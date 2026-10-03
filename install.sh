#!/usr/bin/env bash
set -e

# Wayclicker Installation Script
# Installs wayclicker CLI and GUI to system directories (/usr/local/bin)

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/wayclicker"
DATA_DIR="$PREFIX/share"
APPS_DIR="$DATA_DIR/applications"
ICONS_DIR="$DATA_DIR/icons/hicolor/scalable/apps"
UDEV_DIR="/etc/udev/rules.d"

# Check root privileges if installing to system paths
if [ "$PREFIX" = "/usr" ] || [ "$PREFIX" = "/usr/local" ] || [ "$PREFIX" = "/etc" ]; then
  if [ "$EUID" -ne 0 ]; then
    echo "Error: Installing to system path '$PREFIX' requires root privileges."
    echo "Please run with sudo:"
    echo "  sudo ./install.sh"
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Installing Wayclicker to $PREFIX ==="

# 1. Locate or build CLI binary
CLI_BIN=""
if [ -f "./wayclicker" ]; then
  CLI_BIN="./wayclicker"
elif [ -f "./output/wayclicker" ]; then
  CLI_BIN="./output/wayclicker"
elif [ -f "./target/release/wayclicker" ]; then
  CLI_BIN="./target/release/wayclicker"
elif command -v cargo >/dev/null 2>&1; then
  echo "Building CLI binary with cargo..."
  cargo build --release
  CLI_BIN="./target/release/wayclicker"
fi

if [ -z "$CLI_BIN" ] || [ ! -f "$CLI_BIN" ]; then
  echo "Error: CLI binary 'wayclicker' could not be found or built."
  exit 1
fi

mkdir -p "$BIN_DIR"
echo "-> Installing CLI binary to $BIN_DIR/wayclicker..."
install -m 755 -D "$CLI_BIN" "$BIN_DIR/wayclicker"
chown root:root "$BIN_DIR/wayclicker" 2>/dev/null || true

# 2. Check for GUI bundle
GUI_SRC=""
if [ -f "./wayclicker_gui" ]; then
  GUI_SRC="."
elif [ -d "./output" ] && [ -f "./output/wayclicker_gui" ]; then
  GUI_SRC="./output"
elif [ -d "./gui/build/linux/x64/release/bundle" ]; then
  GUI_SRC="./gui/build/linux/x64/release/bundle"
fi

if [ -n "$GUI_SRC" ] && [ -f "$GUI_SRC/wayclicker_gui" ]; then
  echo "-> Installing GUI application to $LIB_DIR..."
  mkdir -p "$LIB_DIR"
  cp -r "$GUI_SRC/wayclicker_gui" "$LIB_DIR/"
  [ -d "$GUI_SRC/lib" ] && cp -r "$GUI_SRC/lib" "$LIB_DIR/"
  [ -d "$GUI_SRC/data" ] && cp -r "$GUI_SRC/data" "$LIB_DIR/"
  chmod -R 755 "$LIB_DIR"
  chown -R root:root "$LIB_DIR" 2>/dev/null || true

  # Symlink to bin
  ln -sf "$LIB_DIR/wayclicker_gui" "$BIN_DIR/wayclicker-gui"
  echo "-> Created launcher symlink: $BIN_DIR/wayclicker-gui"

  # Desktop entry
  mkdir -p "$APPS_DIR"
  DESKTOP_SRC="./wayclicker.desktop"
  if [ -f "$DESKTOP_SRC" ]; then
    install -m 644 "$DESKTOP_SRC" "$APPS_DIR/wayclicker.desktop"
    echo "-> Installed desktop entry: $APPS_DIR/wayclicker.desktop"
  fi

  # Icon
  mkdir -p "$ICONS_DIR"
  ICON_SRC="./assets/wayclicker.svg"
  if [ -f "$ICON_SRC" ]; then
    install -m 644 "$ICON_SRC" "$ICONS_DIR/wayclicker.svg"
    echo "-> Installed icon: $ICONS_DIR/wayclicker.svg"
  fi

  # Also install desktop entry to /usr/share/applications if prefix is /usr/local
  if [ "$PREFIX" = "/usr/local" ] && [ -d "/usr/share/applications" ]; then
    install -m 644 "$DESKTOP_SRC" "/usr/share/applications/wayclicker.desktop" 2>/dev/null || true
    if [ -f "$ICON_SRC" ] && [ -d "/usr/share/icons/hicolor/scalable/apps" ]; then
      install -m 644 "$ICON_SRC" "/usr/share/icons/hicolor/scalable/apps/wayclicker.svg" 2>/dev/null || true
    fi
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    [ "$PREFIX" = "/usr/local" ] && update-desktop-database "/usr/share/applications" 2>/dev/null || true
  fi
else
  echo "-> GUI bundle not present. Skipping GUI installation (CLI only)."
fi

# 3. Optional udev rule for uinput device permissions (requires root)
if [ "$EUID" -eq 0 ] && [ -d "$UDEV_DIR" ]; then
  echo "-> Configuring udev rule for /dev/uinput..."
  cat <<'EOF' > "$UDEV_DIR/99-wayclicker.rules"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
EOF
  chmod 644 "$UDEV_DIR/99-wayclicker.rules"

  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
  fi
  echo "-> Installed udev rule to $UDEV_DIR/99-wayclicker.rules"
fi

echo ""
echo "=== Installation Complete! ==="
echo "CLI binary: $BIN_DIR/wayclicker"
if [ -f "$BIN_DIR/wayclicker-gui" ]; then
  echo "GUI binary: $BIN_DIR/wayclicker-gui"
fi
echo ""
echo "Usage:"
echo "  Run CLI:  wayclicker --help"
echo "  Run GUI:  wayclicker-gui"
echo ""
