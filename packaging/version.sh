#!/usr/bin/env bash
# Prints the version from Cargo.toml (the single source of truth).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -m1 '^version' "$ROOT/Cargo.toml" | cut -d'"' -f2
