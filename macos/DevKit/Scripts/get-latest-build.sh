#!/bin/bash
set -euo pipefail

R2_PUBLIC_URL="${R2_PUBLIC_URL:-${CLOUDFLARE_R2_PUBLIC_BASE_URL:-https://openbridge-release.afk.surf}}"
R2_PUBLIC_URL="${R2_PUBLIC_URL%/}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

get_build() {
  local env="$1"
  local url="${R2_PUBLIC_URL}/${env}/appcast.xml"
  local file="$TEMP_DIR/${env}.xml"

  for _ in 1 2; do
    local status
    status=$(curl -sSL -w "%{http_code}" "$url" -o "$file" 2> /dev/null || true)
    if [[ "$status" == "200" ]]; then
      local build=$(awk -F'[<>]' '/<sparkle:version>/{print $3; exit}' "$file")
      [[ "$build" =~ ^[0-9]+$ ]] && {
        echo "$build"
        return 0
      }
    elif [[ "$status" == "404" ]]; then
      echo "[i] no existing $env appcast at $url; using 0" >&2
      echo "0"
      return 0
    fi
    sleep 1
  done
  echo "[-] failed to read $env appcast at $url" >&2
  return 1
}

BUILD_STAGING=$(get_build "staging") || exit 1
BUILD_PROD=$(get_build "production") || exit 1

LATEST=$([[ "$BUILD_PROD" -gt "$BUILD_STAGING" ]] && echo "$BUILD_PROD" || echo "$BUILD_STAGING")
echo "[i] latest: staging=$BUILD_STAGING prod=$BUILD_PROD -> $LATEST" >&2
echo "$LATEST"
