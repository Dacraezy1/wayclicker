mod keys;
mod monitor;

use clap::Parser;
use evdev::{
    uinput::VirtualDevice, AttributeSet, EventType, InputEvent, KeyCode, RelativeAxisCode,
};
use keys::{base_virtual_keys, Chord};
use monitor::{Monitor, TriggerMode, VIRTUAL_DEVICE_NAME};
use std::{
    fs::{File, OpenOptions},
    io::BufRead,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

/// Universal autoclicker for Linux (Wayland & X11).
/// Works on every desktop because it uses kernel-level uinput.
#[derive(Parser, Debug)]
#[command(author = "Dacraezy1", version, about, long_about = None)]
struct Args {
    /// Milliseconds between clicks (ignored in hold mode)
    #[arg(short, long, default_value_t = 100)]
    interval: u64,

    /// Key, mouse button or combo that starts/stops the autoclicker.
    /// Examples: F6, F13, X, BTN_SIDE, KEY_KPENTER, ctrl+alt+c, shift+BTN_SIDE
    #[arg(short, long, default_value = "F6")]
    toggle_key: String,

    /// How the trigger behaves: 'toggle' (press to start/stop) or 'hold' (active while held)
    #[arg(long, default_value = "toggle")]
    trigger_mode: String,

    /// Shorthand for --trigger-mode hold
    #[arg(long, default_value_t = false)]
    hold_to_click: bool,

    /// Mouse button to click (left, right, middle, side, extra)
    #[arg(short, long)]
    button: Option<String>,

    /// Keyboard key or combo to press (e.g. G, Space, F13, ctrl+c)
    #[arg(short, long)]
    key: Option<String>,

    /// Target button or key (mouse button or key name)
    #[arg(long)]
    target: Option<String>,

    /// What to do with the target: 'click' (repeat at --interval) or 'hold' (keep pressed down)
    #[arg(short, long, default_value = "click")]
    mode: String,

    /// Shorthand for --mode hold
    #[arg(long, default_value_t = false)]
    hold: bool,

    /// Only validate --toggle-key / --button / --key / --target and exit
    /// (needs no special permissions). Exit code 0 = valid.
    #[arg(long, default_value_t = false)]
    validate: bool,

    /// Check whether this user can run Wayclicker without root (access to
    /// /dev/uinput and /dev/input/event*) and exit. Exit code 0 = yes.
    #[arg(long, default_value_t = false)]
    check_access: bool,

    /// Used by the GUI: stop when a line "stop" arrives on stdin or when
    /// stdin is closed, so a closed GUI never leaves a clicker running.
    #[arg(long, default_value_t = false)]
    stdin_control: bool,
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

/// Press (value 1) or release (value 0) every key of the target.
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

/// True when this user can create the virtual device and read input devices.
fn check_access() -> bool {
    let uinput_ok = ["/dev/uinput", "/dev/input/uinput"]
        .iter()
        .any(|p| OpenOptions::new().write(true).open(p).is_ok());
    let readable = monitor::event_paths()
        .iter()
        .filter(|p| File::open(p).is_ok())
        .count();

    if !uinput_ok {
        eprintln!("No write access to /dev/uinput.");
    }
    if readable == 0 {
        eprintln!("No read access to /dev/input/event* (add yourself to the 'input' group).");
    }
    uinput_ok && readable > 0
}

fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

fn describe_usage(
    trigger_mode: TriggerMode,
    action_mode: ActionMode,
    trigger: &str,
    target: &str,
) -> String {
    match (trigger_mode, action_mode) {
        (TriggerMode::Hold, ActionMode::Click) => {
            format!("HOLD '{trigger}' to autoclick. It stops when you let go.")
        }
        (TriggerMode::Toggle, ActionMode::Click) => {
            format!("TAP '{trigger}' to start autoclicking, tap again to stop.")
        }
        (TriggerMode::Hold, ActionMode::Hold) => {
            format!("HOLD '{trigger}' to keep '{target}' held down. It is released when you let go.")
        }
        (TriggerMode::Toggle, ActionMode::Hold) => {
            format!("TAP '{trigger}' to hold '{target}' down, tap again to release.")
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    if args.check_access {
        if check_access() {
            println!("OK");
            return Ok(());
        }
        std::process::exit(1);
    }

    let trigger_chord = Chord::parse(&args.toggle_key, true)
        .map_err(|e| format!("Invalid trigger key '{}': {}", args.toggle_key, e))?;
    let target = resolve_target(&args, &args.toggle_key)?;
    let trigger_mode = parse_trigger_mode(&args)?;
    let action_mode = parse_action_mode(&args)?;

    if args.validate {
        println!("OK");
        return Ok(());
    }

    println!("Wayclicker {}", env!("CARGO_PKG_VERSION"));
    println!("Trigger : {} ({:?})", args.toggle_key, trigger_mode);
    println!("Target  : {} ({:?})", target.name, target.kind);
    match action_mode {
        ActionMode::Click => println!("Action  : click every {} ms", args.interval.max(1)),
        ActionMode::Hold => println!("Action  : hold down"),
    }
    println!(
        "{}",
        describe_usage(trigger_mode, action_mode, &args.toggle_key, &target.name)
    );

    // Shared state: whether the action loop should be active.
    let clicking_enabled = Arc::new(AtomicBool::new(false));
    let running = Arc::new(AtomicBool::new(true));

    // Graceful shutdown on SIGINT / SIGTERM / SIGHUP.
    let running_ctrlc = Arc::clone(&running);
    if let Err(e) = ctrlc::set_handler(move || {
        running_ctrlc.store(false, Ordering::SeqCst);
    }) {
        eprintln!("Warning: could not set signal handler: {e}");
    }

    // The GUI controls us through stdin: "stop" (or a closed pipe) ends the program.
    if args.stdin_control {
        let running_stdin = Arc::clone(&running);
        thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines() {
                match line {
                    Ok(l) if matches!(l.trim(), "stop" | "quit" | "exit") => break,
                    Ok(_) => continue,
                    Err(_) => break,
                }
            }
            running_stdin.store(false, Ordering::SeqCst);
        });
    }

    // --- Virtual device (uinput) ---
    let mut keys = evdev::AttributeSet::<KeyCode>::new();
    for code in base_virtual_keys() {
        keys.insert(code);
    }
    for code in &target.codes {
        keys.insert(*code);
    }
    // Pointer axes make desktops treat the device as a real mouse so button
    // events are always accepted. No movement is ever sent.
    let mut axes = AttributeSet::<RelativeAxisCode>::new();
    axes.insert(RelativeAxisCode::REL_X);
    axes.insert(RelativeAxisCode::REL_Y);

    let virtual_device = VirtualDevice::builder()
        .map_err(|e| format!("Cannot open /dev/uinput: {e}. Run with sudo or see the README (Permissions)."))?
        .name(VIRTUAL_DEVICE_NAME)
        .with_keys(&keys)?
        .with_relative_axes(&axes)?
        .build()
        .map_err(|e| format!("Failed to create virtual device: {e}. Run with sudo or see the README (Permissions)."))?;
    let virtual_device = Arc::new(Mutex::new(virtual_device));

    // --- Hotkey monitoring (hot-plug aware) ---
    let found = monitor::start(Monitor::new(
        trigger_chord,
        args.toggle_key.clone(),
        trigger_mode,
        Arc::clone(&clicking_enabled),
        Arc::clone(&running),
    ));
    if found == 0 {
        eprintln!(
            "Warning: no readable input device found for '{}'. Run with sudo, or add yourself to the 'input' group.",
            args.toggle_key
        );
    }
    println!("Ready.");

    // --- Action loop (main thread) ---
    let click_interval = Duration::from_millis(args.interval.max(1));
    let press_duration = Duration::from_millis(5.min(args.interval.max(2) / 2));
    let mut is_pressed = false;

    while running.load(Ordering::Relaxed) {
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

                    // Wait out the rest of the interval in small steps so
                    // stopping always feels instant.
                    let sleep_time = click_interval.saturating_sub(press_duration);
                    let step = Duration::from_millis(5);
                    let mut elapsed = Duration::ZERO;
                    while elapsed < sleep_time
                        && clicking_enabled.load(Ordering::SeqCst)
                        && running.load(Ordering::Relaxed)
                    {
                        let to_sleep = (sleep_time - elapsed).min(step);
                        thread::sleep(to_sleep);
                        elapsed += to_sleep;
                    }
                } else {
                    thread::sleep(Duration::from_millis(5));
                }
            }
        }
    }

    // Clean exit: never leave a key or button stuck down.
    if is_pressed {
        emit_keys(&virtual_device, &target.codes, 0);
    }

    println!("Wayclicker stopped.");
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
            check_access: false,
            stdin_control: false,
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
}
