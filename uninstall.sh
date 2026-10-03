#!/usr/bin/env bash
set -e

# Wayclicker Uninstallation Script

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/wayclicker"
DATA_DIR="$PREFIX/share"
APPS_DIR="$DATA_DIR/applications"
ICONS_DIR="$DATA_DIR/icons/hicolor/scalable/apps"
UDEV_DIR="/etc/udev/rules.d"

# Check root privileges if uninstalling from system paths
if [ "$PREFIX" = "/usr" ] || [ "$PREFIX" = "/usr/local" ] || [ "$PREFIX" = "/etc" ]; then
  if [ "$EUID" -ne 0 ]; then
    echo "Error: Uninstalling from system path '$PREFIX' requires root privileges."
    echo "Please run with sudo:"
    echo "  sudo ./uninstall.sh"
    exit 1
  fi
fi

echo "=== Uninstalling Wayclicker from $PREFIX ==="

rm -f "$BIN_DIR/wayclicker"
rm -f "$BIN_DIR/wayclicker-gui"
rm -rf "$LIB_DIR"
rm -f "$APPS_DIR/wayclicker.desktop"
rm -f "/usr/share/applications/wayclicker.desktop"
rm -f "$ICONS_DIR/wayclicker.svg"
rm -f "/usr/share/icons/hicolor/scalable/apps/wayclicker.svg"
if [ "$EUID" -eq 0 ]; then
  rm -f "$UDEV_DIR/99-wayclicker.rules"
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
  fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" 2>/dev/null || true
  update-desktop-database "/usr/share/applications" 2>/dev/null || true
fi

echo "=== Uninstallation Complete! ==="
