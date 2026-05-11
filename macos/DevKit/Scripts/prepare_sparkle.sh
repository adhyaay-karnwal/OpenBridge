#!/bin/zsh

set -euo pipefail

# Skip in preview mode (SwiftUI Preview)
if [[ "${ENABLE_PREVIEWS:-}" == "YES" ]] || [[ "${CONFIGURATION:-}" == *"preview"* ]]; then
  echo "[-] Running in SwiftUI Preview mode. Skipping Sparkle preparation."
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" > /dev/null 2>&1 && pwd)
ROOT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." > /dev/null 2>&1 && pwd)}"

if [[ "${CODE_SIGNING_ALLOWED:-}" != "YES" ]]; then
  echo "[-] CODE_SIGNING_ALLOWED is not set to YES. Exiting."
  exit 0
fi

APP_PATH="$CODESIGNING_FOLDER_PATH"
FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"
echo "[+] Signing Sparkle framework in app at: $FRAMEWORK_PATH"
echo "[+] Using code signing identity: $EXPANDED_CODE_SIGN_IDENTITY"

codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" -o runtime \
  "$FRAMEWORK_PATH/Versions/B/XPCServices/Installer.xpc"

codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" -o runtime --preserve-metadata=entitlements \
  "$FRAMEWORK_PATH/Versions/B/XPCServices/Downloader.xpc"

codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" -o runtime \
  "$FRAMEWORK_PATH/Versions/B/Autoupdate"
codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" -o runtime \
  "$FRAMEWORK_PATH/Versions/B/Updater.app"

codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" -o runtime \
  "$FRAMEWORK_PATH"

codesign --verify --deep --strict --verbose=2 "$FRAMEWORK_PATH"

echo "[+] Successfully signed Sparkle framework"
