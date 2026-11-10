//! Hotkey monitoring: reads physical input devices, tracks which keys are
//! held and reports when the trigger combination is pressed / released.
//!
//! Devices are re-scanned in the background, so a keyboard or mouse that is
//! plugged in (or reconnects) after start-up works without restarting.

use crate::keys::Chord;
use evdev::{Device, EventSummary, EventType, KeyCode};
use std::{
    collections::HashSet,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

/// How often `/dev/input` is re-scanned for new devices.
const RESCAN_INTERVAL: Duration = Duration::from_secs(2);

/// Name given to our own virtual device. It must never be monitored,
/// otherwise our synthetic clicks would feed back into the trigger.
pub const VIRTUAL_DEVICE_NAME: &str = "Wayclicker Virtual Device";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TriggerMode {
    /// Press once to start, press again to stop.
    Toggle,
    /// Active only while the trigger is held down.
    Hold,
}

/// State shared between all device-monitor threads.
pub struct TriggerState {
    pub held: HashSet<KeyCode>,
    pub chord_active: bool,
}

impl TriggerState {
    pub fn new() -> Self {
        Self {
            held: HashSet::new(),
            chord_active: false,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transition {
    /// The whole trigger combination just became pressed.
    Pressed,
    /// The trigger combination just stopped being pressed.
    Released,
}

/// Feed one raw key event (value: 0 = release, 1 = press, 2 = autorepeat) into
/// the trigger state and report whether the combination changed state.
pub fn track_event(
    st: &mut TriggerState,
    chord: &Chord,
    key: KeyCode,
    value: i32,
) -> Option<Transition> {
    match value {
        0 => {
            st.held.remove(&key);
        }
        1 | 2 => {
            st.held.insert(key);
        }
        _ => return None,
    }
    let now_active = chord.is_pressed(&st.held);
    let was_active = st.chord_active;
    st.chord_active = now_active;
    match (was_active, now_active) {
        (false, true) => Some(Transition::Pressed),
        (true, false) => Some(Transition::Released),
        _ => None,
    }
}

/// Everything a monitor thread needs.
#[derive(Clone)]
pub struct Monitor {
    pub chord: Chord,
    pub trigger_name: String,
    pub mode: TriggerMode,
    /// Whether the action loop should currently be active.
    pub enabled: Arc<AtomicBool>,
    /// Cleared on shutdown.
    pub running: Arc<AtomicBool>,
    state: Arc<Mutex<TriggerState>>,
}

impl Monitor {
    pub fn new(
        chord: Chord,
        trigger_name: String,
        mode: TriggerMode,
        enabled: Arc<AtomicBool>,
        running: Arc<AtomicBool>,
    ) -> Self {
        Self {
            chord,
            trigger_name,
            mode,
            enabled,
            running,
            state: Arc::new(Mutex::new(TriggerState::new())),
        }
    }

    fn apply(&self, transition: Option<Transition>) {
        match (self.mode, transition) {
            (TriggerMode::Toggle, Some(Transition::Pressed)) => {
                let on = !self.enabled.load(Ordering::SeqCst);
                self.enabled.store(on, Ordering::SeqCst);
                println!("Autoclicker toggled: {}", if on { "ON" } else { "OFF" });
            }
            (TriggerMode::Hold, Some(Transition::Pressed)) => {
                self.enabled.store(true, Ordering::SeqCst);
                println!("Autoclicker: ACTIVE (holding {})", self.trigger_name);
            }
            (TriggerMode::Hold, Some(Transition::Released)) => {
                self.enabled.store(false, Ordering::SeqCst);
                println!("Autoclicker: STOPPED (released {})", self.trigger_name);
            }
            _ => {}
        }
    }

    fn feed(&self, key: KeyCode, value: i32) {
        let transition = match self.state.lock() {
            Ok(mut st) => track_event(&mut st, &self.chord, key, value),
            Err(_) => return,
        };
        self.apply(transition);
    }

    /// Run until the device disappears or the program stops.
    fn watch(&self, mut device: Device) {
        // Keys this particular device has pressed. When the device vanishes
        // while a key is down, they are released so nothing gets stuck.
        let mut local: HashSet<KeyCode> = HashSet::new();
        while self.running.load(Ordering::Relaxed) {
            let events = match device.fetch_events() {
                Ok(ev) => ev,
                Err(_) => break,
            };
            for event in events {
                let EventSummary::Key(_, key, value) = event.destructure() else {
                    continue;
                };
                match value {
                    0 => {
                        local.remove(&key);
                    }
                    1 | 2 => {
                        local.insert(key);
                    }
                    _ => {}
                }
                self.feed(key, value);
            }
        }
        for key in local {
            self.feed(key, 0);
        }
    }
}

fn is_our_device(device: &Device) -> bool {
    device
        .name()
        .map(|n| n.contains("Wayclicker"))
        .unwrap_or(false)
}

pub fn event_paths() -> Vec<PathBuf> {
    let mut out: Vec<PathBuf> = std::fs::read_dir("/dev/input")
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.starts_with("event"))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default();
    out.sort();
    out
}

/// Can this device send any of the keys of the trigger?
fn supports_trigger(device: &Device, codes: &[KeyCode]) -> bool {
    device
        .supported_keys()
        .map(|keys| codes.iter().any(|c| keys.contains(*c)))
        .unwrap_or(false)
}

fn has_any_keys(device: &Device) -> bool {
    device.supported_events().contains(EventType::KEY)
}

/// Starts monitoring in the background. Returns how many devices were found
/// right now (more may appear later).
pub fn start(monitor: Monitor) -> usize {
    let codes = monitor.chord.all_codes();
    let watched: Arc<Mutex<HashSet<PathBuf>>> = Arc::new(Mutex::new(HashSet::new()));

    let initial = scan(&monitor, &codes, &watched, &mut HashSet::new(), true);

    let rescan_monitor = monitor.clone();
    thread::spawn(move || {
        let mut ignored: HashSet<PathBuf> = HashSet::new();
        while rescan_monitor.running.load(Ordering::Relaxed) {
            thread::sleep(RESCAN_INTERVAL);
            scan(&rescan_monitor, &codes, &watched, &mut ignored, false);
        }
    });
    initial
}

/// One scan pass. `allow_fallback` lets the very first scan watch every
/// keyboard-like device if none advertised support for the trigger keys.
fn scan(
    monitor: &Monitor,
    codes: &[KeyCode],
    watched: &Arc<Mutex<HashSet<PathBuf>>>,
    ignored: &mut HashSet<PathBuf>,
    allow_fallback: bool,
) -> usize {
    let paths = event_paths();
    // Forget ignored paths that no longer exist, so a re-plugged device that
    // re-uses the node is looked at again.
    ignored.retain(|p| paths.contains(p));

    let mut fallback: Vec<(PathBuf, Device)> = Vec::new();
    let mut started = 0usize;

    for path in paths {
        if ignored.contains(&path) || is_watched(watched, &path) {
            continue;
        }
        let Ok(device) = Device::open(&path) else {
            continue; // no permission or vanished: try again next time
        };
        if is_our_device(&device) {
            ignored.insert(path);
            continue;
        }
        if supports_trigger(&device, codes) {
            spawn_watch(monitor, watched, path, device);
            started += 1;
        } else if allow_fallback && has_any_keys(&device) {
            fallback.push((path, device));
        } else {
            ignored.insert(path);
        }
    }

    if started == 0 && allow_fallback {
        for (path, device) in fallback {
            spawn_watch(monitor, watched, path, device);
            started += 1;
        }
    }
    started
}

fn is_watched(watched: &Arc<Mutex<HashSet<PathBuf>>>, path: &Path) -> bool {
    watched.lock().map(|w| w.contains(path)).unwrap_or(false)
}

fn spawn_watch(
    monitor: &Monitor,
    watched: &Arc<Mutex<HashSet<PathBuf>>>,
    path: PathBuf,
    device: Device,
) {
    let name = device.name().unwrap_or("unnamed").to_string();
    println!("Monitoring input device: {name}");
    if let Ok(mut w) = watched.lock() {
        w.insert(path.clone());
    }
    let monitor = monitor.clone();
    let watched = Arc::clone(watched);
    thread::spawn(move || {
        monitor.watch(device);
        if let Ok(mut w) = watched.lock() {
            w.remove(&path);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_events(chord: &str, events: &[(KeyCode, i32)]) -> Vec<Option<Transition>> {
        let chord = Chord::parse(chord, true).unwrap();
        let mut st = TriggerState::new();
        events
            .iter()
            .map(|(k, v)| track_event(&mut st, &chord, *k, *v))
            .collect()
    }

    #[test]
    fn trigger_single_key_f13() {
        let t = run_events(
            "F13",
            &[(KeyCode::KEY_F13, 1), (KeyCode::KEY_F13, 2), (KeyCode::KEY_F13, 0)],
        );
        assert_eq!(t, vec![Some(Transition::Pressed), None, Some(Transition::Released)]);
    }

    #[test]
    fn trigger_ctrl_alt_c_fires_only_when_complete() {
        let t = run_events(
            "ctrl+alt+c",
            &[
                (KeyCode::KEY_LEFTCTRL, 1),
                (KeyCode::KEY_LEFTALT, 1),
                (KeyCode::KEY_C, 1), // complete -> Pressed
                (KeyCode::KEY_C, 2), // autorepeat -> nothing
                (KeyCode::KEY_C, 0), // released -> Released
                (KeyCode::KEY_C, 1), // modifiers still held -> Pressed again
                (KeyCode::KEY_C, 0),
                (KeyCode::KEY_LEFTALT, 0),
                (KeyCode::KEY_LEFTCTRL, 0),
            ],
        );
        assert_eq!(
            t,
            vec![
                None,
                None,
                Some(Transition::Pressed),
                None,
                Some(Transition::Released),
                Some(Transition::Pressed),
                Some(Transition::Released),
                None,
                None,
            ]
        );
    }

    #[test]
    fn trigger_partial_combo_never_fires() {
        let t = run_events(
            "ctrl+alt+c",
            &[
                (KeyCode::KEY_LEFTCTRL, 1),
                (KeyCode::KEY_C, 1),
                (KeyCode::KEY_C, 0),
                (KeyCode::KEY_LEFTCTRL, 0),
            ],
        );
        assert!(t.iter().all(|x| x.is_none()));
    }

    #[test]
    fn trigger_combo_any_press_order() {
        let t = run_events(
            "ctrl+alt+c",
            &[
                (KeyCode::KEY_C, 1),
                (KeyCode::KEY_RIGHTALT, 1),
                (KeyCode::KEY_RIGHTCTRL, 1),
            ],
        );
        assert_eq!(t, vec![None, None, Some(Transition::Pressed)]);
    }

    #[test]
    fn trigger_hold_releases_when_any_part_lifted() {
        let t = run_events(
            "ctrl+c",
            &[(KeyCode::KEY_LEFTCTRL, 1), (KeyCode::KEY_C, 1), (KeyCode::KEY_LEFTCTRL, 0)],
        );
        assert_eq!(t, vec![None, Some(Transition::Pressed), Some(Transition::Released)]);
    }

    #[test]
    fn hold_mode_enables_and_disables() {
        let enabled = Arc::new(AtomicBool::new(false));
        let m = Monitor::new(
            Chord::parse("F6", true).unwrap(),
            "F6".into(),
            TriggerMode::Hold,
            Arc::clone(&enabled),
            Arc::new(AtomicBool::new(true)),
        );
        m.feed(KeyCode::KEY_F6, 1);
        assert!(enabled.load(Ordering::SeqCst));
        m.feed(KeyCode::KEY_F6, 0);
        assert!(!enabled.load(Ordering::SeqCst));
    }

    #[test]
    fn toggle_mode_flips_on_each_press() {
        let enabled = Arc::new(AtomicBool::new(false));
        let m = Monitor::new(
            Chord::parse("F6", true).unwrap(),
            "F6".into(),
            TriggerMode::Toggle,
            Arc::clone(&enabled),
            Arc::new(AtomicBool::new(true)),
        );
        m.feed(KeyCode::KEY_F6, 1);
        m.feed(KeyCode::KEY_F6, 0);
        assert!(enabled.load(Ordering::SeqCst));
        m.feed(KeyCode::KEY_F6, 1);
        m.feed(KeyCode::KEY_F6, 0);
        assert!(!enabled.load(Ordering::SeqCst));
    }
}
