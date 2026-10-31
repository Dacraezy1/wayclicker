//! Key-name parsing and key-combination ("chord") handling.
//!
//! A *chord* is one or more keys joined with `+`, e.g. `F13`, `ctrl+alt+c`,
//! `shift+BTN_SIDE`. A chord is "pressed" when every one of its slots is held.
//! A slot can accept several physical keys: `ctrl` is satisfied by either the
//! left or the right Ctrl key.

use evdev::KeyCode;
use std::{collections::HashSet, str::FromStr};

/// Keys that must never be registered on the virtual device: systemd-logind
/// grabs input devices that advertise power keys, which would break Wayclicker.
const FORBIDDEN: &[KeyCode] = &[
    KeyCode::KEY_POWER,
    KeyCode::KEY_SLEEP,
    KeyCode::KEY_WAKEUP,
    KeyCode::KEY_SUSPEND,
];

/// One position in a chord. Satisfied when ANY of `alts` is held.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeySlot {
    pub alts: Vec<KeyCode>,
}

/// A parsed key combination.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Chord {
    pub slots: Vec<KeySlot>,
}

impl Chord {
    /// Parse `"ctrl+alt+c"`, `"F13"`, `"BTN_SIDE"`, ...
    ///
    /// `prefer_mouse` decides how the ambiguous names `left` / `right` are read:
    /// as mouse buttons (`true`, used for triggers and `--button`) or as arrow
    /// keys (`false`, used for `--key`).
    pub fn parse(input: &str, prefer_mouse: bool) -> Result<Chord, String> {
        let input = input.trim();
        if input.is_empty() {
            return Err("empty key".to_string());
        }
        let mut slots: Vec<KeySlot> = Vec::new();
        for part in input.split('+') {
            let part = part.trim();
            if part.is_empty() {
                return Err(format!(
                    "invalid key combination '{input}' (empty part; write a literal plus as 'kpplus')"
                ));
            }
            let alts = parse_single(part, prefer_mouse).ok_or_else(|| {
                format!("unknown key '{part}' (use names like F13, ctrl, alt, c, space, BTN_SIDE or KEY_xxx)")
            })?;
            let slot = KeySlot { alts };
            if !slots.contains(&slot) {
                slots.push(slot);
            }
        }
        Ok(Chord { slots })
    }

    /// True when every slot has at least one of its keys currently held.
    pub fn is_pressed(&self, held: &HashSet<KeyCode>) -> bool {
        self.slots
            .iter()
            .all(|s| s.alts.iter().any(|k| held.contains(k)))
    }

    /// Every physical key that can take part in this chord.
    pub fn all_codes(&self) -> Vec<KeyCode> {
        self.slots.iter().flat_map(|s| s.alts.iter().copied()).collect()
    }

    /// One concrete key per slot (the first alternative), in order.
    /// This is what gets emitted when the chord is used as the *target*.
    pub fn primary_codes(&self) -> Vec<KeyCode> {
        self.slots.iter().map(|s| s.alts[0]).collect()
    }

    /// True if the chord is exactly one mouse button.
    pub fn is_single_mouse_button(&self) -> bool {
        self.slots.len() == 1 && self.slots[0].alts.len() == 1 && is_mouse_button(self.slots[0].alts[0])
    }
}

pub fn is_mouse_button(code: KeyCode) -> bool {
    matches!(
        code,
        KeyCode::BTN_LEFT
            | KeyCode::BTN_RIGHT
            | KeyCode::BTN_MIDDLE
            | KeyCode::BTN_SIDE
            | KeyCode::BTN_EXTRA
            | KeyCode::BTN_FORWARD
            | KeyCode::BTN_BACK
    )
}

pub fn parse_mouse_button(name: &str) -> Option<KeyCode> {
    match name.trim().to_lowercase().as_str() {
        "left" | "btn_left" | "lmb" | "mouse1" => Some(KeyCode::BTN_LEFT),
        "right" | "btn_right" | "rmb" | "mouse2" => Some(KeyCode::BTN_RIGHT),
        "middle" | "btn_middle" | "mmb" | "mouse3" => Some(KeyCode::BTN_MIDDLE),
        "side" | "back" | "btn_side" | "mouse4" => Some(KeyCode::BTN_SIDE),
        "extra" | "forward" | "btn_extra" | "mouse5" => Some(KeyCode::BTN_EXTRA),
        "btn_forward" => Some(KeyCode::BTN_FORWARD),
        "btn_back" => Some(KeyCode::BTN_BACK),
        _ => None,
    }
}

