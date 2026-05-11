#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

usage() {
  echo "Usage: $0 [app_path]"
  echo ""
  echo "Tests DMG packaging with styled background and icon positions."
  echo ""
  echo "If app_path is not provided, will look for:"
  echo "  1. .build/OpenBridge.xcarchive/Products/Applications/OpenBridge.app"
  echo "  2. /Applications/OpenBridge.app"
  echo ""
  echo "Output: .build/test-OpenBridge.dmg"
  echo ""
  echo "Examples:"
  echo "  $0                          # Auto-detect app location"
  echo "  $0 /path/to/MyApp.app       # Use specific app"
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

# Find app path
APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  # Try archive location first
  ARCHIVE_APP="$MACOS_ROOT/.build/OpenBridge.xcarchive/Products/Applications/OpenBridge.app"
  if [[ -d "$ARCHIVE_APP" ]]; then
    APP_PATH="$ARCHIVE_APP"
    echo "[i] found app in archive: $APP_PATH"
  elif [[ -d "/Applications/OpenBridge.app" ]]; then
    APP_PATH="/Applications/OpenBridge.app"
    echo "[i] found app in Applications: $APP_PATH"
  else
    echo "[-] could not find OpenBridge.app"
    echo "[i] provide app path as argument or build the app first"
    exit 1
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "[-] app not found: $APP_PATH"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
OUTPUT_DIR="$MACOS_ROOT/.build"
OUTPUT_DMG="$OUTPUT_DIR/test-${APP_NAME%.app}.dmg"

mkdir -p "$OUTPUT_DIR"

echo "[*] testing DMG packaging"
echo "[i] app: $APP_PATH"
echo "[i] output: $OUTPUT_DMG"
echo ""

"$SCRIPT_DIR/create-styled-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"

echo ""
echo "[+] test complete!"
echo "[i] opening DMG for preview..."
open "$OUTPUT_DMG"
