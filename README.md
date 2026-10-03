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
- **Flexible Activation Keys:** Toggle with any keyboard key or mouse button (`F1`-`F12`, `A`-`Z`, `BTN_SIDE`, etc.).
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

1. **Select Action Mode:** Choose **Click (Repeat)** or **Hold (Continuous)**.
2. **Set Interval:** Drag the slider, click a preset (e.g. `100ms`, `1s`, `5s`), or type any millisecond value directly into the text field.
3. **Select Action Target:**
   - Choose **Mouse Button** (Left, Middle, Right, Side, Extra).
   - Or choose **Keyboard Key** (e.g. `G`, `F`, `Space`, `Enter`, `1`).
4. **Choose Activation Toggle Key:** The key or mouse button that starts/stops clicking (e.g. `F6`, `X`, `BTN_SIDE`).
5. **Press START SERVICE:** Authenticate if prompted. Your settings are automatically saved and restored on next launch!

---

### CLI Mode

Run the CLI tool directly in your terminal:
```bash
sudo wayclicker [OPTIONS]
```

#### Options

*   `-i, --interval <MS>`: Time in milliseconds between clicks (Default: `100`).
*   `-t, --toggle-key <KEY>`: Key to toggle on/off (Default: `F6`). Supports `F1`-`F12`, `A`-`Z`, `0`-`9`, `BTN_LEFT`, `BTN_RIGHT`, `BTN_SIDE`, `SPACE`, etc.
*   `-b, --button <BTN>`: Target mouse button (`left`, `right`, `middle`, `side`, `extra`).
*   `-k, --key <KEY>`: Target keyboard key (e.g. `G`, `F`, `Space`, `Enter`, `1`, `W`).
*   `--target <TARGET>`: Target button or key name.
*   `-m, --mode <MODE>`: Action mode: `click` or `hold` (Default: `click`).
*   `--hold`: Shorthand flag for `--mode hold`.

#### Examples

**1. Basic Clicker (Left-click every 100ms, toggle with F6):**
```bash
sudo wayclicker
```

**2. Custom delay higher than 1000ms (Click every 5 seconds):**
```bash
sudo wayclicker --interval 5000 --button left
```

**3. Hold Left Mouse Button continuously (Toggle with F6):**
```bash
sudo wayclicker --button left --hold
```

**4. Hold Right Mouse Button (Toggle with 'X'):**
```bash
sudo wayclicker --button right --hold --toggle-key X
```

**5. Automate pressing keyboard key 'G' every 2.5 seconds:**
```bash
sudo wayclicker --key G --interval 2500 --toggle-key F7
```

**6. Hold down keyboard key 'F' continuously:**
```bash
sudo wayclicker --key F --hold --toggle-key F8
```

**7. Mouse side button toggle (BTN_SIDE):**
```bash
sudo wayclicker --toggle-key BTN_SIDE --button left --interval 50
```

---

## 📄 License
This project is licensed under the **GNU General Public License v3.0**. See the `LICENSE` file for the full text.
