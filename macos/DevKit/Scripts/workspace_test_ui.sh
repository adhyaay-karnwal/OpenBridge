#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
WORKSPACE="OpenBridge.xcworkspace"
SCHEME="OpenBridge"
BUNDLE_ID="${BUNDLE_ID:-app.openbridge.unsigneddebug}"
RESULT_BUNDLE="$MACOS_ROOT/.build/TestResults/${SCHEME}UITests.xcresult"
SCREENSHOT_DIR="$MACOS_ROOT/.build/screenshots"
XCODEBUILD_LOG="$MACOS_ROOT/xcodebuild.log"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-UnsignedDebug}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "$MACOS_ROOT"

echo "[*] downloading sandbox-vm"
SRCROOT="$(pwd)" bash "$SCRIPT_DIR/sync-sandbox-vm.sh"

rm -rf "$RESULT_BUNDLE" "$SCREENSHOT_DIR"
mkdir -p "$(dirname "$RESULT_BUNDLE")"

XC_BUILD_CMD=(
  xcodebuild test
  -workspace "$WORKSPACE"
  -scheme "$SCHEME"
  -configuration "$BUILD_CONFIGURATION"
  -destination 'platform=macOS'
  -skipPackagePluginValidation
  -skipMacroValidation
  -resultBundlePath "$RESULT_BUNDLE"
  -only-testing:${SCHEME}UITests
  ENABLE_TESTABILITY=YES
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
  PROVISIONING_PROFILE_SPECIFIER=""
)

if [[ "$CODE_SIGNING_ALLOWED" == "NO" ]]; then
  XC_BUILD_CMD+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGN_IDENTITY=""
  )
else
  XC_BUILD_CMD+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    DEVELOPMENT_TEAM=""
  )
fi

echo "[*] running UI tests..."
set +e
if command -v xcbeautify >/dev/null 2>&1; then
  "${XC_BUILD_CMD[@]}" 2>&1 | tee "$XCODEBUILD_LOG" | xcbeautify --is-ci --disable-logging --disable-colored-output
  TEST_STATUS=${pipestatus[1]}
else
  "${XC_BUILD_CMD[@]}" 2>&1 | tee "$XCODEBUILD_LOG"
  TEST_STATUS=${pipestatus[1]}
fi
set -e

if [[ "$TEST_STATUS" -ne 0 ]]; then
  if grep -q "System authentication is running" "$XCODEBUILD_LOG"; then
    echo "[!] UI test runner could not initialize because macOS LocalAuthentication is already presenting a system authentication prompt."
    echo "[!] Dismiss the active authentication prompt or restart the GUI session, then rerun this script."
  fi
  exit "$TEST_STATUS"
fi

echo "[*] exporting screenshots to $SCREENSHOT_DIR..."
mkdir -p "$SCREENSHOT_DIR"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$SCREENSHOT_DIR"

echo "[*] done"
