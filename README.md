# Wayclicker

A powerful, universal autoclicker and key automator for Linux.

## Preview
<p align="center">
    <img width="45%" src="https://github.com/user-attachments/assets/56264b44-1bda-4210-826c-318647ae5fe9" />
&nbsp; &nbsp; &nbsp; &nbsp;
    <img width="45%" src="https://github.com/user-attachments/assets/2144643c-e7ae-449b-8088-419d82c45569" />
</p>

**Works on ALL desktop environments:**
*   GNOME (Wayland & X11)
*   KDE Plasma (Wayland & X11)
*   Hyprland
*   Sway
*   XFCE, MATE, Cinnamon, LXQt, etc.

Created by: **Dacraezy1**  
GUI Created by: **YanamiRei**

---

## ✨ Features

- **Universal Wayland & X11 Compatibility:** Uses Linux kernel `uinput` virtual input devices directly—no compositor plugins or screen protocol limitations.
- **Arbitrary Delay / Interval Support:** Set intervals from 1ms up to 60,000ms+ in the GUI (via slider, text input, or quick presets).
- **Click Mode & Hold Mode:**
  - **Click (Repeat):** Repeatedly pulses clicks or keystrokes at your designated interval.
  - **Hold (Continuous):** Presses down the mouse button or keyboard key and holds it continuously until toggled off.
- **Automate Mouse and Keyboard:**
  - Emulate mouse buttons: `Left`, `Middle`, `Right`, `Side` (Back), `Extra` (Forward).
  - Emulate keyboard keys: Letters (`A`-`Z`), Numbers (`0`-`9`), Function keys (`F1`-`F12`), Navigation, `Space`, `Enter`, `Tab`, `Esc`, etc.
- **Persistent Configuration:** Automatically saves and restores your GUI settings across boots (`~/.config/wayclicker/config.json`).
- **Fully Custom Hotkeys & Key Combos:** Bind the trigger to *any* key (`F1`-`F24`, `A`-`Z`, keypad, navigation, raw evdev names like `KEY_F20`), any mouse button, or a **combination** such as `ctrl+alt+c` or `shift+BTN_SIDE`. Type it, or press **Record** in the GUI and just press the keys. Combos can also be used as the *target* (e.g. send `ctrl+c`).
- **System Installation & Packaging:** Install binaries to system paths (`/usr/local/bin`), desktop integration with app launcher icon, and packages for Arch, Debian/Ubuntu, and Fedora.

---

