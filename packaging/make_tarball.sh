#!/usr/bin/env bash
# Creates wayclicker-linux-x64.tar.gz (portable release folder with installer).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BUNDLE="gui/build/linux/x64/release/bundle"
[ -x "$BUNDLE/wayclicker_gui" ] || { echo "GUI bundle missing: build it with 'flutter build linux --release' in gui/"; exit 1; }
[ -x target/release/wayclicker ] || { echo "CLI missing: run 'cargo build --release'"; exit 1; }

OUT=wayclicker-release
rm -rf "$OUT" wayclicker-linux-x64.tar.gz
mkdir -p "$OUT/assets" "$OUT/packaging"
cp -r "$BUNDLE"/. "$OUT/"
cp target/release/wayclicker "$OUT/"
cp install.sh uninstall.sh wayclicker.desktop LICENSE README.md "$OUT/"
cp assets/wayclicker.svg "$OUT/assets/"
cp -r packaging/udev packaging/modules-load "$OUT/packaging/"
tar -czf wayclicker-linux-x64.tar.gz "$OUT"
echo "Created wayclicker-linux-x64.tar.gz"
