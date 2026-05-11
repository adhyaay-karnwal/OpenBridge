#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MACOS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
source "$SCRIPT_DIR/version-utils.sh"
source "$SCRIPT_DIR/shell-utils.sh"
ensure_path

RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT:-production}"
[[ "$RELEASE_ENVIRONMENT" == "staging" || "$RELEASE_ENVIRONMENT" == "production" ]] || die "invalid environment: $RELEASE_ENVIRONMENT"

DMG_PATH="${1:-}"
[[ -n "$DMG_PATH" && -f "$DMG_PATH" ]] || die "usage: $0 <dmg-path>"

PRIVATE_KEY_PATH="$SCRIPT_DIR/../Keychain/SparkleKeys/private-key.txt"
require_file "$PRIVATE_KEY_PATH" "Sparkle key not found"

sanitize_env_var() {
  local name="$1"
  local required="${2:-1}"
  local value

  value="$(env_get "$name" | tr -d '\r\n')"
  if [[ -z "$value" ]]; then
    [[ "$required" == "0" ]] && return 0
    die "missing: $name"
  fi

  export "$name=$value"
}

for var in CLOUDFLARE_R2_BUCKET CLOUDFLARE_R2_ACCOUNT_ID CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY; do
  sanitize_env_var "$var"
done

for var in CLOUDFLARE_R2_PUBLIC_BASE_URL CLOUDFLARE_R2_REGION; do
  sanitize_env_var "$var" 0
done

for var in CLOUDFLARE_R2_BUCKET CLOUDFLARE_R2_ACCOUNT_ID CLOUDFLARE_R2_ACCESS_KEY_ID CLOUDFLARE_R2_SECRET_ACCESS_KEY; do
  require_env "$var"
done

R2_ENDPOINT="https://${CLOUDFLARE_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
PUBLIC_BASE_URL="${CLOUDFLARE_R2_PUBLIC_BASE_URL:-$R2_ENDPOINT/$CLOUDFLARE_R2_BUCKET}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}/$RELEASE_ENVIRONMENT"

export AWS_ACCESS_KEY_ID="$CLOUDFLARE_R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$CLOUDFLARE_R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${CLOUDFLARE_R2_REGION:-auto}"
export AWS_PAGER=""

if ! command -v aws > /dev/null 2>&1; then
  if command -v brew > /dev/null 2>&1; then
    brew install awscli || die "aws CLI required"
  else
    die "aws CLI required"
  fi
fi

require_cmd shasum
require_cmd hdiutil
require_cmd xcrun

MOUNT_POINT=""
TEMP_DIR=""

