#!/usr/bin/env bash
# Builds wayclicker_<version>_amd64.deb from the build output in the repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-$("$ROOT/packaging/version.sh")}"
PKG="$ROOT/wayclicker_${VERSION}_amd64"

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN"
DESTDIR="$PKG" PREFIX=/usr "$ROOT/install.sh" >/dev/null
# Debian keeps licenses under doc/
mkdir -p "$PKG/usr/share/doc/wayclicker"
mv "$PKG/usr/share/licenses/wayclicker/LICENSE" "$PKG/usr/share/doc/wayclicker/copyright"
rm -rf "$PKG/usr/share/licenses"

SIZE="$(du -sk "$PKG/usr" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<CTL
Package: wayclicker
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6, libstdc++6, libgtk-3-0 | libgtk-3-0t64
Recommends: pkexec | policykit-1
Maintainer: Dacraezy1 <https://github.com/Dacraezy1/wayclicker>
Homepage: https://github.com/Dacraezy1/wayclicker
Description: Simple autoclicker for Linux (Wayland and X11)
 Wayclicker clicks or holds mouse buttons and keys on a hotkey. It uses the
 kernel uinput interface, so it works on GNOME, KDE, Hyprland, Sway, X11 and
 every other desktop.
CTL

cat > "$PKG/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  modprobe uinput 2>/dev/null || true
  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=misc --action=add 2>/dev/null || true
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
SH
cat > "$PKG/DEBIAN/postrm" <<'SH'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then udevadm control --reload-rules 2>/dev/null || true; fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null || true
exit 0
SH
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$PKG" "$ROOT/wayclicker_${VERSION}_amd64.deb" >/dev/null
rm -rf "$PKG"
echo "Created wayclicker_${VERSION}_amd64.deb"
