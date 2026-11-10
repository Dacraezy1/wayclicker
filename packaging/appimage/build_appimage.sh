#!/usr/bin/env bash
# Builds Wayclicker-<version>-x86_64.AppImage. Needs appimagetool on PATH
# (or set APPIMAGETOOL=/path/to/it).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-$("$ROOT/packaging/version.sh")}"
TOOL="${APPIMAGETOOL:-appimagetool}"
APPDIR="$ROOT/Wayclicker.AppDir"

rm -rf "$APPDIR"
DESTDIR="$APPDIR" PREFIX=/usr "$ROOT/install.sh" >/dev/null
# Keep the AppImage free of system-only files.
rm -rf "$APPDIR/usr/lib/udev" "$APPDIR/usr/lib/modules-load.d"

cp "$ROOT/wayclicker.desktop" "$APPDIR/wayclicker.desktop"
cp "$ROOT/assets/wayclicker.svg" "$APPDIR/wayclicker.svg"

cat > "$APPDIR/AppRun" <<'SH'
#!/bin/sh
# Starts the GUI. "AppImage --cli <options>" runs the command-line program.
HERE="$(dirname "$(readlink -f "$0")")"
if [ "$1" = "--cli" ]; then
  shift
  exec "$HERE/usr/lib/wayclicker/wayclicker" "$@"
fi
exec "$HERE/usr/lib/wayclicker/wayclicker_gui" "$@"
SH
chmod +x "$APPDIR/AppRun"

OUT="$ROOT/Wayclicker-${VERSION}-x86_64.AppImage"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUT" >/dev/null 2>&1 \
  || ARCH=x86_64 "$TOOL" --no-appstream "$APPDIR" "$OUT"
rm -rf "$APPDIR"
echo "Created $(basename "$OUT")"
