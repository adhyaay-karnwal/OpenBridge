#!/bin/bash
# project-env.sh - Populate and validate project environment
# Source this file: source ./project-env.sh

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Paths
VERSION_XCCONFIG="$PROJECT_ROOT/OpenBridge/Configuration/Version.xcconfig"
KEYCHAIN_DIR="$SCRIPT_DIR/../Keychain"

# Validation functions
validate_version() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || {
    echo "[-] invalid version: '$v'"
    return 1
  }
}

validate_build() {
  local b="$1"
  [[ "$b" =~ ^[0-9]+$ ]] || {
    echo "[-] invalid build number: '$b'"
    return 1
  }
}

# Parse xcconfig value (strips comments and whitespace)
parse_xcconfig() {
  local key="$1" file="$2"
  grep "^$key" "$file" 2> /dev/null | sed 's/.*= *//' | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' \n\r'
}

# Sanitize version (extract valid semver)
sanitize_version() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?' || echo "1.0.0"
}

# Sanitize build number (extract integer)
sanitize_build_number() {
  echo "$1" | sed 's/[[:space:]]*\/\/.*//' | sed 's/[[:space:]]*\/\*.*//' | tr -d ' ' |
    grep -oE '^[0-9]+' || echo "1"
}

# Load and validate project info
load_project_info() {
  [[ -f "$VERSION_XCCONFIG" ]] || {
    echo "[-] Version.xcconfig not found: $VERSION_XCCONFIG"
    return 1
  }

  local raw_version raw_build
  raw_version=$(parse_xcconfig "MARKETING_VERSION" "$VERSION_XCCONFIG")
  raw_build=$(parse_xcconfig "CURRENT_PROJECT_VERSION" "$VERSION_XCCONFIG")

  MARKETING_VERSION=$(sanitize_version "$raw_version")
  PROJECT_VERSION=$(sanitize_build_number "$raw_build")

  validate_version "$MARKETING_VERSION" || return 1
  validate_build "$PROJECT_VERSION" || return 1

  export MARKETING_VERSION PROJECT_VERSION
  echo "[+] project: v$MARKETING_VERSION ($PROJECT_VERSION)"
}

# Load version from built app Info.plist
load_app_version() {
  local plist="$1"
  [[ -f "$plist" ]] || {
    echo "[-] Info.plist not found: $plist"
    return 1
  }

  local raw_version raw_build
  raw_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2> /dev/null || echo "1.0.0")
  raw_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2> /dev/null || echo "1")

  APP_VERSION=$(sanitize_version "$raw_version")
  APP_BUILD=$(sanitize_build_number "$raw_build")

  validate_version "$APP_VERSION" || return 1
  validate_build "$APP_BUILD" || return 1

  export APP_VERSION APP_BUILD
  echo "[+] app: v$APP_VERSION ($APP_BUILD)"
}

# Validate all required paths exist
validate_paths() {
  local missing=0
  for path in "$@"; do
    [[ -e "$path" ]] || {
      echo "[-] missing: $path"
      missing=1
    }
  done
  return $missing
}

# Export common paths
export SCRIPT_DIR PROJECT_ROOT VERSION_XCCONFIG KEYCHAIN_DIR