## 🚀 How it Works
Unlike traditional Wayland autoclickers that depend on compositor-specific protocols (like `wlr-virtual-pointer` which doesn't work on GNOME), **Wayclicker** uses the Linux kernel's `uinput` subsystem to create a virtual input device. This allows it to work universally across every Linux system, regardless of the display server (Wayland or X11) or desktop compositor.

---

## 🛠️ Installation

### Option 1: System Install via Script (Recommended)
You can install the binaries to system paths (`/usr/local/bin`) with desktop integration and application menu shortcuts:

```bash
# 1. Download and extract the latest release tarball
tar -xzvf wayclicker-linux-x64.tar.gz
cd wayclicker-release

# 2. Run the installer with root privileges
sudo ./install.sh
```

This installs:
- CLI binary to `/usr/local/bin/wayclicker` (protected from non-root modification)
- GUI bundle to `/usr/local/lib/wayclicker/` and launcher to `/usr/local/bin/wayclicker-gui`
- Desktop entry and application icon to your system app launcher
- Optional `/etc/udev/rules.d/99-wayclicker.rules` for uinput device permissions

To uninstall:
```bash
sudo ./uninstall.sh
```

### Option 2: Package Managers

#### Debian / Ubuntu / Linux Mint
Download the `.deb` package from the [Releases](https://github.com/Dacraezy1/wayclicker/releases) page:
```bash
sudo apt install ./wayclicker_amd64.deb
```
Or build from source:
```bash
./packaging/debian/build_deb.sh
```

#### Arch Linux / Manjaro
Use the included `PKGBUILD`:
```bash
cd packaging/arch
makepkg -si
```

#### Fedora / RHEL
Use the included RPM spec file:
```bash
rpmbuild -ba packaging/rpm/wayclicker.spec
```

### Option 3: Portable Binary
1. Extract `wayclicker-linux-x64.tar.gz`.
2. Run GUI directly: `./wayclicker_gui` or CLI directly: `sudo ./wayclicker`.

### Option 4: Build from Source
**Prerequisites:** Rust toolchain (`rustup default stable`), Flutter SDK

```bash
chmod +x build_release.sh
./build_release.sh
```
Find the output in the `output/` directory.

---

## 🎮 Usage

Because `Wayclicker` operates at the kernel level (`/dev/uinput` and `/dev/input/*`), permissions are required (either via `sudo` / `pkexec`, or via the included uinput udev rule).

### GUI Mode

Launch `wayclicker-gui` (or `./wayclicker_gui`):

1. **Select Action Type:** Choose **Click Repeatedly** or **Hold Down** (keeps the target button/key pressed until you release/toggle off).
2. **Set Interval:** Drag the slider, click a preset (e.g. `100ms`, `1s`, `5s`), or type any millisecond value directly into the text field.
3. **Select Action Target:**
   - Choose **Mouse Button** (Left, Middle, Right, Side, Extra).
   - Or choose **Keyboard Key** (e.g. `G`, `F`, `Space`, `Enter`, `1`).
4. **Choose the Hotkey:** The key, mouse button or combo that starts/stops (or, in *Hold* activation mode, that is held to activate) the clicker, e.g. `F6`, `F13`, `BTN_SIDE` or `ctrl+alt+c`. Type it in the box, pick one from the list, or click **Record** and press it.
5. **Press START SERVICE:** Authenticate if prompted. Your settings are automatically saved and restored on next launch!

---

### CLI Mode

Run the CLI tool directly in your terminal:
```bash
sudo wayclicker [OPTIONS]
```

#### Options

*   `-i, --interval <MS>`: Time in milliseconds between clicks / speed (Default: `100`).
*   `-t, --toggle-key <KEY>`: Key, mouse button or **key combination** that triggers the autoclicker (Default: `F6`). Accepts `left`, `right`, `middle`, `side`, `extra`, `BTN_SIDE`, `F1`-`F24`, `A`-`Z`, `0`-`9`, `SPACE`, keypad keys (`kp5`, `kpenter`), any raw evdev name (`KEY_F20`, ...), and combos joined with `+` such as `ctrl+alt+c`. `ctrl`, `alt`, `shift` and `super` match either the left or right key (use `leftctrl`, `rightalt`, ... to be specific).
*   `--trigger-mode <MODE>`: Activation mode: `hold` (autoclick while held) or `toggle` (click to toggle on/off). Default: `toggle`.
*   `--hold-to-click`: Shorthand flag for `--trigger-mode hold` (autoclicks continuously only while holding down the button/key, stops immediately when released).
*   `-b, --button <BTN>`: Target mouse button (`left`, `right`, `middle`, `side`, `extra`).
*   `-k, --key <KEY>`: Target keyboard key or combo (e.g. `G`, `F`, `Space`, `Enter`, `1`, `W`, `F13`, `ctrl+c`).
*   `--target <TARGET>`: Target button or key name.
*   `-m, --mode <MODE>`: Action mode: `click` (rapid pulse clicks) or `hold` (virtual button held down).
*   `--hold`: Shorthand for `--mode hold`.
*   `--validate`: Only check that the given keys/combos are valid and exit (no root needed).

#### Examples

**1. Hold-to-Click Left Mouse Button (Rapid-fires at 50ms while held):**
```bash
sudo wayclicker --toggle-key left --hold-to-click --interval 50
```

**2. Hold-to-Click Right Mouse Button (Rapid-fires at 25ms while held):**
```bash
sudo wayclicker --toggle-key right --hold-to-click --interval 25
```

**3. Hold-to-Click Middle Mouse Button:**
```bash
sudo wayclicker --toggle-key middle --hold-to-click --interval 50
```

**4. Hold down 'X' on keyboard to spam Left Click:**
```bash
sudo wayclicker --toggle-key X --hold-to-click --interval 30
```

**5. Classic Toggle Mode (Left-click every 100ms, toggle with F6):**
```bash
sudo wayclicker --toggle-key F6 --interval 100
```

**6. Custom delay higher than 1000ms (Click every 5 seconds):**
```bash
sudo wayclicker --interval 5000 --button left
```

**7. Automate pressing keyboard key 'G' every 2.5 seconds:**
```bash
sudo wayclicker --key G --interval 2500 --toggle-key F7
```

**8. Hold down keyboard key 'F' continuously:**
```bash
sudo wayclicker --key F --hold --toggle-key F8
```

**9. Use F13 as the toggle key (or any key your keyboard/macro pad sends, e.g. F21):**
```bash
sudo wayclicker --toggle-key F13 --interval 100
```

**10. Use a key combination as the hotkey (Ctrl + Alt + C toggles clicking):**
```bash
sudo wayclicker --toggle-key "ctrl+alt+c" --interval 50
```

**11. Hold the left mouse button down while the hotkey is held (drag / charge attacks):**
```bash
sudo wayclicker --toggle-key F9 --hold-to-click --button left --mode hold
```

**12. Press a key combination repeatedly (Ctrl+S every 30 seconds):**
```bash
sudo wayclicker --toggle-key F10 --key "ctrl+s" --interval 30000
```

> **Note:** Wayclicker only *listens* to your keyboard, it does not grab it. A hotkey such as `ctrl+alt+c` is therefore still delivered to the focused application too, so pick a combination that does nothing there (or use a dedicated key like `F13`).

---

## 📄 License
This project is licensed under the **GNU General Public License v3.0**. See the `LICENSE` file for the full text.
