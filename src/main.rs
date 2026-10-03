use clap::Parser;
use evdev::{
    uinput::VirtualDevice, AttributeSet, EventType, InputEvent, KeyCode,
};
use std::{
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
    /// Interval between clicks in milliseconds (for click/repeat mode)
    #[arg(short, long, default_value_t = 100)]
    interval: u64,

    /// Key to toggle the autoclicker on/off (e.g., F6, X, BTN_LEFT, BTN_SIDE)
    #[arg(short, long, default_value = "F6")]
    toggle_key: String,

    /// Mouse button to click (left, right, middle, side, extra)
    #[arg(short, long)]
    button: Option<String>,

    /// Keyboard key to click or hold (e.g., G, F, Space, Enter, W, 1)
    #[arg(short, long)]
    key: Option<String>,

    /// Target button or key (mouse button or key name, e.g., left, right, G, Space)
    #[arg(long)]
    target: Option<String>,

    /// Mode of operation: 'click' (repeated clicking) or 'hold' (press and hold down)
    #[arg(short, long, default_value = "click")]
    mode: String,

    /// Hold mode flag (shorthand for --mode hold)
    #[arg(long, default_value_t = false)]
    hold: bool,
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
    code: KeyCode,
    name: String,
    kind: TargetKind,
}

// Function to parse the mouse button string into a KeyCode
fn parse_mouse_button(button_str: &str) -> Option<KeyCode> {
    match button_str.to_lowercase().as_str() {
        "left" | "btn_left" => Some(KeyCode::BTN_LEFT),
        "right" | "btn_right" => Some(KeyCode::BTN_RIGHT),
        "middle" | "btn_middle" => Some(KeyCode::BTN_MIDDLE),
        "side" | "back" | "btn_side" => Some(KeyCode::BTN_SIDE),
        "extra" | "forward" | "btn_extra" => Some(KeyCode::BTN_EXTRA),
        _ => None,
    }
}

