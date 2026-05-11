#!/bin/zsh

set -euo pipefail

export CURRENT_DIR=$(pwd)

export KEYCHAIN_DB=${KEYCHAIN_DB:-""}
export KEYCHAIN_PASSWORD=${KEYCHAIN_PASSWORD:-""}
source ./publish-config-keychain.sh

if [[ -z "${CODE_SIGNING_IDENTITY:-}" || -z "${CODE_SIGNING_TEAM:-}" || -z "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
  echo "[-] required profile variables are not set, can not continue."
  exit 1
fi

export CLOUDFLARE_R2_ACCOUNT_ID=${CLOUDFLARE_R2_ACCOUNT_ID:-""}
export CLOUDFLARE_R2_BUCKET=${CLOUDFLARE_R2_BUCKET:-""}
export CLOUDFLARE_R2_ACCESS_KEY_ID=${CLOUDFLARE_R2_ACCESS_KEY_ID:-""}
export CLOUDFLARE_R2_SECRET_ACCESS_KEY=${CLOUDFLARE_R2_SECRET_ACCESS_KEY:-""}
