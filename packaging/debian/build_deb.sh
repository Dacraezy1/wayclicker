#!/usr/bin/env bash
set -e

# Script to build a Debian package (.deb)
VERSION="${VERSION:-0.2.1}"
ARCH="amd64"
PKG_DIR="wayclicker_${VERSION}_${ARCH}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Building Debian Package: $PKG_DIR.deb ==="

rm -rf "$ROOT_DIR/$PKG_DIR"
mkdir -p "$ROOT_DIR/$PKG_DIR/DEBIAN"
mkdir -p "$ROOT_DIR/$PKG_DIR/usr/bin"
mkdir -p "$ROOT_DIR/$PKG_DIR/usr/lib/wayclicker"
mkdir -p "$ROOT_DIR/$PKG_DIR/usr/share/applications"
mkdir -p "$ROOT_DIR/$PKG_DIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$ROOT_DIR/$PKG_DIR/lib/udev/rules.d"

# 1. Control file
cat <<EOF > "$ROOT_DIR/$PKG_DIR/DEBIAN/control"
Package: wayclicker
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libc6, libgtk-3-0
Recommends: policykit-1
Maintainer: Dacraezy1 <https://github.com/Dacraezy1/wayclicker>
Description: Powerful universal autoclicker for Linux (Wayland & X11)
 Wayclicker uses Linux kernel uinput to simulate mouse and keyboard events universally
 across Wayland (GNOME, KDE, Hyprland, Sway) and X11 environments.
EOF

# 2. Copy binaries
if [ -f "$ROOT_DIR/target/release/wayclicker" ]; then
  install -m 755 "$ROOT_DIR/target/release/wayclicker" "$ROOT_DIR/$PKG_DIR/usr/bin/wayclicker"
elif [ -f "$ROOT_DIR/wayclicker" ]; then
  install -m 755 "$ROOT_DIR/wayclicker" "$ROOT_DIR/$PKG_DIR/usr/bin/wayclicker"
fi

# GUI bundle if present
if [ -d "$ROOT_DIR/output" ] && [ -f "$ROOT_DIR/output/wayclicker_gui" ]; then
  cp -r "$ROOT_DIR/output/." "$ROOT_DIR/$PKG_DIR/usr/lib/wayclicker/"
  ln -sf "/usr/lib/wayclicker/wayclicker_gui" "$ROOT_DIR/$PKG_DIR/usr/bin/wayclicker-gui"
elif [ -d "$ROOT_DIR/gui/build/linux/x64/release/bundle" ]; then
  cp -r "$ROOT_DIR/gui/build/linux/x64/release/bundle/." "$ROOT_DIR/$PKG_DIR/usr/lib/wayclicker/"
  ln -sf "/usr/lib/wayclicker/wayclicker_gui" "$ROOT_DIR/$PKG_DIR/usr/bin/wayclicker-gui"
fi

# 3. Assets & desktop file
[ -f "$ROOT_DIR/wayclicker.desktop" ] && cp "$ROOT_DIR/wayclicker.desktop" "$ROOT_DIR/$PKG_DIR/usr/share/applications/"
[ -f "$ROOT_DIR/assets/wayclicker.svg" ] && cp "$ROOT_DIR/assets/wayclicker.svg" "$ROOT_DIR/$PKG_DIR/usr/share/icons/hicolor/scalable/apps/"
[ -f "$ROOT_DIR/packaging/udev/99-wayclicker.rules" ] && cp "$ROOT_DIR/packaging/udev/99-wayclicker.rules" "$ROOT_DIR/$PKG_DIR/lib/udev/rules.d/"

# 4. Build deb
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$ROOT_DIR/$PKG_DIR"
  echo "Debian package created: $ROOT_DIR/${PKG_DIR}.deb"
else
  echo "dpkg-deb not found. Staging directory prepared at: $ROOT_DIR/$PKG_DIR"
fi