// Function to parse keyboard key string into an evdev::KeyCode
fn parse_keyboard_key(key_str: &str) -> Option<KeyCode> {
    match key_str.to_uppercase().as_str() {
        // Digits
        "0" => Some(KeyCode::KEY_0),
        "1" => Some(KeyCode::KEY_1),
        "2" => Some(KeyCode::KEY_2),
        "3" => Some(KeyCode::KEY_3),
        "4" => Some(KeyCode::KEY_4),
        "5" => Some(KeyCode::KEY_5),
        "6" => Some(KeyCode::KEY_6),
        "7" => Some(KeyCode::KEY_7),
        "8" => Some(KeyCode::KEY_8),
        "9" => Some(KeyCode::KEY_9),
        // Function keys
        "F1" => Some(KeyCode::KEY_F1),
        "F2" => Some(KeyCode::KEY_F2),
        "F3" => Some(KeyCode::KEY_F3),
        "F4" => Some(KeyCode::KEY_F4),
        "F5" => Some(KeyCode::KEY_F5),
        "F6" => Some(KeyCode::KEY_F6),
        "F7" => Some(KeyCode::KEY_F7),
        "F8" => Some(KeyCode::KEY_F8),
        "F9" => Some(KeyCode::KEY_F9),
        "F10" => Some(KeyCode::KEY_F10),
        "F11" => Some(KeyCode::KEY_F11),
        "F12" => Some(KeyCode::KEY_F12),
        // Letters
        "A" => Some(KeyCode::KEY_A),
        "B" => Some(KeyCode::KEY_B),
        "C" => Some(KeyCode::KEY_C),
        "D" => Some(KeyCode::KEY_D),
        "E" => Some(KeyCode::KEY_E),
        "F" => Some(KeyCode::KEY_F),
        "G" => Some(KeyCode::KEY_G),
        "H" => Some(KeyCode::KEY_H),
        "I" => Some(KeyCode::KEY_I),
        "J" => Some(KeyCode::KEY_J),
        "K" => Some(KeyCode::KEY_K),
        "L" => Some(KeyCode::KEY_L),
        "M" => Some(KeyCode::KEY_M),
        "N" => Some(KeyCode::KEY_N),
        "O" => Some(KeyCode::KEY_O),
        "P" => Some(KeyCode::KEY_P),
        "Q" => Some(KeyCode::KEY_Q),
        "R" => Some(KeyCode::KEY_R),
        "S" => Some(KeyCode::KEY_S),
        "T" => Some(KeyCode::KEY_T),
        "U" => Some(KeyCode::KEY_U),
        "V" => Some(KeyCode::KEY_V),
        "W" => Some(KeyCode::KEY_W),
        "X" => Some(KeyCode::KEY_X),
        "Y" => Some(KeyCode::KEY_Y),
        "Z" => Some(KeyCode::KEY_Z),
        // Modifiers & Navigation
        "ESC" | "ESCAPE" => Some(KeyCode::KEY_ESC),
        "TAB" => Some(KeyCode::KEY_TAB),
        "CAPSLOCK" | "CAPS" => Some(KeyCode::KEY_CAPSLOCK),
        "LEFTSHIFT" | "SHIFT" => Some(KeyCode::KEY_LEFTSHIFT),
        "RIGHTSHIFT" => Some(KeyCode::KEY_RIGHTSHIFT),
        "LEFTCTRL" | "CTRL" => Some(KeyCode::KEY_LEFTCTRL),
        "RIGHTCTRL" => Some(KeyCode::KEY_RIGHTCTRL),
        "LEFTALT" | "ALT" => Some(KeyCode::KEY_LEFTALT),
        "RIGHTALT" => Some(KeyCode::KEY_RIGHTALT),
        "SPACE" => Some(KeyCode::KEY_SPACE),
        "ENTER" | "RETURN" => Some(KeyCode::KEY_ENTER),
        "BACKSPACE" => Some(KeyCode::KEY_BACKSPACE),
        "UP" => Some(KeyCode::KEY_UP),
        "DOWN" => Some(KeyCode::KEY_DOWN),
        "LEFT" => Some(KeyCode::KEY_LEFT),
        "RIGHT" => Some(KeyCode::KEY_RIGHT),
        "INSERT" => Some(KeyCode::KEY_INSERT),
        "DELETE" | "DEL" => Some(KeyCode::KEY_DELETE),
        "HOME" => Some(KeyCode::KEY_HOME),
        "END" => Some(KeyCode::KEY_END),
        "PAGEUP" | "PGUP" => Some(KeyCode::KEY_PAGEUP),
        "PAGEDOWN" | "PGDN" => Some(KeyCode::KEY_PAGEDOWN),
        _ => None,
    }
}

// Function to parse toggle key (supports both keyboard keys and mouse buttons)
fn parse_toggle_key(key_str: &str) -> Option<KeyCode> {
    if let Some(code) = parse_mouse_button(key_str) {
        return Some(code);
    }
    parse_keyboard_key(key_str)
}

fn resolve_target(args: &Args) -> Result<ResolvedTarget, String> {
    if let Some(ref target_str) = args.target {
        if let Some(code) = parse_mouse_button(target_str) {
            return Ok(ResolvedTarget {
                code,
                name: target_str.clone(),
                kind: TargetKind::Mouse,
            });
        }
        if let Some(code) = parse_keyboard_key(target_str) {
            return Ok(ResolvedTarget {
                code,
                name: target_str.clone(),
                kind: TargetKind::Keyboard,
            });
        }
        return Err(format!("Invalid target: '{}'. Must be a mouse button (left, right, middle, side, extra) or supported keyboard key.", target_str));
    }

    if let Some(ref key_str) = args.key {
        if let Some(code) = parse_keyboard_key(key_str) {
            return Ok(ResolvedTarget {
                code,
                name: key_str.clone(),
                kind: TargetKind::Keyboard,
            });
        }
        if let Some(code) = parse_mouse_button(key_str) {
            return Ok(ResolvedTarget {
                code,
                name: key_str.clone(),
                kind: TargetKind::Mouse,
            });
        }
        return Err(format!("Invalid key: '{}'. Must be a supported keyboard key (e.g. G, F, Space, 1).", key_str));
    }

    if let Some(ref btn_str) = args.button {
        if let Some(code) = parse_mouse_button(btn_str) {
            return Ok(ResolvedTarget {
                code,
                name: btn_str.clone(),
                kind: TargetKind::Mouse,
            });
        }
        if let Some(code) = parse_keyboard_key(btn_str) {
            return Ok(ResolvedTarget {
                code,
                name: btn_str.clone(),
                kind: TargetKind::Keyboard,
            });
        }
        return Err(format!("Invalid mouse button: '{}'. Use 'left', 'right', 'middle', 'side', or 'extra'.", btn_str));
    }

    // Default: left click
    Ok(ResolvedTarget {
        code: KeyCode::BTN_LEFT,
        name: "left".to_string(),
        kind: TargetKind::Mouse,
    })
}

