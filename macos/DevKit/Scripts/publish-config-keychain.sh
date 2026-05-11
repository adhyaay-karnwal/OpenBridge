#!/bin/zsh

set -euo pipefail

# 此脚本用于提取签名配置所需的信息并解锁 Keychain

if [[ -z "${KEYCHAIN_DB:-}" || -z "${KEYCHAIN_PASSWORD:-}" ]]; then
  echo "[-] KEYCHAIN_DB or KEYCHAIN_PASSWORD is not set"
  exit 1
fi

# security 指令必须使用绝对路径
KEYCHAIN_DB=$(realpath "$KEYCHAIN_DB")

CODE_SIGNING_CONTENTS=$(security find-identity -v -p codesigning "$KEYCHAIN_DB")
DEVELOPER_ID_LINE=$(echo "$CODE_SIGNING_CONTENTS" | grep "Developer ID Application" | head -n 1)
CODE_SIGNING_IDENTITY=$(echo "$DEVELOPER_ID_LINE" | sed 's/.*"\(.*\)".*/\1/')
CODE_SIGNING_IDENTITY_HASH=$(echo "$DEVELOPER_ID_LINE" | awk '{print $2}')
CODE_SIGNING_TEAM=$(echo "$DEVELOPER_ID_LINE" | sed 's/.*(\(.*\)).*/\1/')

if [[ -z "$CODE_SIGNING_IDENTITY" ]]; then
  echo "[-] cannot find Developer ID Application identity in keychain"
  exit 1
fi

if [[ -z "$CODE_SIGNING_IDENTITY_HASH" ]]; then
  echo "[-] cannot extract identity hash from Developer ID Application identity"
  exit 1
fi

if [[ -z "$CODE_SIGNING_TEAM" ]]; then
  echo "[-] cannot find Team ID from Developer ID Application identity"
  exit 1
fi

echo "[i] found identity: $CODE_SIGNING_IDENTITY"
echo "[i] found identity hash: $CODE_SIGNING_IDENTITY_HASH"
echo "[i] found team: $CODE_SIGNING_TEAM"

CODE_SIGNING_IDENTITY=${CODE_SIGNING_IDENTITY_HASH}
echo "[i] set CODE_SIGNING_IDENTITY to identity hash: $CODE_SIGNING_IDENTITY"

NOTARIZE_KEYCHAIN_PROFILE=$(
  security dump-keychain -r "$KEYCHAIN_DB" |
    strings |
    grep "com.apple.gke.notary.tool.saved-creds" |
    head -n 1 |
    awk -F. '{print $NF}' |
    tr -d '"'
)
echo "[i] found notary profile: $NOTARIZE_KEYCHAIN_PROFILE"

export CODE_SIGNING_IDENTITY
export CODE_SIGNING_IDENTITY_HASH
export CODE_SIGNING_TEAM
export NOTARIZE_KEYCHAIN_PROFILE

echo "[*] unlocking keychain: $KEYCHAIN_DB"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_DB"

CURRENT_KEYCHAINS=$(security list-keychains -d user | sed 's/"//g' | tr '\n' ' ')
security list-keychains -d user -s "$KEYCHAIN_DB" $CURRENT_KEYCHAINS
security set-keychain-settings -t 3600 -l "$KEYCHAIN_DB"

echo "[i] keychain unlocked and configured"
echo "[i] current default keychain: $(security default-keychain | sed 's/"//g')"
