#!/usr/bin/env bash
# Wayclicker installer.
#
#   sudo ./install.sh                       install to /usr/local
#   sudo PREFIX=/usr ./install.sh           install to /usr
#   PREFIX=$HOME/.local ./install.sh        install for your user only (no root)
#   DESTDIR=/tmp/pkg PREFIX=/usr ./install.sh   stage files for a package (no root)
#
# Works from the extracted release folder, or from a repository checkout after
# building (cargo build --release; flutter build linux --release).
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="$DESTDIR$PREFIX/bin"
LIB_DIR="$DESTDIR$PREFIX/lib/wayclicker"
APPS_DIR="$DESTDIR$PREFIX/share/applications"
ICONS_DIR="$DESTDIR$PREFIX/share/icons/hicolor/scalable/apps"

# System udev rules and module lists live in /usr/lib for /usr, otherwise /etc.
if [ "$PREFIX" = "/usr" ]; then
  UDEV_DIR="$DESTDIR/usr/lib/udev/rules.d"
  MODULES_DIR="$DESTDIR/usr/lib/modules-load.d"
else
  UDEV_DIR="$DESTDIR/etc/udev/rules.d"
  MODULES_DIR="$DESTDIR/etc/modules-load.d"
fi

is_root() { [ "$(id -u)" -eq 0 ]; }

# Real installs under system paths need root.
if [ -z "$DESTDIR" ] && ! is_root; then
  case "$PREFIX" in
    /usr|/usr/local|/opt*|/etc*)
      echo "Installing to $PREFIX needs root. Run:  sudo ./install.sh"
      echo "For a user-only install:  PREFIX=\$HOME/.local ./install.sh"
      exit 1
      ;;
  esac
fi

# ---- find what to install --------------------------------------------------
find_first() { for f in "$@"; do [ -e "$f" ] && { echo "$f"; return 0; }; done; return 1; }

CLI="$(find_first "$SRC/wayclicker" "$SRC/output/wayclicker" "$SRC/target/release/wayclicker" || true)"
if [ -z "$CLI" ] && command -v cargo >/dev/null 2>&1 && [ -f "$SRC/Cargo.toml" ]; then
  echo "Building the command-line program with cargo..."
  (cd "$SRC" && cargo build --release --locked)
  CLI="$SRC/target/release/wayclicker"
fi
if [ -z "$CLI" ]; then
  echo "Error: the 'wayclicker' program was not found. Build it first (cargo build --release)."
  exit 1
fi

GUI_DIR=""
for d in "$SRC" "$SRC/output" "$SRC/gui/build/linux/x64/release/bundle"; do
  if [ -x "$d/wayclicker_gui" ]; then GUI_DIR="$d"; break; fi
done

DESKTOP="$(find_first "$SRC/wayclicker.desktop" || true)"
ICON="$(find_first "$SRC/assets/wayclicker.svg" || true)"
UDEV_RULE="$(find_first "$SRC/packaging/udev/60-wayclicker.rules" || true)"
MODULES_CONF="$(find_first "$SRC/packaging/modules-load/wayclicker.conf" || true)"
LICENSE_FILE="$(find_first "$SRC/LICENSE" || true)"

echo "=== Installing Wayclicker to ${DESTDIR}${PREFIX} ==="

# ---- program files ---------------------------------------------------------
if [ -n "$GUI_DIR" ]; then
  # The GUI looks for the CLI next to itself, so keep them together.
  install -d "$LIB_DIR" "$BIN_DIR"
  cp -a "$GUI_DIR/wayclicker_gui" "$GUI_DIR/lib" "$GUI_DIR/data" "$LIB_DIR/"
  install -m 755 "$CLI" "$LIB_DIR/wayclicker"
  ln -sf "$PREFIX/lib/wayclicker/wayclicker" "$BIN_DIR/wayclicker"
  ln -sf "$PREFIX/lib/wayclicker/wayclicker_gui" "$BIN_DIR/wayclicker-gui"
  echo "-> Installed GUI and command-line program"
else
  install -Dm755 "$CLI" "$BIN_DIR/wayclicker"
  echo "-> Installed command-line program (no GUI found, skipping it)"
fi

if [ -n "$GUI_DIR" ]; then
  [ -n "$DESKTOP" ] && install -Dm644 "$DESKTOP" "$APPS_DIR/wayclicker.desktop"
  [ -n "$ICON" ] && install -Dm644 "$ICON" "$ICONS_DIR/wayclicker.svg"
fi
if [ -n "$LICENSE_FILE" ]; then
  install -Dm644 "$LICENSE_FILE" "$DESTDIR$PREFIX/share/licenses/wayclicker/LICENSE"
fi

# ---- permissions (uinput) --------------------------------------------------
SYSTEM_FILES=0
if [ -n "$DESTDIR" ] || is_root; then
  [ -n "$UDEV_RULE" ] && install -Dm644 "$UDEV_RULE" "$UDEV_DIR/60-wayclicker.rules"
  [ -n "$MODULES_CONF" ] && install -Dm644 "$MODULES_CONF" "$MODULES_DIR/wayclicker.conf"
  SYSTEM_FILES=1
fi

# ---- refresh system caches (only for a real install as root) ---------------
if [ -z "$DESTDIR" ] && is_root; then
  # Remove the udev rule shipped by older versions (it was named too late to work).
  rm -f /etc/udev/rules.d/99-wayclicker.rules /usr/lib/udev/rules.d/99-wayclicker.rules
  modprobe uinput 2>/dev/null || true
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=misc --action=add 2>/dev/null || true
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f "$PREFIX/share/icons/hicolor" 2>/dev/null || true
fi

echo "=== Done ==="
if [ -z "$DESTDIR" ]; then
  echo "Start the app:   wayclicker-gui"
  echo "Command line:    wayclicker --help"
  if [ "$SYSTEM_FILES" -eq 0 ]; then
    echo "Note: run the installer as root once to set up uinput permissions."
  else
    echo "To use it without a password prompt: sudo usermod -aG input \$USER   (then log out and in)"
  fi
fi
