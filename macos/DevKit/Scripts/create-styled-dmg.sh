#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# Resources
INSTALLER_RESOURCES="$MACOS_ROOT/Resources/Installer"
CONFIG_FILE="$INSTALLER_RESOURCES/install-bg-app-rect.json"

usage() {
  echo "Usage: $0 <app_path> <output_dmg_path>"
  echo ""
  echo "Creates a styled DMG with custom background and icon positions."
  echo "Uses appdmg (no AppleScript/Finder required - works on CI)."
  echo ""
  echo "Arguments:"
  echo "  app_path        Path to the .app bundle"
  echo "  output_dmg_path Path for the output DMG file"
  echo ""
  echo "Example:"
  echo "  $0 /path/to/OpenBridge.app /path/to/output/OpenBridge.dmg"
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

APP_PATH="$1"
OUTPUT_DMG="$2"

if [[ ! -d "$APP_PATH" ]]; then
  echo "[-] app path does not exist: $APP_PATH"
  exit 1
fi

if [[ ! "$APP_PATH" =~ \.app$ ]]; then
  echo "[-] provided path is not a .app bundle: $APP_PATH"
  exit 1
fi

# Check Node.js is available
if ! command -v node &> /dev/null; then
  echo "[-] node is not installed"
  exit 1
fi

# Check resources
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[-] config file not found: $CONFIG_FILE"
  exit 1
fi

# Install npm dependencies if needed
if [[ ! -d "$SCRIPT_DIR/node_modules" ]]; then
  echo "[*] installing npm dependencies..."
  pushd "$SCRIPT_DIR" > /dev/null
  npm install --prefer-offline --no-audit --no-fund 2>&1 | grep -v "^npm " || true
  popd > /dev/null
fi

# Remove existing DMG if exists
if [[ -f "$OUTPUT_DMG" ]]; then
  echo "[*] removing existing DMG"
  rm -f "$OUTPUT_DMG"
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_DMG")"

# Run the Node.js script to create DMG using appdmg
# appdmg creates .DS_Store files programmatically instead of using AppleScript
node "$SCRIPT_DIR/create-dmg.mjs" "$APP_PATH" "$OUTPUT_DMG"

if [[ ! -f "$OUTPUT_DMG" ]]; then
  echo "[-] DMG creation failed"
  exit 1
fi

DMG_SIZE=$(du -h "$OUTPUT_DMG" | awk '{print $1}')
echo "[+] DMG created successfully: $OUTPUT_DMG ($DMG_SIZE)"
