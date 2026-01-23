# Wayland Autoclicker

A powerful and fast autoclicker designed for Linux systems using the Wayland display server.

Created by: **Dacraezy1**

## ⚠️ Compatibility

This tool relies on the `wlr-virtual-pointer-v1` protocol. It currently **ONLY** works on **wlroots-based compositors**, such as:
*   **Hyprland**
*   **Sway**
*   **Wayfire**
*   **River**

It will **NOT** work on standard GNOME or KDE Plasma (unless they have added specific support for this protocol).

## 🛠️ Building

### Prerequisites

You need the Rust toolchain installed. You also need system development libraries for Wayland.

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install build-essential libwayland-dev libxkbcommon-dev pkg-config
```

**Arch Linux:**
```bash
sudo pacman -S base-devel wayland libxkbcommon
```

**Fedora:**
```bash
sudo dnf install gcc wayland-devel libxkbcommon-devel
```

### Installation

1.  Clone this repository:
    ```bash
    git clone https://github.com/Dacraezy1/wayland-autoclicker.git
    cd wayland-autoclicker
    ```
2.  Build the project in release mode:
    ```bash
    cargo build --release
    ```
3.  The executable will be located at `target/release/wayland-autoclicker`.

## 🚀 Usage

The autoclicker monitors your physical keyboard to toggle clicking. Because it reads directly from input devices (`/dev/input/*`), **root privileges (sudo) are required**.

```bash
sudo ./target/release/wayland-autoclicker [OPTIONS]
```

### Options

*   `-i, --interval <MS>`: Time in milliseconds between clicks (Default: `100`).
*   `-t, --toggle-key <KEY>`: The key to toggle clicking on/off (Default: `F6`).
    *   Common keys: `F1`-`F12`, `X`, `Z`, `BTN_LEFT`, `BTN_RIGHT`.
*   `-b, --button <BTN>`: The mouse button to click (Default: `left`).
    *   Options: `left`, `right`, `middle`.

### Examples

**1. Basic usage (Click every 100ms, toggle with F6):**
```bash
sudo ./target/release/wayland-autoclicker
```

**2. Fast clicking (25ms) using the 'X' key to toggle:**
```bash
sudo ./target/release/wayland-autoclicker --interval 25 --toggle-key X
```

**3. Spam Right-Click with 500ms interval:**
```bash
sudo ./target/release/wayland-autoclicker --button right --interval 500
```

## 🔧 Troubleshooting

*   **"Compositor does not support..."**: You are likely running GNOME, KDE, or another compositor that does not support the `wlr-virtual-pointer` protocol.
*   **"No keyboard device found"**: Ensure you are running with `sudo`. The program needs permission to scan `/dev/input/` to find your keyboard.

## License

This project is licensed under the **GNU General Public License v3.0**. See the `LICENSE` file for the full text.
