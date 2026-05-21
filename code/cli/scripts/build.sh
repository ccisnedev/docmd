#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$CLI_DIR/build"
BIN_DIR="$BUILD_DIR/bin"

rm -rf "$BUILD_DIR"
mkdir -p "$BIN_DIR"

cd "$CLI_DIR"
dart compile exe bin/main.dart -o "$BIN_DIR/docmd"

echo "Build complete: $BUILD_DIR"
