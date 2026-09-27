#!/bin/bash
# install.sh — Downloads and installs the latest DocMD CLI release on Linux.
#
# Usage:
#   curl -fsSL https://docmd.ccisne.dev/install.sh | bash

set -euo pipefail

REPO="ccisnedev/docmd"
BIN_DIR="$HOME/.local/bin"
ASSET_NAME="docmd-linux-x64"
EXECUTABLE="docmd"
ALIAS="dm"

ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" != "Linux" ]; then
  echo "Error: DocMD CLI install.sh is for Linux only. Got: $OS" >&2
  exit 1
fi

if [ "$ARCH" != "x86_64" ]; then
  echo "Error: DocMD CLI requires x86_64. Got: $ARCH" >&2
  exit 1
fi

echo ">>> Fetching latest release..."
RELEASE_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" "$RELEASE_URL")

TAG=$(echo "$RELEASE_JSON" | grep -o '"tag_name":\s*"[^"]*"' | head -1 | sed 's/.*"tag_name":\s*"\([^"]*\)".*/\1/')
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url":\s*"[^"]*'"$ASSET_NAME"'"' | head -1 | sed 's/.*"browser_download_url":\s*"\([^"]*\)".*/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: No $ASSET_NAME asset found in release $TAG." >&2
  exit 1
fi

echo "    Release: $TAG"
echo "    Asset:   $ASSET_NAME"

# The release asset is the raw compiled executable, not an archive:
# InstallationPlugin's `upgrade` command writes it directly over
# $BIN_DIR/$EXECUTABLE's current location, so the installer does the
# equivalent here on first install.
mkdir -p "$BIN_DIR"
TARGET_PATH="$BIN_DIR/$EXECUTABLE"
TEMP_FILE=$(mktemp "$BIN_DIR/.$EXECUTABLE.XXXXXX")

echo ">>> Downloading..."
curl -fsSL -o "$TEMP_FILE" "$DOWNLOAD_URL"
chmod +x "$TEMP_FILE"
# Atomic swap: never leaves a half-written binary at $TARGET_PATH, and is
# safe even if a previous docmd process is still running.
mv -f "$TEMP_FILE" "$TARGET_PATH"

# `dm` is a short alias for `docmd`. It is a symlink, not a copy, so
# `docmd doctor`'s alias check (which compares them by inode) recognizes them
# as the same binary.
ln -sf "$EXECUTABLE" "$BIN_DIR/$ALIAS"
echo ">>> Alias configured: $BIN_DIR/$ALIAS -> $EXECUTABLE"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  export PATH="$BIN_DIR:$PATH"
  echo ">>> Added $BIN_DIR to PATH for this session"
fi

for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$RC_FILE" ] || continue
  if ! grep -q '\.local/bin' "$RC_FILE"; then
    printf '\n# Added by DocMD CLI installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC_FILE"
    echo ">>> Added ~/.local/bin to PATH in $(basename "$RC_FILE")"
  fi
done

echo ">>> Verifying installation..."
VERSION_OUTPUT=$("$TARGET_PATH" version)
echo "    $VERSION_OUTPUT"

echo ""
echo ">>> DocMD CLI installed successfully!"
echo "    Location: $TARGET_PATH"
