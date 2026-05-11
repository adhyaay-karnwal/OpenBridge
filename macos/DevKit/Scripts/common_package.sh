#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
REPO_ROOT=$(cd "$MACOS_ROOT/.." && pwd)

ARCHIVE_PATH="$MACOS_ROOT/.build/OpenBridge.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/OpenBridge.app"
ARTIFACT_DIR="$REPO_ROOT/artifacts"
DMG_SOURCE="$MACOS_ROOT/.build/OpenBridge.dmg"
ARTIFACT_PATH="$ARTIFACT_DIR/OpenBridge.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"

if [[ -f "$DMG_SOURCE" ]]; then
  echo "[*] Using existing notarized DMG from $DMG_SOURCE"
  cp "$DMG_SOURCE" "$ARTIFACT_PATH"
else
  echo "[*] Creating styled DMG from app..."
  "$SCRIPT_DIR/create-styled-dmg.sh" "$APP_PATH" "$ARTIFACT_PATH"
fi

echo "[*] Packaged DMG to $ARTIFACT_PATH"
