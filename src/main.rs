use clap::Parser;
use std::{
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};
use wayland_client::{
    protocol::{wl_pointer, wl_registry},
    Connection, Dispatch, QueueHandle,
    Proxy, // Added Proxy trait import for interface() method
};
use wayland_protocols_wlr::unstable::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1,
    zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};
use evdev::{Device, InputEventKind, KeyCode};

/// A powerful and fast autoclicker for Wayland.
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

// AppState will hold our Wayland objects and the virtual pointer manager
struct AppState {
    virtual_pointer_manager: Option<ZwlrVirtualPointerManagerV1>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for AppState {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qhandle: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            // Bind to the virtual pointer manager if available
            if interface == ZwlrVirtualPointerManagerV1::interface().name {
                println!("Found virtual pointer manager (version {})", version);
                state.virtual_pointer_manager = Some(
                    registry.bind::<ZwlrVirtualPointerManagerV1, _, _>(name, version, qhandle, ()),
                );
            }
        }
    }
}

// Dispatch for ZwlrVirtualPointerManagerV1
impl Dispatch<ZwlrVirtualPointerManagerV1, ()> for AppState {
    fn event(
        _state: &mut Self,
        _proxy: &ZwlrVirtualPointerManagerV1,
        _event: <ZwlrVirtualPointerManagerV1 as wayland_client::Proxy>::Event,
        _data: &(),
        _conn: &Connection,
        _qhandle: &QueueHandle<Self>,
    ) {
    }
}

// Dispatch for ZwlrVirtualPointerV1
impl Dispatch<ZwlrVirtualPointerV1, ()> for AppState {
    fn event(
        _state: &mut Self,
        _proxy: &ZwlrVirtualPointerV1,
        _event: <ZwlrVirtualPointerV1 as wayland_client::Proxy>::Event,
        _data: &(),
        _conn: &Connection,
        _qhandle: &QueueHandle<Self>,
    ) {
    }
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
        "BTN_LEFT" => Some(KeyCode::BTN_LEFT),
        "BTN_RIGHT" => Some(KeyCode::BTN_RIGHT),
        "BTN_MIDDLE" => Some(KeyCode::BTN_MIDDLE),
        _ => None,
    }
}

// Function to parse the mouse button string into a linux button code
fn parse_mouse_button(button_str: &str) -> Option<u32> {
    match button_str.to_lowercase().as_str() {
        "left" => Some(0x110),   // BTN_LEFT
        "right" => Some(0x111),  // BTN_RIGHT
        "middle" => Some(0x112), // BTN_MIDDLE
        _ => None,
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    let toggle_key = parse_toggle_key(&args.toggle_key)
        .ok_or_else(|| format!("Invalid toggle key: {}", args.toggle_key))?;

    let mouse_button = parse_mouse_button(&args.button)
        .ok_or_else(|| format!("Invalid mouse button: {}. Use 'left', 'right', or 'middle'.", args.button))?;

    println!(
        "Autoclicker configured: Interval = {}ms, Toggle Key = {}, Mouse Button = {}",
        args.interval, args.toggle_key, args.button
    );
    println!("To start/stop clicking, press the '{}' key.", args.toggle_key);
    println!("NOTE: This program needs to be run with permissions to read input devices (e.g., `sudo`).");

    // Shared state for toggling the autoclicker
    let clicking_enabled = Arc::new(Mutex::new(false));
    let clicking_enabled_clone = Arc::clone(&clicking_enabled);

    // --- Keyboard Listener Thread ---
    thread::spawn(move || {
        let mut device = None;
        // Try to find a keyboard device
        for (_, d) in evdev::enumerate() {
            if d.supported_events().contains(evdev::EventType::KEY) {
                // Heuristic: try to find a keyboard.
                if d.name().unwrap_or("").to_lowercase().contains("keyboard") || d.name().unwrap_or("").to_lowercase().contains("kbd") {
                    println!("Found input device: {}", d.name().unwrap_or("unnamed"));
                    device = Some(d);
                    break;
                }
            }
        }

        if device.is_none() {
            eprintln!("No keyboard device found via heuristics.");
            // Fallback: Just grab the first device with keys? No, unsafe.
            // Better to warn.
            eprintln!("Warning: Auto-detection failed. Monitoring disabled.");
            return;
        }

        let mut device = device.unwrap();
        
        // Grab the device to prevent events from going to other applications
        // This requires root privileges.
        if let Err(e) = device.grab() {
            eprintln!("Failed to grab input device: {}. Ensure you run with sufficient permissions (e.g., `sudo`).", e);
            return;
        }
        println!("Grabbed input device: {}", device.name().unwrap_or("unnamed"));

        loop {
            // fetch_events blocks, so we don't need sleep
            if let Ok(events) = device.fetch_events() {
                 for event in events {
                    if let InputEventKind::Key(key) = event.kind() {
                        if event.value() == 1 && key == toggle_key {
                            let mut enabled = clicking_enabled_clone.lock().unwrap();
                            *enabled = !*enabled; // Toggle the state
                            println!("Autoclicker toggled: {}", if *enabled { "ON" } else { "OFF" });
                        }
                    }
                }
            }
        }
    });

    // --- Wayland Connection and Clicking Logic (Main Thread) ---
    // Connect to the Wayland server
    let conn = match Connection::connect_to_env() {
        Ok(c) => c,
        Err(e) => {
             eprintln!("Failed to connect to Wayland display: {}", e);
             return Err(Box::new(e));
        }
    };

    let mut event_queue = conn.new_event_queue();
    let qhandle = event_queue.handle();

    let display = conn.display();
    display.get_registry(&qhandle, ());

    let mut app_state = AppState {
        virtual_pointer_manager: None,
    };

    // Process events to get the virtual pointer manager
    event_queue.roundtrip(&mut app_state)?;

    let virtual_pointer_manager = app_state
        .virtual_pointer_manager
        .expect("Compositor does not support zwlr_virtual_pointer_manager_v1. Cannot create virtual pointer. Are you running a wlroots-based compositor (Sway, Hyprland)?");

    // Create the virtual pointer
    // Use None for seat to let compositor decide (or we might need to bind a seat first if required, but usually optional)
    let virtual_pointer = virtual_pointer_manager.create_virtual_pointer(None, &qhandle, ());

    println!("Virtual pointer created. Autoclicker ready.");

    let click_interval = Duration::from_millis(args.interval);

    loop {
        let enabled = *clicking_enabled.lock().unwrap();

        if enabled {
            // Send button press
            // Use 0 for time
            virtual_pointer.button(0, 0, mouse_button, wl_pointer::ButtonState::Pressed);
            virtual_pointer.frame(); // Commit the event
            conn.flush()?;

            thread::sleep(Duration::from_millis(10)); // Small delay for button down state

            // Send button release
            virtual_pointer.button(0, 0, mouse_button, wl_pointer::ButtonState::Released);
            virtual_pointer.frame(); // Commit the event
            conn.flush()?;

            thread::sleep(click_interval.checked_sub(Duration::from_millis(10)).unwrap_or_default());
        } else {
            // If not clicking, sleep for a short duration to avoid busy-waiting
            thread::sleep(Duration::from_millis(50));
        }
    }
}