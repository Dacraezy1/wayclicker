#!/usr/bin/env bash
# Builds wayclicker-<version>-1.x86_64.rpm (needs the "rpm" package for rpmbuild).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-$("$ROOT/packaging/version.sh")}"
TOP="$ROOT/.rpmbuild"

rm -rf "$TOP"
mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
rpmbuild -bb "$ROOT/packaging/rpm/wayclicker.spec" \
  --define "_topdir $TOP" \
  --define "wc_version $VERSION" \
  --define "wc_src $ROOT" \
  --define "_binary_payload w9.xzdio" \
  --define "_binary_filedigest_algorithm 1" \
  --target x86_64 >/dev/null
cp "$TOP"/RPMS/x86_64/*.rpm "$ROOT/"
rm -rf "$TOP"
echo "Created $(cd "$ROOT" && ls wayclicker-${VERSION}-*.rpm)"
