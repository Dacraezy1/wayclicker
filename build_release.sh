#!/bin/bash

set -e

# Define paths
ROOT_DIR=$(pwd)
OUTPUT_DIR="$ROOT_DIR/output"
FLUTTER_BUNDLE="$ROOT_DIR/gui/build/linux/x64/release/bundle"

echo "Starting Build Process..."

# Build the CLI binary
echo "Building CLI Binary..."
cargo build --release

# Build the Flutter GUI
echo "Building Flutter GUI..."
cd gui
flutter build linux --release
cd ..

# Prepare Output Directory
echo "Organizing files..."
# Remove old output if it exists and recreate it
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy the Flutter bundle
cp -r "$FLUTTER_BUNDLE/." "$OUTPUT_DIR/"

# Copy the CLI Binary into the output folder
cp "$ROOT_DIR/target/release/wayclicker" "$OUTPUT_DIR/"

echo "Done!"
echo "Output Directory: $OUTPUT_DIR"
