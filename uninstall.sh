#!/usr/bin/env bash
# Removes what install.sh installed. Use the same PREFIX you installed with.
#   sudo ./uninstall.sh
#   sudo PREFIX=/usr ./uninstall.sh
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

is_root() { [ "$(id -u)" -eq 0 ]; }

case "$PREFIX" in
  /usr|/usr/local|/opt*|/etc*)
    if ! is_root; then
      echo "Uninstalling from $PREFIX needs root. Run:  sudo ./uninstall.sh"
      exit 1
    fi
    ;;
esac

echo "=== Removing Wayclicker from $PREFIX ==="
rm -f "$PREFIX/bin/wayclicker" "$PREFIX/bin/wayclicker-gui"
rm -rf "$PREFIX/lib/wayclicker"
rm -f "$PREFIX/share/applications/wayclicker.desktop"
rm -f "$PREFIX/share/icons/hicolor/scalable/apps/wayclicker.svg"
rm -rf "$PREFIX/share/licenses/wayclicker"

if is_root; then
  rm -f /etc/udev/rules.d/60-wayclicker.rules /usr/lib/udev/rules.d/60-wayclicker.rules
  rm -f /etc/udev/rules.d/99-wayclicker.rules /usr/lib/udev/rules.d/99-wayclicker.rules
  rm -f /etc/modules-load.d/wayclicker.conf /usr/lib/modules-load.d/wayclicker.conf
  command -v udevadm >/dev/null 2>&1 && udevadm control --reload-rules 2>/dev/null || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi

echo "=== Done ==="
echo "Your settings in ~/.config/wayclicker were kept."
