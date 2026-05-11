#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

source ./shell-utils.sh
ensure_path

source ./project-env.sh

export RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT:-production}"
echo "=========================================="
echo "Publishing: $RELEASE_ENVIRONMENT"
echo "=========================================="

step_validate() {
  echo "[*] validating environment..."
  load_project_info || exit 1

  export KEYCHAIN_DB
  KEYCHAIN_DB=$(realpath ../Keychain/AFK-Developer-ID-Keychain.keychain)
  [[ -f "$KEYCHAIN_DB" ]] || {
    echo "[-] keychain not found: $KEYCHAIN_DB"
    exit 1
  }

  export KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD_AFK:-}"
  [[ -n "$KEYCHAIN_PASSWORD" ]] || {
    echo "[-] KEYCHAIN_PASSWORD_AFK not set"
    exit 1
  }

  source ./publish-config.sh
}

step_increment_build() {
  ./auto-increment-build.sh
}

step_archive() {
  echo "[*] archiving..."
  export CODE_SIGNING_IDENTITY CODE_SIGNING_TEAM
  ./workspace_archive.sh
}

step_notarize() {
  ARCHIVE_ROOT=$(realpath ../../.build/OpenBridge.xcarchive)
  APP_PATH=$(find "$ARCHIVE_ROOT" -name "*.app" -type d | head -n 1)
  [[ -n "$APP_PATH" ]] || {
    echo "[-] .app not found in archive"
    exit 1
  }

  echo "[*] notarizing..."
  export NOTARIZE_KEYCHAIN_PROFILE
  export NOTARIZE_DMG_OUTPUT="$ARCHIVE_ROOT/../OpenBridge.dmg"
  ./publish-submit-notary.sh "$APP_PATH"

  DMG_PATH="$ARCHIVE_ROOT/../OpenBridge.dmg"
  [[ -f "$DMG_PATH" ]] || {
    echo "[-] DMG not found"
    exit 1
  }
  xcrun stapler validate "$DMG_PATH" > /dev/null 2>&1 || {
    echo "[-] notarization validation failed"
    exit 1
  }
}

step_upload() {
  echo "[*] uploading to R2..."
  export CLOUDFLARE_R2_ACCOUNT_ID CLOUDFLARE_R2_BUCKET CLOUDFLARE_R2_TOKEN
  ./publish-submit-r2.sh "$DMG_PATH"
}

step_package_artifact() {
  ./common_package.sh
}

main() {
  step_validate
  step_increment_build
  step_archive
  step_notarize
  step_upload
  step_package_artifact
  echo "[+] done"
}

main "$@"