cleanup() {
  [[ -n "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" -quiet 2> /dev/null || true
  [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] && /bin/rm -rf "$MOUNT_POINT"
  [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && /bin/rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

extract_version_from_dmg() {
  log_step "extracting version from DMG..."
  MOUNT_POINT=$(mktemp -d)

  hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet || die "mount failed"

  local app_in_dmg
  app_in_dmg=$(find "$MOUNT_POINT" -name "*.app" -maxdepth 1 -type d | head -n 1)
  [[ -n "$app_in_dmg" ]] || die ".app not found in DMG"

  local info_plist
  info_plist="$app_in_dmg/Contents/Info.plist"

  local raw_version raw_build
  raw_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist" 2> /dev/null || echo "1.0.0")
  raw_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist" 2> /dev/null || echo "1")

  VERSION=$(sanitize_version "$raw_version")
  BUILD_VERSION=$(sanitize_build_number "$raw_build")
  log_info "version: $VERSION ($BUILD_VERSION)"

  hdiutil detach "$MOUNT_POINT" -quiet 2> /dev/null || true
}

validate_notarization() {
  xcrun stapler validate "$DMG_PATH" > /dev/null 2>&1 || die "notarization staple invalid"
}

prepare_archive_dir() {
  TIMESTAMP=$(date +%s)
  SHA256SUM=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
  FINAL_FILENAME="${VERSION}-${TIMESTAMP}-${SHA256SUM}.dmg"
  log_info "filename: $FINAL_FILENAME"

  TEMP_DIR=$(mktemp -d)
  ARCHIVES_DIR="$TEMP_DIR/sparkle/archives"
  mkdir -p "$ARCHIVES_DIR"
  cp "$DMG_PATH" "$ARCHIVES_DIR/$FINAL_FILENAME"
}

find_generate_appcast() {
  local candidate
  for candidate in \
    "$MACOS_ROOT/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$MACOS_ROOT/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$MACOS_ROOT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$MACOS_ROOT/.build/Build/Products/Release/Sparkle.framework/Versions/B/bin/generate_appcast"; do
    [[ -x "$candidate" ]] && {
      echo "$candidate"
      return 0
    }
  done

  if command -v generate_appcast > /dev/null 2>&1; then
    echo "$(command -v generate_appcast)"
    return 0
  fi

  local found
  found=$(find "$MACOS_ROOT/.build" -path "*sparkle*bin/generate_appcast" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$found" ]] && {
    echo "$found"
    return 0
  }

  found=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*sparkle*bin/generate_appcast" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$found" ]] && {
    echo "$found"
    return 0
  }

  found=$(find "$MACOS_ROOT" -name "generate_appcast" -type f -perm -111 -print -quit 2> /dev/null || echo "")
  [[ -n "$found" ]] && {
    echo "$found"
    return 0
  }

  log_err "generate_appcast not found"
  log_info "checked candidates:"
  log_info "- $MACOS_ROOT/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  log_info "- $MACOS_ROOT/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  log_info "- $MACOS_ROOT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  log_info "- $MACOS_ROOT/.build/Build/Products/Release/Sparkle.framework/Versions/B/bin/generate_appcast"
  return 1
}

generate_appcast() {
  local gen_appcast="$1"
  log_info "using: $gen_appcast"
  log_step "generating appcast..."

  pushd "$TEMP_DIR/sparkle" > /dev/null
  "$gen_appcast" --download-url-prefix "${PUBLIC_BASE_URL}/" --ed-key-file "$PRIVATE_KEY_PATH" "$ARCHIVES_DIR"
  popd > /dev/null

  [[ -f "$ARCHIVES_DIR/appcast.xml" ]] || die "appcast.xml not created"
}

verify_r2_object() {
  local key="$1"
  local size

  size=$(aws --endpoint-url "$R2_ENDPOINT" s3api head-object \
    --bucket "$CLOUDFLARE_R2_BUCKET" \
    --key "$key" \
    --query ContentLength \
    --output text) || die "R2 object verification failed: s3://${CLOUDFLARE_R2_BUCKET}/${key}"

  [[ -n "$size" && "$size" != "None" ]] || die "R2 object has no content length: s3://${CLOUDFLARE_R2_BUCKET}/${key}"
  log_ok "verified R2 object: s3://${CLOUDFLARE_R2_BUCKET}/${key} (${size} bytes)"
}

upload_r2_object() {
  local source_path="$1"
  local key="$2"
  local content_type="$3"

  log_info "uploading: s3://${CLOUDFLARE_R2_BUCKET}/${key}"
  aws --endpoint-url "$R2_ENDPOINT" s3 cp "$source_path" "s3://${CLOUDFLARE_R2_BUCKET}/${key}" --content-type "$content_type"
  verify_r2_object "$key"
}

upload_to_r2() {
  log_step "uploading to R2 ($RELEASE_ENVIRONMENT)..."
  local dmg_key="${RELEASE_ENVIRONMENT}/${FINAL_FILENAME}"
  upload_r2_object "$ARCHIVES_DIR/$FINAL_FILENAME" "$dmg_key" "application/x-apple-diskimage"

  # staging: upload appcast.xml directly (immediate availability)
  # production: upload as appcast_pending.xml (requires signoff to activate)
  local appcast_remote_name="appcast.xml"
  if [[ "$RELEASE_ENVIRONMENT" == "production" ]]; then
    appcast_remote_name="appcast_pending.xml"
  fi
  local appcast_key="${RELEASE_ENVIRONMENT}/${appcast_remote_name}"
  upload_r2_object "$ARCHIVES_DIR/appcast.xml" "$appcast_key" "application/xml"

  echo "$FINAL_FILENAME" > "$TEMP_DIR/latest.txt"
  local latest_key="${RELEASE_ENVIRONMENT}/latest.txt"
  upload_r2_object "$TEMP_DIR/latest.txt" "$latest_key" "text/plain"

  log_ok "uploaded: $FINAL_FILENAME"
}

main() {
  extract_version_from_dmg
  validate_notarization
  prepare_archive_dir

  local gen_appcast
  gen_appcast=$(find_generate_appcast) || exit 1
  generate_appcast "$gen_appcast"

  upload_to_r2
}

main "$@"
