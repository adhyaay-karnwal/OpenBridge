#!/bin/zsh

set -euo pipefail

if [[ "${ENABLE_PREVIEWS:-}" == "YES" ]] || [[ "${CONFIGURATION:-}" == *"preview"* ]]; then
  echo "[-] running in SwiftUI Preview mode; skipping OpenBridge Computer Use embed"
  exit 0
fi

if [[ -z "${SRCROOT:-}" ]]; then
  echo "[!] SRCROOT is required"
  exit 1
fi

if [[ -z "${CODESIGNING_FOLDER_PATH:-}" ]]; then
  echo "[!] CODESIGNING_FOLDER_PATH is required"
  exit 1
fi

helper_config="release"
if [[ "${CONFIGURATION:-}" == *"Debug"* ]] || [[ "${CONFIGURATION:-}" == *"debug"* ]]; then
  helper_config="debug"
fi

helper_archs="${HELPER_ARCHS:-}"
if [[ -z "$helper_archs" ]]; then
  if [[ "$helper_config" == "release" ]]; then
    helper_archs="${ARCHS:-$(uname -m)}"
  else
    helper_archs="${NATIVE_ARCH_ACTUAL:-$(uname -m)}"
  fi
fi

sign_identity="-"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY:-}" != "-" ]]; then
    sign_identity="${EXPANDED_CODE_SIGN_IDENTITY}"
  elif [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY:-}" != "-" && "${CODE_SIGN_IDENTITY:-}" != "Sign to Run Locally" ]]; then
    sign_identity="${CODE_SIGN_IDENTITY}"
  elif [[ -n "${CODE_SIGNING_IDENTITY:-}" && "${CODE_SIGNING_IDENTITY:-}" != "-" && "${CODE_SIGNING_IDENTITY:-}" != "Sign to Run Locally" ]]; then
    sign_identity="${CODE_SIGNING_IDENTITY}"
  fi
fi

sign_team="${DEVELOPMENT_TEAM:-${CODE_SIGNING_TEAM:-}}"
if [[ "$sign_identity" == "-" ]]; then
  sign_team=""
fi

helper_output="${DERIVED_FILE_DIR:-${SRCROOT}/.build}/BridgeComputerUse"

echo "[*] building and embedding OpenBridge Computer Use before OpenBridge code signing"
echo "[*] helper configuration: $helper_config"
echo "[*] helper architectures: $helper_archs"
if [[ "$sign_identity" == "-" ]]; then
  echo "[*] helper signing: ad-hoc"
else
  echo "[*] helper signing identity: $sign_identity"
fi

CONFIG="$helper_config" \
HELPER_ARCHS="$helper_archs" \
DAEMON_OUTPUT_DIR="$helper_output" \
BRIDGE_APP_PATH="$CODESIGNING_FOLDER_PATH" \
CODE_SIGNING_IDENTITY="$sign_identity" \
CODE_SIGNING_TEAM="$sign_team" \
  /bin/zsh "$SRCROOT/DevKit/Scripts/build_bridge_computer_use.sh"
