mod keys;

use clap::Parser;
use evdev::{uinput::VirtualDevice, AttributeSet, EventType, InputEvent, KeyCode};
use keys::{base_virtual_keys, Chord};
use std::{
    collections::HashSet,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

/// A powerful, universal autoclicker for Linux (Wayland & X11).
/// Works on GNOME, KDE, Hyprland, and others by using kernel-level uinput.
#[derive(Parser, Debug)]
#[command(author = "Dacraezy1", version, about, long_about = None)]
struct Args {
    /// Interval between clicks in milliseconds (autoclick speed)
    #[arg(short, long, default_value_t = 100)]
    interval: u64,

    /// Key, mouse button or key combination that triggers the autoclicker.
    /// Any key works, e.g. F6, F13, F21, X, BTN_SIDE, KEY_KPENTER, or a combo
    /// such as "ctrl+alt+c" or "shift+BTN_SIDE".
    #[arg(short, long, default_value = "F6")]
    toggle_key: String,

    /// Trigger activation mode: 'hold' (autoclick while held down) or 'toggle' (click to toggle on/off)
    #[arg(long, default_value = "toggle")]
    trigger_mode: String,

    /// Hold-to-click flag: autoclick continuously only while holding down the trigger button/key
    #[arg(long, default_value_t = false)]
    hold_to_click: bool,

    /// Mouse button to click (left, right, middle, side, extra)
    #[arg(short, long)]
    button: Option<String>,

    /// Keyboard key or key combination to click or hold (e.g., G, Space, F13, ctrl+c)
    #[arg(short, long)]
    key: Option<String>,

    /// Target button or key (mouse button or key name, e.g., left, right, G, Space)
    #[arg(long)]
    target: Option<String>,

    /// Virtual action mode: 'click' (repeated clicking at interval) or 'hold' (hold button/key down)
    #[arg(short, long, default_value = "click")]
    mode: String,

    /// Virtual hold flag (shorthand for --mode hold)
    #[arg(long, default_value_t = false)]
    hold: bool,

    /// Only validate --toggle-key / --button / --key / --target and exit
    /// (needs no special permissions). Exit code 0 = valid.
    #[arg(long, default_value_t = false)]
    validate: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TriggerMode {
    Toggle, // Click once to toggle ON, click again to toggle OFF
    Hold,   // Autoclick while held down, stop as soon as released
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TargetKind {
    Mouse,
    Keyboard,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ActionMode {
    Click,
    Hold,
}

struct ResolvedTarget {
    /// Keys emitted in order on press (and released in reverse order).
    codes: Vec<KeyCode>,
    name: String,
    kind: TargetKind,
}

/// Parse the action mode, rejecting typos instead of silently falling back.
fn parse_action_mode(args: &Args) -> Result<ActionMode, String> {
    if args.hold {
        return Ok(ActionMode::Hold);
    }
    match args.mode.trim().to_lowercase().as_str() {
        "click" => Ok(ActionMode::Click),
        "hold" => Ok(ActionMode::Hold),
        other => Err(format!("Invalid --mode '{other}': use 'click' or 'hold'.")),
    }
}

fn parse_trigger_mode(args: &Args) -> Result<TriggerMode, String> {
    if args.hold_to_click {
        return Ok(TriggerMode::Hold);
    }
    match args.trigger_mode.trim().to_lowercase().as_str() {
        "toggle" => Ok(TriggerMode::Toggle),
        "hold" => Ok(TriggerMode::Hold),
        other => Err(format!(
            "Invalid --trigger-mode '{other}': use 'toggle' or 'hold'."
        )),
    }
}

fn target_from_chord(chord: Chord, name: &str) -> ResolvedTarget {
    let kind = if chord.is_single_mouse_button() {
        TargetKind::Mouse
    } else {
        TargetKind::Keyboard
    };
    ResolvedTarget {
        codes: chord.primary_codes(),
        name: name.to_string(),
        kind,
    }
}

fn resolve_target(args: &Args, toggle_str: &str) -> Result<ResolvedTarget, String> {
    if let Some(ref target_str) = args.target {
        let chord = Chord::parse(target_str, true)
            .map_err(|e| format!("Invalid target '{target_str}': {e}"))?;
        return Ok(target_from_chord(chord, target_str));
    }

    if let Some(ref key_str) = args.key {
        let chord = Chord::parse(key_str, false)
            .map_err(|e| format!("Invalid key '{key_str}': {e}"))?;
        return Ok(target_from_chord(chord, key_str));
    }

    if let Some(ref btn_str) = args.button {
        let chord = Chord::parse(btn_str, true)
            .map_err(|e| format!("Invalid button '{btn_str}': {e}"))?;
        return Ok(target_from_chord(chord, btn_str));
    }

    // Default: if the trigger is a mouse button, target that same button.
    if let Ok(chord) = Chord::parse(toggle_str, true) {
        if chord.is_single_mouse_button() {
            return Ok(target_from_chord(chord, &toggle_str.to_lowercase()));
        }
    }

    // Otherwise default: left click
    Ok(ResolvedTarget {
        codes: vec![KeyCode::BTN_LEFT],
        name: "left".to_string(),
        kind: TargetKind::Mouse,
    })
}

/// State shared between the input-monitor threads.
struct TriggerState {
    held: HashSet<KeyCode>,
    chord_active: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Transition {
    /// The whole trigger combination just became pressed.
    Pressed,
    /// The trigger combination just stopped being pressed.
    Released,
}

/// Feed one raw key event (value: 0 = release, 1 = press, 2 = autorepeat) into
/// the trigger state and report whether the combination changed state.
fn track_event(
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

fn emit_keys(dev: &Arc<Mutex<VirtualDevice>>, codes: &[KeyCode], value: i32) {
    let mut events: Vec<InputEvent> = Vec::with_capacity(codes.len() + 1);
    if value == 0 {
        for c in codes.iter().rev() {
            events.push(InputEvent::new(EventType::KEY.0, c.0, 0));
        }
    } else {
        for c in codes {
            events.push(InputEvent::new(EventType::KEY.0, c.0, value));
        }
    }
    events.push(InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0));
    if let Ok(mut d) = dev.lock() {
        let _ = d.emit(&events);
    }
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let trigger_chord = Chord::parse(&args.toggle_key, true)
        .map_err(|e| format!("Invalid toggle/trigger key '{}': {}", args.toggle_key, e))?;
    let target = resolve_target(&args, &args.toggle_key)?;
    let trigger_mode = parse_trigger_mode(&args)?;
    let action_mode = parse_action_mode(&args)?;

    if args.validate {
        println!("OK");
        return Ok(());
    }

    println!("======================================================");
    println!("  Wayclicker Universal Linux Autoclicker (Wayland/X11) ");
    println!("======================================================");
    println!(
        "Trigger Key/Button : {} ({:?})",
        args.toggle_key, trigger_mode
    );
    println!(
        "Action Target      : {:?} ({})",
        target.kind, target.name
    );
    println!("Action Mode        : {:?}", action_mode);
    match action_mode {
        ActionMode::Click => println!("Autoclick Speed    : {}ms interval", args.interval),
        ActionMode::Hold => println!("Autoclick Speed    : n/a (target is held down, not clicked)"),
    }

    match (trigger_mode, action_mode) {
        (TriggerMode::Hold, ActionMode::Click) => println!(
            "How to use         : HOLD DOWN '{}' to autoclick. Stops immediately when released.",
            args.toggle_key
        ),
        (TriggerMode::Toggle, ActionMode::Click) => println!(
            "How to use         : TAP '{}' once to start autoclicking, tap again to stop.",
            args.toggle_key
        ),
        (TriggerMode::Hold, ActionMode::Hold) => println!(
            "How to use         : HOLD DOWN '{}' to hold '{}' down. Released when you let go.",
            args.toggle_key, target.name
        ),
        (TriggerMode::Toggle, ActionMode::Hold) => println!(
            "How to use         : TAP '{}' once to hold '{}' down, tap again to release.",
            args.toggle_key, target.name
        ),
    }
    println!("NOTE: Requires input device permissions (sudo, pkexec, or uinput group).");
    println!("------------------------------------------------------");

    // Shared state: whether the action loop should be active, and trigger tracking.
    let clicking_enabled = Arc::new(AtomicBool::new(false));
    let trigger_state = Arc::new(Mutex::new(TriggerState {
        held: HashSet::new(),
        chord_active: false,
    }));

    let running = Arc::new(AtomicBool::new(true));
    let running_ctrlc = Arc::clone(&running);
    let running_loop = Arc::clone(&running);

    // Graceful shutdown on SIGINT / SIGTERM / SIGHUP (the GUI's Stop button sends SIGTERM)
    if let Err(e) = ctrlc::set_handler(move || {
        running_ctrlc.store(false, Ordering::SeqCst);
    }) {
        eprintln!("Warning: Could not set signal handler: {}", e);
    }

    // --- Enumerate physical input devices BEFORE creating the virtual device ---
    let chord_codes = trigger_chord.all_codes();
    let mut candidate_devices = Vec::new();
    for (_, d) in evdev::enumerate() {
        if let Some(name) = d.name() {
            if name.contains("Wayclicker") {
                continue;
            }
        }
        if let Some(supported) = d.supported_keys() {
            if chord_codes.iter().any(|c| supported.contains(*c)) {
                candidate_devices.push(d);
            }
        }
    }

    // Fallback if no device reported explicit support for the trigger keys
    if candidate_devices.is_empty() {
        for (_, d) in evdev::enumerate() {
            if let Some(name) = d.name() {
                if name.contains("Wayclicker") {
                    continue;
                }
            }
            if d.supported_events().contains(EventType::KEY) {
                candidate_devices.push(d);
            }
        }
    }

    // --- Virtual Device Creation (uinput) ---
    let mut keys = AttributeSet::<KeyCode>::new();
    for code in base_virtual_keys() {
        keys.insert(code);
    }
    for code in &target.codes {
        keys.insert(*code);
    }

    let virtual_device = VirtualDevice::builder()?
        .name("Wayclicker Virtual Device")
        .with_keys(&keys)?
        .build()
        .map_err(|e| format!("Failed to create virtual device: {}. (Did you run with sudo?)", e))?;

    let virtual_device = Arc::new(Mutex::new(virtual_device));

    if candidate_devices.is_empty() {
        eprintln!("No input device found to monitor for trigger key '{}'.", args.toggle_key);
        eprintln!("Warning: Monitoring disabled. Ensure you run with appropriate permissions.");
    } else {
        for mut device in candidate_devices {
            let dev_name = device.name().unwrap_or("unnamed").to_string();
            println!("Monitoring input device: {}", dev_name);
            let enabled = Arc::clone(&clicking_enabled);
            let state = Arc::clone(&trigger_state);
            let run_flag = Arc::clone(&running);
            let chord = trigger_chord.clone();
            let trigger_name = args.toggle_key.clone();

            thread::spawn(move || {
                while run_flag.load(Ordering::Relaxed) {
                    let events = match device.fetch_events() {
                        Ok(ev) => ev,
                        Err(_) => break,
                    };
                    for event in events {
                        let evdev::EventSummary::Key(_, key, value) = event.destructure() else {
                            continue;
                        };
                        let transition = {
                            let mut st = state.lock().unwrap();
                            track_event(&mut st, &chord, key, value)
                        };

                        match trigger_mode {
                            TriggerMode::Toggle => {
                                // Fire once each time the whole combination becomes pressed.
                                if transition == Some(Transition::Pressed) {
                                    let on = !enabled.load(Ordering::SeqCst);
                                    enabled.store(on, Ordering::SeqCst);
                                    println!("Autoclicker toggled: {}", if on { "ON" } else { "OFF" });
                                }
                            }
                            TriggerMode::Hold => {
                                if transition == Some(Transition::Pressed) {
                                    enabled.store(true, Ordering::SeqCst);
                                    println!("Autoclicker: ACTIVE (holding {})", trigger_name);
                                } else if transition == Some(Transition::Released) {
                                    enabled.store(false, Ordering::SeqCst);
                                    println!("Autoclicker: STOPPED (released {})", trigger_name);
                                }
                            }
                        }
                    }
                }
            });
        }
    }

    // --- Action Loop (Main Thread) ---
    let click_interval = Duration::from_millis(args.interval.max(1));
    let press_duration = Duration::from_millis(5.min(args.interval.max(2) / 2));
    let mut is_pressed = false;

    while running_loop.load(Ordering::Relaxed) {
        let enabled = clicking_enabled.load(Ordering::SeqCst);

        match action_mode {
            ActionMode::Hold => {
                if enabled && !is_pressed {
                    emit_keys(&virtual_device, &target.codes, 1);
                    is_pressed = true;
                } else if !enabled && is_pressed {
                    emit_keys(&virtual_device, &target.codes, 0);
                    is_pressed = false;
                }
                thread::sleep(Duration::from_millis(10));
            }
            ActionMode::Click => {
                if enabled {
                    emit_keys(&virtual_device, &target.codes, 1);
                    thread::sleep(press_duration);
                    emit_keys(&virtual_device, &target.codes, 0);

                    // Sleep remaining interval in small responsive increments (5ms)
                    let sleep_time = click_interval.saturating_sub(press_duration);
                    if sleep_time > Duration::ZERO {
                        let step = Duration::from_millis(5);
                        let mut elapsed = Duration::ZERO;
                        while elapsed < sleep_time
                            && clicking_enabled.load(Ordering::SeqCst)
                            && running_loop.load(Ordering::Relaxed)
                        {
                            let to_sleep = (sleep_time - elapsed).min(step);
                            thread::sleep(to_sleep);
                            elapsed += to_sleep;
                        }
                    }
                } else {
                    thread::sleep(Duration::from_millis(5));
                }
            }
        }
    }

    // Clean exit: ensure target key(s) are released
    if is_pressed {
        emit_keys(&virtual_device, &target.codes, 0);
    }

    println!("Wayclicker stopped cleanly.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_args() -> Args {
        Args {
            interval: 100,
            toggle_key: "F6".to_string(),
            trigger_mode: "toggle".to_string(),
            hold_to_click: false,
            button: None,
            key: None,
            target: None,
            mode: "click".to_string(),
            hold: false,
            validate: false,
        }
    }

    #[test]
    fn test_resolve_target_defaults() {
        // Default target with F6 toggle is left click
        let t = resolve_target(&base_args(), "F6").unwrap();
        assert_eq!(t.kind, TargetKind::Mouse);
        assert_eq!(t.codes, vec![KeyCode::BTN_LEFT]);

        // Auto-match target to mouse toggle key
        let mut a = base_args();
        a.toggle_key = "right".into();
        a.trigger_mode = "hold".into();
        a.hold_to_click = true;
        let t = resolve_target(&a, "right").unwrap();
        assert_eq!(t.kind, TargetKind::Mouse);
        assert_eq!(t.codes, vec![KeyCode::BTN_RIGHT]);
    }

    #[test]
    fn test_resolve_target_keyboard_and_combo() {
        let mut a = base_args();
        a.key = Some("G".into());
        let t = resolve_target(&a, "F6").unwrap();
        assert_eq!(t.kind, TargetKind::Keyboard);
        assert_eq!(t.codes, vec![KeyCode::KEY_G]);

        a.key = Some("ctrl+c".into());
        let t = resolve_target(&a, "F6").unwrap();
        assert_eq!(t.kind, TargetKind::Keyboard);
        assert_eq!(t.codes, vec![KeyCode::KEY_LEFTCTRL, KeyCode::KEY_C]);

        // --key left means the arrow key, --button left means the mouse button
        a.key = Some("left".into());
        assert_eq!(resolve_target(&a, "F6").unwrap().codes, vec![KeyCode::KEY_LEFT]);
        a.key = None;
        a.button = Some("left".into());
        assert_eq!(resolve_target(&a, "F6").unwrap().codes, vec![KeyCode::BTN_LEFT]);
    }

    #[test]
    fn test_resolve_target_rejects_garbage() {
        let mut a = base_args();
        a.key = Some("nope".into());
        assert!(resolve_target(&a, "F6").is_err());
    }

    #[test]
    fn test_modes() {
        let mut a = base_args();
        assert_eq!(parse_action_mode(&a).unwrap(), ActionMode::Click);
        assert_eq!(parse_trigger_mode(&a).unwrap(), TriggerMode::Toggle);

        a.mode = "HOLD".into();
        assert_eq!(parse_action_mode(&a).unwrap(), ActionMode::Hold);
        a.mode = "click".into();
        a.hold = true;
        assert_eq!(parse_action_mode(&a).unwrap(), ActionMode::Hold);

        a.hold = false;
        a.mode = "holdd".into();
        assert!(parse_action_mode(&a).is_err());

        a.trigger_mode = "hold".into();
        assert_eq!(parse_trigger_mode(&a).unwrap(), TriggerMode::Hold);
        a.trigger_mode = "bogus".into();
        assert!(parse_trigger_mode(&a).is_err());
    }

    fn run_events(chord: &str, events: &[(KeyCode, i32)]) -> Vec<Option<Transition>> {
        let chord = Chord::parse(chord, true).unwrap();
        let mut st = TriggerState { held: HashSet::new(), chord_active: false };
        events.iter().map(|(k, v)| track_event(&mut st, &chord, *k, *v)).collect()
    }

    #[test]
    fn trigger_single_key_f13() {
        let t = run_events("F13", &[(KeyCode::KEY_F13, 1), (KeyCode::KEY_F13, 2), (KeyCode::KEY_F13, 0)]);
        assert_eq!(t, vec![Some(Transition::Pressed), None, Some(Transition::Released)]);
    }

    #[test]
    fn trigger_ctrl_alt_c_fires_only_when_complete() {
        let t = run_events("ctrl+alt+c", &[
            (KeyCode::KEY_LEFTCTRL, 1), (KeyCode::KEY_LEFTALT, 1), (KeyCode::KEY_C, 1), // complete -> Pressed
            (KeyCode::KEY_C, 2),                                      // autorepeat -> nothing
            (KeyCode::KEY_C, 0),                                      // released -> Released
            (KeyCode::KEY_C, 1),                                      // modifiers still held -> Pressed again
            (KeyCode::KEY_C, 0), (KeyCode::KEY_LEFTALT, 0), (KeyCode::KEY_LEFTCTRL, 0),
        ]);
        assert_eq!(t, vec![
            None, None, Some(Transition::Pressed),
            None,
            Some(Transition::Released),
            Some(Transition::Pressed),
            Some(Transition::Released), None, None,
        ]);
    }

    #[test]
    fn trigger_partial_combo_never_fires() {
        let t = run_events("ctrl+alt+c", &[(KeyCode::KEY_LEFTCTRL, 1), (KeyCode::KEY_C, 1), (KeyCode::KEY_C, 0), (KeyCode::KEY_LEFTCTRL, 0)]);
        assert!(t.iter().all(|x| x.is_none()));
    }

    #[test]
    fn trigger_combo_any_press_order() {
        let t = run_events("ctrl+alt+c", &[(KeyCode::KEY_C, 1), (KeyCode::KEY_RIGHTALT, 1), (KeyCode::KEY_RIGHTCTRL, 1)]);
        assert_eq!(t, vec![None, None, Some(Transition::Pressed)]);
    }

    #[test]
    fn trigger_hold_releases_when_any_part_lifted() {
        let t = run_events("ctrl+c", &[(KeyCode::KEY_LEFTCTRL, 1), (KeyCode::KEY_C, 1), (KeyCode::KEY_LEFTCTRL, 0)]);
        assert_eq!(t, vec![None, Some(Transition::Pressed), Some(Transition::Released)]);
    }
}

