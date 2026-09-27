#!/bin/bash
# install.sh — Downloads and installs the latest DocMD CLI release on Linux.
#
# Usage:
#   curl -fsSL https://docmd.ccisne.dev/install.sh | bash

set -euo pipefail

REPO="ccisnedev/docmd"
INSTALL_DIR="$HOME/.docmd"
BIN_DIR="$INSTALL_DIR/bin"
ASSET_NAME="docmd-linux-x64.tar.gz"

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

TEMP_FILE=$(mktemp /tmp/docmd-XXXXXX.tar.gz)

echo ">>> Downloading..."
curl -fsSL -o "$TEMP_FILE" "$DOWNLOAD_URL"

if [ -d "$INSTALL_DIR" ]; then
  echo ">>> Removing previous installation..."
  rm -rf "$INSTALL_DIR"
fi

echo ">>> Extracting..."
mkdir -p "$INSTALL_DIR"
tar xzf "$TEMP_FILE" -C "$INSTALL_DIR"
rm -f "$TEMP_FILE"

chmod +x "$BIN_DIR/docmd"

LINK_DIR="$HOME/.local/bin"
mkdir -p "$LINK_DIR"
ln -sf "$BIN_DIR/docmd" "$LINK_DIR/docmd"
echo ">>> Symlink configured: $LINK_DIR/docmd -> $BIN_DIR/docmd"

if [[ ":$PATH:" != *":$LINK_DIR:"* ]]; then
  export PATH="$LINK_DIR:$PATH"
  echo ">>> Added $LINK_DIR to PATH for this session"
fi

for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$RC_FILE" ] || continue
  if ! grep -q '\.local/bin' "$RC_FILE"; then
    printf '\n# Added by DocMD CLI installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC_FILE"
    echo ">>> Added ~/.local/bin to PATH in $(basename "$RC_FILE")"
  fi
done

echo ">>> Verifying installation..."
VERSION_OUTPUT=$("$BIN_DIR/docmd" version)
echo "    $VERSION_OUTPUT"

echo ""
echo ">>> DocMD CLI installed successfully!"
echo "    Location: $INSTALL_DIR"