/// Parse a single (non-combo) keyboard key name.
pub fn parse_keyboard_key(name: &str) -> Option<Vec<KeyCode>> {
    let raw = name.trim();
    if raw.is_empty() {
        return None;
    }
    let lower = raw.to_lowercase();

    // Modifiers: generic names accept either side.
    let modifier = match lower.as_str() {
        "ctrl" | "control" => Some(vec![KeyCode::KEY_LEFTCTRL, KeyCode::KEY_RIGHTCTRL]),
        "shift" => Some(vec![KeyCode::KEY_LEFTSHIFT, KeyCode::KEY_RIGHTSHIFT]),
        "alt" => Some(vec![KeyCode::KEY_LEFTALT, KeyCode::KEY_RIGHTALT]),
        "super" | "meta" | "win" | "windows" | "cmd" | "logo" => {
            Some(vec![KeyCode::KEY_LEFTMETA, KeyCode::KEY_RIGHTMETA])
        }
        "leftctrl" | "lctrl" | "left_ctrl" => Some(vec![KeyCode::KEY_LEFTCTRL]),
        "rightctrl" | "rctrl" | "right_ctrl" => Some(vec![KeyCode::KEY_RIGHTCTRL]),
        "leftshift" | "lshift" | "left_shift" => Some(vec![KeyCode::KEY_LEFTSHIFT]),
        "rightshift" | "rshift" | "right_shift" => Some(vec![KeyCode::KEY_RIGHTSHIFT]),
        "leftalt" | "lalt" | "left_alt" => Some(vec![KeyCode::KEY_LEFTALT]),
        "rightalt" | "ralt" | "right_alt" | "altgr" => Some(vec![KeyCode::KEY_RIGHTALT]),
        "leftmeta" | "lmeta" | "lsuper" | "left_meta" => Some(vec![KeyCode::KEY_LEFTMETA]),
        "rightmeta" | "rmeta" | "rsuper" | "right_meta" => Some(vec![KeyCode::KEY_RIGHTMETA]),
        _ => None,
    };
    if modifier.is_some() {
        return modifier;
    }

    let single = |c: KeyCode| Some(vec![c]);

    // Single characters.
    if lower.chars().count() == 1 {
        let c = lower.chars().next().unwrap();
        let code = match c {
            'a' => KeyCode::KEY_A, 'b' => KeyCode::KEY_B, 'c' => KeyCode::KEY_C,
            'd' => KeyCode::KEY_D, 'e' => KeyCode::KEY_E, 'f' => KeyCode::KEY_F,
            'g' => KeyCode::KEY_G, 'h' => KeyCode::KEY_H, 'i' => KeyCode::KEY_I,
            'j' => KeyCode::KEY_J, 'k' => KeyCode::KEY_K, 'l' => KeyCode::KEY_L,
            'm' => KeyCode::KEY_M, 'n' => KeyCode::KEY_N, 'o' => KeyCode::KEY_O,
            'p' => KeyCode::KEY_P, 'q' => KeyCode::KEY_Q, 'r' => KeyCode::KEY_R,
            's' => KeyCode::KEY_S, 't' => KeyCode::KEY_T, 'u' => KeyCode::KEY_U,
            'v' => KeyCode::KEY_V, 'w' => KeyCode::KEY_W, 'x' => KeyCode::KEY_X,
            'y' => KeyCode::KEY_Y, 'z' => KeyCode::KEY_Z,
            '0' => KeyCode::KEY_0, '1' => KeyCode::KEY_1, '2' => KeyCode::KEY_2,
            '3' => KeyCode::KEY_3, '4' => KeyCode::KEY_4, '5' => KeyCode::KEY_5,
            '6' => KeyCode::KEY_6, '7' => KeyCode::KEY_7, '8' => KeyCode::KEY_8,
            '9' => KeyCode::KEY_9,
            '-' => KeyCode::KEY_MINUS,
            '=' => KeyCode::KEY_EQUAL,
            '[' => KeyCode::KEY_LEFTBRACE,
            ']' => KeyCode::KEY_RIGHTBRACE,
            '\\' => KeyCode::KEY_BACKSLASH,
            ';' => KeyCode::KEY_SEMICOLON,
            '\'' => KeyCode::KEY_APOSTROPHE,
            '`' => KeyCode::KEY_GRAVE,
            ',' => KeyCode::KEY_COMMA,
            '.' => KeyCode::KEY_DOT,
            '/' => KeyCode::KEY_SLASH,
            _ => return None,
        };
        return single(code);
    }

    // Function keys F1 .. F24.
    if let Some(num) = lower.strip_prefix('f') {
        if let Ok(n) = num.parse::<u8>() {
            let code = match n {
                1 => KeyCode::KEY_F1, 2 => KeyCode::KEY_F2, 3 => KeyCode::KEY_F3,
                4 => KeyCode::KEY_F4, 5 => KeyCode::KEY_F5, 6 => KeyCode::KEY_F6,
                7 => KeyCode::KEY_F7, 8 => KeyCode::KEY_F8, 9 => KeyCode::KEY_F9,
                10 => KeyCode::KEY_F10, 11 => KeyCode::KEY_F11, 12 => KeyCode::KEY_F12,
                13 => KeyCode::KEY_F13, 14 => KeyCode::KEY_F14, 15 => KeyCode::KEY_F15,
                16 => KeyCode::KEY_F16, 17 => KeyCode::KEY_F17, 18 => KeyCode::KEY_F18,
                19 => KeyCode::KEY_F19, 20 => KeyCode::KEY_F20, 21 => KeyCode::KEY_F21,
                22 => KeyCode::KEY_F22, 23 => KeyCode::KEY_F23, 24 => KeyCode::KEY_F24,
                _ => return None,
            };
            return single(code);
        }
    }

    // Named keys.
    let named = match lower.as_str() {
        "esc" | "escape" => Some(KeyCode::KEY_ESC),
        "tab" => Some(KeyCode::KEY_TAB),
        "capslock" | "caps" | "caps_lock" => Some(KeyCode::KEY_CAPSLOCK),
        "space" | "spacebar" => Some(KeyCode::KEY_SPACE),
        "enter" | "return" => Some(KeyCode::KEY_ENTER),
        "backspace" => Some(KeyCode::KEY_BACKSPACE),
        "up" | "arrowup" => Some(KeyCode::KEY_UP),
        "down" | "arrowdown" => Some(KeyCode::KEY_DOWN),
        "left" | "arrowleft" => Some(KeyCode::KEY_LEFT),
        "right" | "arrowright" => Some(KeyCode::KEY_RIGHT),
        "insert" | "ins" => Some(KeyCode::KEY_INSERT),
        "delete" | "del" => Some(KeyCode::KEY_DELETE),
        "home" => Some(KeyCode::KEY_HOME),
        "end" => Some(KeyCode::KEY_END),
        "pageup" | "pgup" => Some(KeyCode::KEY_PAGEUP),
        "pagedown" | "pgdn" => Some(KeyCode::KEY_PAGEDOWN),
        "printscreen" | "print" | "prtsc" | "sysrq" => Some(KeyCode::KEY_SYSRQ),
        "scrolllock" | "scroll_lock" => Some(KeyCode::KEY_SCROLLLOCK),
        "pause" | "break" => Some(KeyCode::KEY_PAUSE),
        "numlock" | "num_lock" => Some(KeyCode::KEY_NUMLOCK),
        "menu" | "compose" => Some(KeyCode::KEY_COMPOSE),
        "minus" => Some(KeyCode::KEY_MINUS),
        "equal" | "equals" => Some(KeyCode::KEY_EQUAL),
        "leftbrace" => Some(KeyCode::KEY_LEFTBRACE),
        "rightbrace" => Some(KeyCode::KEY_RIGHTBRACE),
        "backslash" => Some(KeyCode::KEY_BACKSLASH),
        "semicolon" => Some(KeyCode::KEY_SEMICOLON),
        "apostrophe" => Some(KeyCode::KEY_APOSTROPHE),
        "grave" | "backtick" => Some(KeyCode::KEY_GRAVE),
        "comma" => Some(KeyCode::KEY_COMMA),
        "dot" | "period" => Some(KeyCode::KEY_DOT),
        "slash" => Some(KeyCode::KEY_SLASH),
        "kpplus" | "plus" => Some(KeyCode::KEY_KPPLUS),
        "kpminus" => Some(KeyCode::KEY_KPMINUS),
        "kpasterisk" => Some(KeyCode::KEY_KPASTERISK),
        "kpslash" => Some(KeyCode::KEY_KPSLASH),
        "kpenter" => Some(KeyCode::KEY_KPENTER),
        "kpdot" => Some(KeyCode::KEY_KPDOT),
        "kp0" => Some(KeyCode::KEY_KP0),
        "kp1" => Some(KeyCode::KEY_KP1),
        "kp2" => Some(KeyCode::KEY_KP2),
        "kp3" => Some(KeyCode::KEY_KP3),
        "kp4" => Some(KeyCode::KEY_KP4),
        "kp5" => Some(KeyCode::KEY_KP5),
        "kp6" => Some(KeyCode::KEY_KP6),
        "kp7" => Some(KeyCode::KEY_KP7),
        "kp8" => Some(KeyCode::KEY_KP8),
        "kp9" => Some(KeyCode::KEY_KP9),
        _ => None,
    };
    if let Some(c) = named {
        return single(c);
    }

    // Fallback: any raw evdev name (KEY_xxx / BTN_xxx), with or without prefix.
    let upper = raw.to_uppercase();
    let candidates = [upper.clone(), format!("KEY_{upper}")];
    for cand in candidates {
        if let Ok(code) = KeyCode::from_str(&cand) {
            if FORBIDDEN.contains(&code) {
                return None;
            }
            return single(code);
        }
    }
    None
}

