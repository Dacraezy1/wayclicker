#!/usr/bin/env bash
# Builds everything locally: the CLI, the GUI and the portable tarball.
# Needs: Rust (cargo) and the Flutter SDK. Output: wayclicker-linux-x64.tar.gz
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> Building the command-line program"
cargo build --release --locked

echo "==> Building the GUI"
(cd gui && flutter pub get && flutter build linux --release)

echo "==> Creating the tarball"
./packaging/make_tarball.sh
echo "Done. Install with:  tar xzf wayclicker-linux-x64.tar.gz && cd wayclicker-release && sudo ./install.sh"
