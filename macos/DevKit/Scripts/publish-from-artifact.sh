#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

source ./shell-utils.sh
ensure_path

export KEYCHAIN_DB=$(realpath $(pwd)/../Keychain/AFK-Developer-ID-Keychain.keychain)
export KEYCHAIN_PASSWORD="$KEYCHAIN_PASSWORD_AFK"

source ./publish-config.sh

REPO_ROOT=$(cd ../../.. && pwd)
ARTIFACT_DMG="$REPO_ROOT/artifacts/OpenBridge.dmg"

if [[ ! -f "$ARTIFACT_DMG" ]]; then
  echo "[-] artifact not found at: $ARTIFACT_DMG"
  exit 1
fi

echo "[*] mounting DMG from artifact..."
TEMP_DIR=$(mktemp -d)
MOUNT_POINT="$TEMP_DIR/mount"
mkdir -p "$MOUNT_POINT"
trap "hdiutil detach '$MOUNT_POINT' -quiet 2>/dev/null || true; /bin/rm -rf '$TEMP_DIR'" EXIT

if ! hdiutil attach "$ARTIFACT_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet; then
  echo "[-] failed to mount DMG"
  exit 1
fi

APP_IN_DMG=$(find "$MOUNT_POINT" -name "*.app" -maxdepth 1 -type d | head -n 1)
if [[ -z "$APP_IN_DMG" ]]; then
  echo "[-] could not find .app in DMG"
  exit 1
fi

echo "[i] found .app at: $APP_IN_DMG"

echo "[*] copying app from DMG..."
APP_PATH="$TEMP_DIR/OpenBridge.app"
cp -R "$APP_IN_DMG" "$APP_PATH"

hdiutil detach "$MOUNT_POINT" -quiet 2> /dev/null || true

echo "[*] code signing app..."
export CODE_SIGNING_IDENTITY
export CODE_SIGNING_TEAM
codesign --force --deep --sign "$CODE_SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements "$APP_PATH"

echo "[*] submitting for notarization..."
export NOTARIZE_KEYCHAIN_PROFILE
export NOTARIZE_DMG_OUTPUT="$TEMP_DIR/OpenBridge-notarized.dmg"
./publish-submit-notary.sh "$APP_PATH"

echo "[+] notarization completed successfully"

DMG_PATH="$TEMP_DIR/OpenBridge-notarized.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
  echo "[-] notarized DMG not found"
  exit 1
fi

echo "[*] uploading to Cloudflare R2..."
export CLOUDFLARE_R2_ACCOUNT_ID
export CLOUDFLARE_R2_BUCKET
export CLOUDFLARE_R2_TOKEN
./publish-submit-r2.sh "$DMG_PATH"

echo "[+] publish process completed successfully"
echo "[i] done $(basename "$0")"
