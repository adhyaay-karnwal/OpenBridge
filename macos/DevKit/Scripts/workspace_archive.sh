#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

while [[ ! -e OpenBridge.xcworkspace ]] && [[ ! -f OpenBridge.xcodeproj ]] && [[ "$(pwd)" != "/" ]]; do
  cd ..
done

if [[ ! -e OpenBridge.xcworkspace ]] && [[ ! -f OpenBridge.xcodeproj ]]; then
  echo "[!] could not locate project root or workspace"
  exit 1
fi

PROJECT_ROOT=$(pwd)
WORKSPACE="OpenBridge.xcworkspace"
SCHEME="OpenBridge"
APP_DIR="OpenBridge"
BUNDLE_ID="app.afk.openbridge"
BUILD_DIR="$PROJECT_ROOT/.build"
ARCHIVE_PATH="$BUILD_DIR/${SCHEME}.xcarchive"
DERIVED_DATA="$BUILD_DIR/DerivedData"
LICENSE_OUTPUT="$PROJECT_ROOT/${APP_DIR}/Resources/OSSLicenses.txt"
LICENSE_CLONE_ROOT="$BUILD_DIR/license.scanner/dependencies"
XCODEBUILD_LOG="$PROJECT_ROOT/xcodebuild.log"

echo "[*] downloading sandbox-vm"
SRCROOT="$(pwd)" bash "$SCRIPT_DIR/sync-sandbox-vm.sh"

mkdir -p "$BUILD_DIR"
mkdir -p "$DERIVED_DATA"

function cleanup_build_artifacts() {
  echo "[*] cleaning previous archive artifacts"
  rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA"
  rm -f "$XCODEBUILD_LOG"
  mkdir -p "$BUILD_DIR"
  mkdir -p "$DERIVED_DATA"
}

function run_xcodebuild() {
  xcodebuild "$@" 2>&1 | tee "$XCODEBUILD_LOG" | xcbeautify --is-ci --disable-logging --disable-colored-output
}

# Read environment variable
RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT:-production}"
echo "[*] release environment: $RELEASE_ENVIRONMENT"

# Set configuration and Sparkle Feed URL based on environment
if [[ "$RELEASE_ENVIRONMENT" == "staging" ]]; then
  CONFIGURATION="Staging"
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://openbridge-release.afk.surf/staging/appcast.xml}"
  echo "[*] building for STAGING environment (configuration: Staging)"
else
  CONFIGURATION="Release"
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://openbridge-release.afk.surf/production/appcast.xml}"
  echo "[*] building for PRODUCTION environment (configuration: Release)"
fi

if [[ -n "${CODE_SIGNING_IDENTITY:-}" && -n "${CODE_SIGNING_TEAM:-}" ]]; then
  echo "[*] archiving $SCHEME with code signing"
  echo "[i] identity: $CODE_SIGNING_IDENTITY"
  echo "[i] team: $CODE_SIGNING_TEAM"
  CODE_SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$CODE_SIGNING_IDENTITY"
    DEVELOPMENT_TEAM="$CODE_SIGNING_TEAM"
  )
elif [[ "${CODE_SIGNING_ALLOWED:-}" == "NO" ]]; then
  echo "[*] archiving $SCHEME without code signing (explicitly disabled)"
  CODE_SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGN_IDENTITY=""
  )
else
  echo "[*] archiving $SCHEME without code signing"
  CODE_SIGN_ARGS=()
fi

cleanup_build_artifacts

run_xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  archive \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
  "${CODE_SIGN_ARGS[@]}"

echo "[*] archive generated at $ARCHIVE_PATH"