fn parse_single(name: &str, prefer_mouse: bool) -> Option<Vec<KeyCode>> {
    if prefer_mouse {
        if let Some(c) = parse_mouse_button(name) {
            return Some(vec![c]);
        }
        parse_keyboard_key(name)
    } else {
        if let Some(k) = parse_keyboard_key(name) {
            return Some(k);
        }
        parse_mouse_button(name).map(|c| vec![c])
    }
}

/// Every key the virtual device must advertise so that it can emit any key
/// the user may configure as a target.
pub fn base_virtual_keys() -> Vec<KeyCode> {
    let mut v = vec![
        KeyCode::BTN_LEFT, KeyCode::BTN_RIGHT, KeyCode::BTN_MIDDLE,
        KeyCode::BTN_SIDE, KeyCode::BTN_EXTRA, KeyCode::BTN_FORWARD, KeyCode::BTN_BACK,
    ];
    // KEY_ESC (1) .. KEY_KPDOT (83) covers the main block, digits, punctuation and keypad.
    for code in 1u16..=83 {
        v.push(KeyCode::new(code));
    }
    // KEY_F11, KEY_F12, KEY_KPENTER..KEY_KPSLASH, SYSRQ, RIGHTALT, navigation cluster, pause, meta, compose.
    for code in [
        87u16, 88, 96, 97, 98, 99, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
        119, 125, 126, 127,
    ] {
        v.push(KeyCode::new(code));
    }
    // KEY_F13 (183) .. KEY_F24 (194)
    for code in 183u16..=194 {
        v.push(KeyCode::new(code));
    }
    v.retain(|c| !FORBIDDEN.contains(c));
    v.sort_by_key(|c| c.0);
    v.dedup();
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn held(keys: &[KeyCode]) -> HashSet<KeyCode> {
        keys.iter().copied().collect()
    }

    #[test]
    fn parses_f13_to_f24() {
        assert_eq!(Chord::parse("F13", true).unwrap().primary_codes(), vec![KeyCode::KEY_F13]);
        assert_eq!(Chord::parse("f21", true).unwrap().primary_codes(), vec![KeyCode::KEY_F21]);
        assert_eq!(Chord::parse("F24", true).unwrap().primary_codes(), vec![KeyCode::KEY_F24]);
        assert!(Chord::parse("F25", true).is_err());
        assert!(Chord::parse("F0", true).is_err());
    }

    #[test]
    fn parses_ctrl_alt_c_combo() {
        let c = Chord::parse("ctrl+alt+c", true).unwrap();
        assert_eq!(c.slots.len(), 3);
        assert!(!c.is_pressed(&held(&[KeyCode::KEY_LEFTCTRL, KeyCode::KEY_C])));
        assert!(c.is_pressed(&held(&[KeyCode::KEY_LEFTCTRL, KeyCode::KEY_LEFTALT, KeyCode::KEY_C])));
        // Right-hand modifiers satisfy the generic names as well.
        assert!(c.is_pressed(&held(&[KeyCode::KEY_RIGHTCTRL, KeyCode::KEY_RIGHTALT, KeyCode::KEY_C])));
        // Extra held keys do not prevent a match.
        assert!(c.is_pressed(&held(&[
            KeyCode::KEY_LEFTCTRL, KeyCode::KEY_LEFTALT, KeyCode::KEY_C, KeyCode::KEY_W
        ])));
    }

    #[test]
    fn combo_is_whitespace_and_case_tolerant() {
        let a = Chord::parse("Ctrl + ALT + C", true).unwrap();
        let b = Chord::parse("ctrl+alt+c", true).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn side_specific_modifiers() {
        let c = Chord::parse("leftctrl+x", true).unwrap();
        assert!(c.is_pressed(&held(&[KeyCode::KEY_LEFTCTRL, KeyCode::KEY_X])));
        assert!(!c.is_pressed(&held(&[KeyCode::KEY_RIGHTCTRL, KeyCode::KEY_X])));
    }

    #[test]
    fn mouse_buttons_in_combos() {
        let c = Chord::parse("shift+BTN_SIDE", true).unwrap();
        assert!(c.is_pressed(&held(&[KeyCode::KEY_LEFTSHIFT, KeyCode::BTN_SIDE])));
        assert!(Chord::parse("left", true).unwrap().is_single_mouse_button());
        assert!(!Chord::parse("ctrl+left", true).unwrap().is_single_mouse_button());
    }

    #[test]
    fn left_right_ambiguity() {
        assert_eq!(Chord::parse("left", true).unwrap().primary_codes(), vec![KeyCode::BTN_LEFT]);
        assert_eq!(Chord::parse("left", false).unwrap().primary_codes(), vec![KeyCode::KEY_LEFT]);
        assert_eq!(Chord::parse("arrowright", true).unwrap().primary_codes(), vec![KeyCode::KEY_RIGHT]);
    }

    #[test]
    fn raw_evdev_names() {
        assert_eq!(Chord::parse("KEY_F20", true).unwrap().primary_codes(), vec![KeyCode::KEY_F20]);
        assert_eq!(Chord::parse("KEY_KPENTER", true).unwrap().primary_codes(), vec![KeyCode::KEY_KPENTER]);
        assert_eq!(Chord::parse("kpenter", true).unwrap().primary_codes(), vec![KeyCode::KEY_KPENTER]);
    }

    #[test]
    fn rejects_bad_input() {
        assert!(Chord::parse("", true).is_err());
        assert!(Chord::parse("ctrl+", true).is_err());
        assert!(Chord::parse("+c", true).is_err());
        assert!(Chord::parse("notakey", true).is_err());
        assert!(Chord::parse("ctrl+notakey", true).is_err());
    }

    #[test]
    fn power_keys_are_refused() {
        assert!(Chord::parse("KEY_POWER", true).is_err());
        assert!(Chord::parse("sleep", true).is_err());
    }

    #[test]
    fn duplicate_slots_collapse() {
        let c = Chord::parse("ctrl+ctrl+c", true).unwrap();
        assert_eq!(c.slots.len(), 2);
    }

    #[test]
    fn virtual_keys_cover_common_targets_and_exclude_power() {
        let keys = base_virtual_keys();
        for k in [KeyCode::KEY_A, KeyCode::KEY_F13, KeyCode::KEY_F24, KeyCode::KEY_LEFTMETA,
                  KeyCode::KEY_KPENTER, KeyCode::KEY_SPACE, KeyCode::BTN_LEFT, KeyCode::KEY_PAGEDOWN] {
            assert!(keys.contains(&k), "missing {k:?}");
        }
        assert!(!keys.contains(&KeyCode::KEY_POWER));
    }
}
