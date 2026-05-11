#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

source ./shell-utils.sh
ensure_path

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-app>"
  exit 1
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
  echo "[-] app path does not exist: $APP_PATH"
  exit 1
fi

if [[ ! "$APP_PATH" =~ \.app$ ]]; then
  echo "[-] provided path is not a .app bundle: $APP_PATH"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
APP_BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2> /dev/null || echo "unknown")

echo "[*] preparing to notarize: $APP_NAME"
echo "[i] bundle id: $APP_BUNDLE_ID"

if [[ -z "${CODE_SIGNING_IDENTITY:-}" ]]; then
  echo "[-] CODE_SIGNING_IDENTITY is not set"
  exit 1
fi

if [[ -z "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
  echo "[-] NOTARIZE_KEYCHAIN_PROFILE is not set"
  exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "/bin/rm -rf '$TEMP_DIR'" EXIT

DMG_BASENAME="${APP_NAME%.app}"
DMG_PATH="$TEMP_DIR/${DMG_BASENAME}.dmg"

echo "[*] creating styled dmg"
if ! ./create-styled-dmg.sh "$APP_PATH" "$DMG_PATH"; then
  echo "[-] failed to create dmg"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "[-] dmg file not found after creation"
  exit 1
fi

DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo "[i] dmg size: $DMG_SIZE"

echo "[*] signing dmg"
if ! codesign --sign "$CODE_SIGNING_IDENTITY" --timestamp "$DMG_PATH"; then
  echo "[-] failed to sign dmg"
  exit 1
fi
echo "[+] dmg signed successfully"

echo "[*] submitting to notary service"
echo "[i] using keychain profile: $NOTARIZE_KEYCHAIN_PROFILE"

SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" \
  --wait \
  2>&1)

echo "$SUBMIT_OUTPUT"

if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
  echo "[+] notarization successful"

  echo "[*] stapling notarization ticket to dmg"
  if ! xcrun stapler staple "$DMG_PATH"; then
    echo "[-] failed to staple notarization ticket to dmg"
    exit 1
  fi

  echo "[+] dmg stapled successfully"

  echo "[*] verifying dmg staple"
  if ! xcrun stapler validate "$DMG_PATH"; then
    echo "[-] dmg staple validation failed"
    exit 1
  fi

  echo "[+] dmg staple validated successfully"

  echo "[*] stapling notarization ticket to app"
  if ! xcrun stapler staple "$APP_PATH"; then
    echo "[-] failed to staple notarization ticket to app"
    exit 1
  fi

  echo "[+] app stapled successfully"

  echo "[*] verifying staple"
  if ! xcrun stapler validate "$APP_PATH"; then
    echo "[-] staple validation failed"
    exit 1
  fi

  echo "[+] app staple validated successfully"

  if [[ -n "${NOTARIZE_DMG_OUTPUT:-}" ]]; then
    DEST_PATH="$NOTARIZE_DMG_OUTPUT"
    mkdir -p "$(dirname "$DEST_PATH")"
    if cp "$DMG_PATH" "$DEST_PATH"; then
      echo "[i] copied notarized dmg to: $DEST_PATH"
    else
      echo "[!] warning: failed to copy notarized dmg to $DEST_PATH"
    fi
  fi

  exit 0
elif echo "$SUBMIT_OUTPUT" | grep -q "status: Invalid"; then
  echo "[-] notarization failed with status: Invalid"

  SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -n 1 | awk '{print $2}')
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "[*] fetching notarization log for submission: $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" \
      --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE"
  fi

  exit 1
else
  echo "[-] notarization failed or timed out"
  exit 1
fi
