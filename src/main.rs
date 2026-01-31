use clap::Parser;
use evdev::{
    uinput::VirtualDevice, AttributeSet, EventType, InputEvent, KeyCode,
};
use std::{
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

/// A powerful, universal autoclicker for Linux (Wayland & X11).
/// Works on GNOME, KDE, Hyprland, and others by using kernel-level uinput.
#[derive(Parser, Debug)]
#[command(author = "Dacraezy1", version, about, long_about = None)]
struct Args {
    /// Interval between clicks in milliseconds
    #[arg(short, long, default_value_t = 100)]
    interval: u64,

    /// Key to toggle the autoclicker on/off (e.g., F6, X, BTN_LEFT)
    #[arg(short, long, default_value = "F6")]
    toggle_key: String,

    /// Mouse button to click (left, right, middle)
    #[arg(short, long, default_value = "left")]
    button: String,
}

// Function to parse the toggle key string into an evdev::KeyCode
fn parse_toggle_key(key_str: &str) -> Option<KeyCode> {
    match key_str.to_uppercase().as_str() {
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
        "X" => Some(KeyCode::KEY_X),
        "Z" => Some(KeyCode::KEY_Z),
        "C" => Some(KeyCode::KEY_C),
        "V" => Some(KeyCode::KEY_V),
        "B" => Some(KeyCode::KEY_B),
        "N" => Some(KeyCode::KEY_N),
        "M" => Some(KeyCode::KEY_M),
        "A" => Some(KeyCode::KEY_A),
        "S" => Some(KeyCode::KEY_S),
        "D" => Some(KeyCode::KEY_D),
        "W" => Some(KeyCode::KEY_W),
        "Q" => Some(KeyCode::KEY_Q),
        "E" => Some(KeyCode::KEY_E),
        "R" => Some(KeyCode::KEY_R),
        "T" => Some(KeyCode::KEY_T),
        "Y" => Some(KeyCode::KEY_Y),
        "U" => Some(KeyCode::KEY_U),
        "I" => Some(KeyCode::KEY_I),
        "O" => Some(KeyCode::KEY_O),
        "P" => Some(KeyCode::KEY_P),
        "K" => Some(KeyCode::KEY_K),
        "L" => Some(KeyCode::KEY_L),
        "J" => Some(KeyCode::KEY_J),
        "H" => Some(KeyCode::KEY_H),
        "G" => Some(KeyCode::KEY_G),
        "F" => Some(KeyCode::KEY_F),
        "ESC" => Some(KeyCode::KEY_ESC),
        "TAB" => Some(KeyCode::KEY_TAB),
        "CAPSLOCK" => Some(KeyCode::KEY_CAPSLOCK),
        "LEFTSHIFT" | "SHIFT" => Some(KeyCode::KEY_LEFTSHIFT),
        "LEFTCTRL" | "CTRL" => Some(KeyCode::KEY_LEFTCTRL),
        "LEFTALT" | "ALT" => Some(KeyCode::KEY_LEFTALT),
        "SPACE" => Some(KeyCode::KEY_SPACE),
        "ENTER" => Some(KeyCode::KEY_ENTER),
        "BACKSPACE" => Some(KeyCode::KEY_BACKSPACE),
        "BTN_LEFT" => Some(KeyCode::BTN_LEFT),
        "BTN_RIGHT" => Some(KeyCode::BTN_RIGHT),
        "BTN_MIDDLE" => Some(KeyCode::BTN_MIDDLE),
        "BTN_SIDE" => Some(KeyCode::BTN_SIDE),
        "BTN_EXTRA" => Some(KeyCode::BTN_EXTRA),
        _ => None,
    }
}

// Function to parse the mouse button string into a KeyCode for the virtual mouse
fn parse_mouse_button(button_str: &str) -> Option<KeyCode> {
    match button_str.to_lowercase().as_str() {
        "left" => Some(KeyCode::BTN_LEFT),
        "right" => Some(KeyCode::BTN_RIGHT),
        "middle" => Some(KeyCode::BTN_MIDDLE),
        _ => None,
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let toggle_key = parse_toggle_key(&args.toggle_key)
        .ok_or_else(|| format!("Invalid toggle key: {}", args.toggle_key))?;

    let mouse_button_code = parse_mouse_button(&args.button)
        .ok_or_else(|| format!("Invalid mouse button: {}. Use 'left', 'right', or 'middle'.", args.button))?;

    println!(
        "Wayclicker configured: Interval = {}ms, Toggle Key = {}, Mouse Button = {}",
        args.interval, args.toggle_key, args.button
    );
    println!("To start/stop clicking, press the '{}' key.", args.toggle_key);
    println!("NOTE: This program needs to be run with root permissions (sudo) to create a virtual input device.");

    // Shared state for toggling the autoclicker
    let clicking_enabled = Arc::new(Mutex::new(false));
    let clicking_enabled_clone = Arc::clone(&clicking_enabled);

    // --- Virtual Device Creation (uinput) ---
    // We create a virtual mouse that can emit key events (buttons) and synchronization events.
    let mut keys = AttributeSet::<KeyCode>::new();
    keys.insert(KeyCode::BTN_LEFT);
    keys.insert(KeyCode::BTN_RIGHT);
    keys.insert(KeyCode::BTN_MIDDLE);

    let virtual_device = VirtualDevice::builder()?
        .name("Wayclicker Virtual Mouse")
        .with_keys(&keys)?
        .build()
        .map_err(|e| format!("Failed to create virtual device: {}. (Did you run with sudo?)", e))?;

    let virtual_device = Arc::new(Mutex::new(virtual_device));
    let virtual_device_clone = Arc::clone(&virtual_device);

    // --- Keyboard Listener Thread ---
    thread::spawn(move || {
        let mut device = None;
        // Try to find a keyboard device
        for (_, d) in evdev::enumerate() {
            if d.supported_events().contains(EventType::KEY) {
                // Heuristic: try to find a keyboard.
                if d.name().unwrap_or("").to_lowercase().contains("keyboard")
                    || d.name().unwrap_or("").to_lowercase().contains("kbd")
                {
                    // Basic filter to avoid grabbing our own virtual device or other non-keyboards
                    if !d.name().unwrap_or("").contains("Wayclicker") {
                         println!("Found input device: {}", d.name().unwrap_or("unnamed"));
                         device = Some(d);
                         break;
                    }
                }
            }
        }

        if device.is_none() {
            eprintln!("No physical keyboard device found via heuristics.");
            eprintln!("Warning: Auto-detection failed. Monitoring disabled.");
            return;
        }

        let mut device = device.unwrap();
        
        // Grab the device to prevent events from going to other applications?
        // CAUTION: Grabbing prevents other apps from seeing the key.
        // We removed the grab so you can still use your keyboard while this runs.
        /*
        if let Err(e) = device.grab() {
            eprintln!("Failed to grab input device: {}. Ensure you run with sufficient permissions (e.g., `sudo`).", e);
            return;
        }
        println!("Grabbed input device: {}", device.name().unwrap_or("unnamed"));
        */
        println!("Monitoring input device: {}", device.name().unwrap_or("unnamed"));

        loop {
            if let Ok(events) = device.fetch_events() {
                 for event in events {
                    if let evdev::EventSummary::Key(_, key, value) = event.destructure() {
                        if value == 1 && key == toggle_key {
                            let mut enabled = clicking_enabled_clone.lock().unwrap();
                            *enabled = !*enabled; // Toggle the state
                            println!("Autoclicker toggled: {}", if *enabled { "ON" } else { "OFF" });
                        }
                    }
                }
            }
        }
    });

    // --- Clicking Loop (Main Thread) ---
    let click_interval = Duration::from_millis(args.interval);

    loop {
        let enabled = *clicking_enabled.lock().unwrap();

        if enabled {
            // We must lock the device to write to it
            let mut v_dev = virtual_device_clone.lock().unwrap();

            // Press
            let _ = v_dev.emit(&[InputEvent::new(EventType::KEY.0, mouse_button_code.0, 1)]);
            let _ = v_dev.emit(&[InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0)]);
            
            // Release lock during sleep? No, actually we can release it, but we need it again very soon.
            // Better to drop the lock before sleeping.
            drop(v_dev);

            thread::sleep(Duration::from_millis(10)); // Small delay for button down state

            let mut v_dev = virtual_device_clone.lock().unwrap();
            // Release
            let _ = v_dev.emit(&[InputEvent::new(EventType::KEY.0, mouse_button_code.0, 0)]);
            let _ = v_dev.emit(&[InputEvent::new(EventType::SYNCHRONIZATION.0, 0, 0)]);
            drop(v_dev);

            thread::sleep(click_interval.checked_sub(Duration::from_millis(10)).unwrap_or_default());
        } else {
            thread::sleep(Duration::from_millis(50));
        }
    }
}
