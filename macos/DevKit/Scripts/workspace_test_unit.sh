#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
WORKSPACE="OpenBridge.xcworkspace"
SCHEME="OpenBridge"
RESULT_BUNDLE="$MACOS_ROOT/.build/TestResults/${SCHEME}UnitTests.xcresult"
XCODEBUILD_LOG="$MACOS_ROOT/xcodebuild.log"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-UnsignedDebug}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "$MACOS_ROOT"

echo "[*] downloading sandbox-vm"
SRCROOT="$(pwd)" bash "$SCRIPT_DIR/sync-sandbox-vm.sh"

rm -rf "$RESULT_BUNDLE"
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
  -only-testing:OpenBridgeUnitTests
  ENABLE_TESTABILITY=YES
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

echo "[*] running unit tests..."
if command -v xcbeautify >/dev/null 2>&1; then
  "${XC_BUILD_CMD[@]}" 2>&1 | tee "$XCODEBUILD_LOG" | xcbeautify --is-ci --disable-logging --disable-colored-output
else
  "${XC_BUILD_CMD[@]}" 2>&1 | tee "$XCODEBUILD_LOG"
fi

echo "[*] done"