fn all_supported_keycodes() -> Vec<KeyCode> {
    vec![
        KeyCode::BTN_LEFT, KeyCode::BTN_RIGHT, KeyCode::BTN_MIDDLE,
        KeyCode::BTN_SIDE, KeyCode::BTN_EXTRA, KeyCode::BTN_FORWARD, KeyCode::BTN_BACK,
        KeyCode::KEY_0, KeyCode::KEY_1, KeyCode::KEY_2, KeyCode::KEY_3, KeyCode::KEY_4,
        KeyCode::KEY_5, KeyCode::KEY_6, KeyCode::KEY_7, KeyCode::KEY_8, KeyCode::KEY_9,
        KeyCode::KEY_F1, KeyCode::KEY_F2, KeyCode::KEY_F3, KeyCode::KEY_F4,
        KeyCode::KEY_F5, KeyCode::KEY_F6, KeyCode::KEY_F7, KeyCode::KEY_F8,
        KeyCode::KEY_F9, KeyCode::KEY_F10, KeyCode::KEY_F11, KeyCode::KEY_F12,
        KeyCode::KEY_A, KeyCode::KEY_B, KeyCode::KEY_C, KeyCode::KEY_D, KeyCode::KEY_E,
        KeyCode::KEY_F, KeyCode::KEY_G, KeyCode::KEY_H, KeyCode::KEY_I, KeyCode::KEY_J,
        KeyCode::KEY_K, KeyCode::KEY_L, KeyCode::KEY_M, KeyCode::KEY_N, KeyCode::KEY_O,
        KeyCode::KEY_P, KeyCode::KEY_Q, KeyCode::KEY_R, KeyCode::KEY_S, KeyCode::KEY_T,
        KeyCode::KEY_U, KeyCode::KEY_V, KeyCode::KEY_W, KeyCode::KEY_X, KeyCode::KEY_Y,
        KeyCode::KEY_Z, KeyCode::KEY_ESC, KeyCode::KEY_TAB, KeyCode::KEY_CAPSLOCK,
        KeyCode::KEY_LEFTSHIFT, KeyCode::KEY_RIGHTSHIFT, KeyCode::KEY_LEFTCTRL,
        KeyCode::KEY_RIGHTCTRL, KeyCode::KEY_LEFTALT, KeyCode::KEY_RIGHTALT,
        KeyCode::KEY_SPACE, KeyCode::KEY_ENTER, KeyCode::KEY_BACKSPACE,
        KeyCode::KEY_UP, KeyCode::KEY_DOWN, KeyCode::KEY_LEFT, KeyCode::KEY_RIGHT,
        KeyCode::KEY_INSERT, KeyCode::KEY_DELETE, KeyCode::KEY_HOME, KeyCode::KEY_END,
        KeyCode::KEY_PAGEUP, KeyCode::KEY_PAGEDOWN,
    ]
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let toggle_key = parse_toggle_key(&args.toggle_key)
        .ok_or_else(|| format!("Invalid toggle key: {}", args.toggle_key))?;

    let target = resolve_target(&args)?;

    let action_mode = if args.hold || args.mode.to_lowercase() == "hold" {
        ActionMode::Hold
    } else {
        ActionMode::Click
    };

    println!(
        "Wayclicker configured: Target = {:?} ({}), Mode = {:?}, Interval = {}ms, Toggle Key = {}",
        target.kind, target.name, action_mode, args.interval, args.toggle_key
    );
    println!("To start/stop, press the '{}' key.", args.toggle_key);
    println!("NOTE: This program needs permissions (sudo or uinput group) to create a virtual input device.");

    // Shared state for toggling the autoclicker and tracking shutdown
    let clicking_enabled = Arc::new(Mutex::new(false));
    let clicking_enabled_clone = Arc::clone(&clicking_enabled);

    let running = Arc::new(AtomicBool::new(true));
    let running_ctrlc = Arc::clone(&running);
    let running_loop = Arc::clone(&running);

    // Graceful shutdown on SIGINT / SIGTERM
    if let Err(e) = ctrlc::set_handler(move || {
        running_ctrlc.store(false, Ordering::SeqCst);
    }) {
        eprintln!("Warning: Could not set signal handler: {}", e);
    }

    // --- Virtual Device Creation (uinput) ---
    let mut keys = AttributeSet::<KeyCode>::new();
    for code in all_supported_keycodes() {
        keys.insert(code);
    }

    let virtual_device = VirtualDevice::builder()?
        .name("Wayclicker Virtual Device")
        .with_keys(&keys)?
        .build()
        .map_err(|e| format!("Failed to create virtual device: {}. (Did you run with sudo?)", e))?;

    let virtual_device = Arc::new(Mutex::new(virtual_device));
    let virtual_device_loop = Arc::clone(&virtual_device);

    // --- Input Listener Threads ---
    let mut candidate_devices = Vec::new();
    for (_, d) in evdev::enumerate() {
        if let Some(name) = d.name() {
            if name.contains("Wayclicker") {
                continue;
            }
        }
        if let Some(keys) = d.supported_keys() {
            if keys.contains(toggle_key) {
                candidate_devices.push(d);
            }
        }
    }

    // Fallback if no device reported explicit support for the toggle_key
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

    if candidate_devices.is_empty() {
        eprintln!("No input device found to monitor for toggle key.");
        eprintln!("Warning: Monitoring disabled. Ensure you run with appropriate permissions.");
    } else {
        for mut device in candidate_devices {
            let dev_name = device.name().unwrap_or("unnamed").to_string();
            println!("Monitoring input device: {}", dev_name);
            let toggler = Arc::clone(&clicking_enabled_clone);
            let run_flag = Arc::clone(&running);

            thread::spawn(move || {
                while run_flag.load(Ordering::Relaxed) {
                    if let Ok(events) = device.fetch_events() {
                        for event in events {
                            if let evdev::EventSummary::Key(_, key, value) = event.destructure() {
                                if value == 1 && key == toggle_key {
                                    let mut enabled = toggler.lock().unwrap();
                                    *enabled = !*enabled;
                                    println!(
                                        "Autoclicker toggled: {}",
                                        if *enabled { "ON" } else { "OFF" }
                                    );
                                }
                            }
                        }
                    } else {
                        break;
                    }
                }
            });
        }
    }

    // --- Action Loop (Main Thread) ---
    let click_interval = Duration::from_millis(args.interval.max(1));
    let press_duration = Duration::from_millis(10.min(args.interval.max(2) / 2));
    let mut is_pressed = false;

    while running_loop.load(Ordering::Relaxed) {
        let enabled = *clicking_enabled.lock().unwrap();

        match action_mode {
            ActionMode::Hold => {
                if enabled && !is_pressed {
                    let mut v_dev = virtual_device_loop.lock().unwrap();
                    let _ = v_dev.emit(&[
                        InputEvent::new(EventType::KEY.0, target.code.0, 1),
                        InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0),
                    ]);
                    is_pressed = true;
                } else if !enabled && is_pressed {
                    let mut v_dev = virtual_device_loop.lock().unwrap();
                    let _ = v_dev.emit(&[
                        InputEvent::new(EventType::KEY.0, target.code.0, 0),
                        InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0),
                    ]);
                    is_pressed = false;
                }
                thread::sleep(Duration::from_millis(20));
            }
            ActionMode::Click => {
                if enabled {
                    // Press
                    let mut v_dev = virtual_device_loop.lock().unwrap();
                    let _ = v_dev.emit(&[
                        InputEvent::new(EventType::KEY.0, target.code.0, 1),
                        InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0),
                    ]);
                    drop(v_dev);

                    thread::sleep(press_duration);

                    // Release
                    let mut v_dev = virtual_device_loop.lock().unwrap();
                    let _ = v_dev.emit(&[
                        InputEvent::new(EventType::KEY.0, target.code.0, 0),
                        InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0),
                    ]);
                    drop(v_dev);

                    // Sleep remaining interval in responsive increments
                    let sleep_time = click_interval.saturating_sub(press_duration);
                    if sleep_time > Duration::ZERO {
                        let step = Duration::from_millis(25);
                        let mut elapsed = Duration::ZERO;
                        while elapsed < sleep_time
                            && *clicking_enabled.lock().unwrap()
                            && running_loop.load(Ordering::Relaxed)
                        {
                            let to_sleep = (sleep_time - elapsed).min(step);
                            thread::sleep(to_sleep);
                            elapsed += to_sleep;
                        }
                    }
                } else {
                    thread::sleep(Duration::from_millis(30));
                }
            }
        }
    }

    // Clean exit: ensure target key is released
    if is_pressed {
        let mut v_dev = virtual_device_loop.lock().unwrap();
        let _ = v_dev.emit(&[
            InputEvent::new(EventType::KEY.0, target.code.0, 0),
            InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0),
        ]);
    }

    println!("Wayclicker stopped cleanly.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_mouse_button() {
        assert_eq!(parse_mouse_button("left"), Some(KeyCode::BTN_LEFT));
        assert_eq!(parse_mouse_button("right"), Some(KeyCode::BTN_RIGHT));
        assert_eq!(parse_mouse_button("middle"), Some(KeyCode::BTN_MIDDLE));
        assert_eq!(parse_mouse_button("side"), Some(KeyCode::BTN_SIDE));
        assert_eq!(parse_mouse_button("extra"), Some(KeyCode::BTN_EXTRA));
        assert_eq!(parse_mouse_button("btn_left"), Some(KeyCode::BTN_LEFT));
        assert_eq!(parse_mouse_button("unknown"), None);
    }

    #[test]
    fn test_parse_keyboard_key() {
        assert_eq!(parse_keyboard_key("A"), Some(KeyCode::KEY_A));
        assert_eq!(parse_keyboard_key("g"), Some(KeyCode::KEY_G));
        assert_eq!(parse_keyboard_key("f"), Some(KeyCode::KEY_F));
        assert_eq!(parse_keyboard_key("F6"), Some(KeyCode::KEY_F6));
        assert_eq!(parse_keyboard_key("space"), Some(KeyCode::KEY_SPACE));
        assert_eq!(parse_keyboard_key("1"), Some(KeyCode::KEY_1));
        assert_eq!(parse_keyboard_key("enter"), Some(KeyCode::KEY_ENTER));
    }

    #[test]
    fn test_parse_toggle_key() {
        assert_eq!(parse_toggle_key("F6"), Some(KeyCode::KEY_F6));
        assert_eq!(parse_toggle_key("BTN_LEFT"), Some(KeyCode::BTN_LEFT));
        assert_eq!(parse_toggle_key("BTN_SIDE"), Some(KeyCode::BTN_SIDE));
        assert_eq!(parse_toggle_key("X"), Some(KeyCode::KEY_X));
    }

    #[test]
    fn test_resolve_target() {
        // Default target
        let args_default = Args {
            interval: 100,
            toggle_key: "F6".to_string(),
            button: None,
            key: None,
            target: None,
            mode: "click".to_string(),
            hold: false,
        };
        let target = resolve_target(&args_default).unwrap();
        assert_eq!(target.kind, TargetKind::Mouse);
        assert_eq!(target.code, KeyCode::BTN_LEFT);

        // Keyboard target
        let args_key = Args {
            interval: 50,
            toggle_key: "F6".to_string(),
            button: None,
            key: Some("G".to_string()),
            target: None,
            mode: "click".to_string(),
            hold: false,
        };
        let target_key = resolve_target(&args_key).unwrap();
        assert_eq!(target_key.kind, TargetKind::Keyboard);
        assert_eq!(target_key.code, KeyCode::KEY_G);

        // Target string
        let args_target = Args {
            interval: 50,
            toggle_key: "F6".to_string(),
            button: None,
            key: None,
            target: Some("right".to_string()),
            mode: "hold".to_string(),
            hold: true,
        };
        let target_t = resolve_target(&args_target).unwrap();
        assert_eq!(target_t.kind, TargetKind::Mouse);
        assert_eq!(target_t.code, KeyCode::BTN_RIGHT);
    }
}
