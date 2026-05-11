#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
source "$SCRIPT_DIR/version-utils.sh"

RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT:-production}"
VERSION_XCCONFIG="$PROJECT_ROOT/OpenBridge/Configuration/Version.xcconfig"

echo "[*] auto-incrementing build number ($RELEASE_ENVIRONMENT)..."

LATEST_BUILD=$("$SCRIPT_DIR/get-latest-build.sh")
CURRENT_BUILD=$(read_project_version "$VERSION_XCCONFIG")

[[ "$CURRENT_BUILD" -gt "$LATEST_BUILD" ]] 2> /dev/null && LATEST_BUILD=$CURRENT_BUILD

NEW_BUILD=$((LATEST_BUILD + 1))
echo "[i] $CURRENT_BUILD -> $NEW_BUILD (latest published: $LATEST_BUILD)"

sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" "$VERSION_XCCONFIG"

UPDATED=$(read_project_version "$VERSION_XCCONFIG")
[[ "$UPDATED" == "$NEW_BUILD" ]] || {
  echo "[-] update failed"
  exit 1
}
echo "[+] build number updated to $NEW_BUILD"
