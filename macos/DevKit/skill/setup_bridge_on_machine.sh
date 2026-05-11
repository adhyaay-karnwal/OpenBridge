#!/usr/bin/env bash
set -euo pipefail

DEFAULT_COMPLETE_ONBOARDING=1
DEFAULT_TCCUTIL_VERSION=1.5.1

usage() {
  cat <<'USAGE'
Usage:
  setup_bridge_on_machine.sh [options]

Options:
  --repo <owner/name>                GitHub repo slug (default: AFK-surf/openbridge)
  --branch <branch>                  Branch to fetch/build (default: main)
  --repo-dir <path>                  Clone/update directory on the machine (default: ~/openbridge)
  --build-configuration <name>       Xcode build configuration (default: UnsignedDebug)
  --node-version <version>           Portable Node.js version to bootstrap when node is missing (default: 22.16.0)
  --swiftformat-version <version>    SwiftFormat version to pin during the build (default: 0.60.1)
  --complete-onboarding              Mark onboarding as completed before launch (default)
  --no-complete-onboarding           Leave onboarding state unchanged
  --tccutil-version <version>        jacobsalmela/tccutil version to download for machine-side TCC seeding (default: 1.5.1)
  --skip-open                        Build but do not launch OpenBridge.app
  --dry-run                          Print commands without executing them
  --help                             Show this message

Auth for private repo clone:
  1. Preferred: gh auth login on the machine, then this script can use gh repo clone.
  2. Alternative: export CUEBOARD_GH_TOKEN with repo read access before running.
  3. Alternative: export CUEBOARD_REPO_URL to a clone URL the machine can access.

Environment overrides:
  BRIDGE_COMPLETE_ONBOARDING=0|1
  TCC_TARGET_USER
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

run_in_shell() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ $*"
  else
    bash -lc "$*"
  fi
}

normalize_bool() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) echo 1 ;;
    0|false|FALSE|no|NO|off|OFF) echo 0 ;;
    *) die "expected boolean value, got: $1" ;;
  esac
}

REPO_SLUG="AFK-surf/openbridge"
BRANCH="main"
REPO_DIR="$HOME/openbridge"
BUILD_CONFIGURATION="UnsignedDebug"
NODE_VERSION="22.16.0"
SWIFTFORMAT_VERSION="${SWIFTFORMAT_VERSION:-0.60.1}"
COMPLETE_ONBOARDING="$(normalize_bool "${BRIDGE_COMPLETE_ONBOARDING:-$DEFAULT_COMPLETE_ONBOARDING}")"
TCCUTIL_VERSION="${TCCUTIL_VERSION:-$DEFAULT_TCCUTIL_VERSION}"
TCCUTIL_URL="${TCCUTIL_URL:-https://raw.githubusercontent.com/jacobsalmela/tccutil/v${TCCUTIL_VERSION}/tccutil.py}"
TCCUTIL_PATH="${TCCUTIL_PATH:-$HOME/.local/share/openbridge-toolchain/tccutil/v${TCCUTIL_VERSION}/tccutil.py}"
TCC_TARGET_USER="${TCC_TARGET_USER:-${USER:-admin}}"
SKIP_OPEN=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_SLUG="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --build-configuration)
      BUILD_CONFIGURATION="${2:-}"
      shift 2
      ;;
    --node-version)
      NODE_VERSION="${2:-}"
      shift 2
      ;;
    --swiftformat-version)
      SWIFTFORMAT_VERSION="${2:-}"
      shift 2
      ;;
    --complete-onboarding)
      COMPLETE_ONBOARDING=1
      shift
      ;;
    --no-complete-onboarding)
      COMPLETE_ONBOARDING=0
      shift
      ;;
    --tccutil-version)
      TCCUTIL_VERSION="${2:-}"
      TCCUTIL_URL="${TCCUTIL_URL:-https://raw.githubusercontent.com/jacobsalmela/tccutil/v${TCCUTIL_VERSION}/tccutil.py}"
      TCCUTIL_PATH="${TCCUTIL_PATH:-$HOME/.local/share/openbridge-toolchain/tccutil/v${TCCUTIL_VERSION}/tccutil.py}"
      shift 2
      ;;
    --skip-open)
      SKIP_OPEN=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

need_shell_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

have git || die "git is required"
have python3 || die "python3 is required"
have xcodebuild || die "xcodebuild is required"
need_shell_tool curl
need_shell_tool tar
need_shell_tool defaults
need_shell_tool chmod
need_shell_tool grep

bootstrap_node() {
  if have node && have corepack; then
    return
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    arm64) arch="arm64" ;;
    x86_64) arch="x64" ;;
    *) die "unsupported machine architecture for portable node bootstrap: $arch" ;;
  esac

  local node_root="$HOME/.local/share/openbridge-toolchain"
  local node_dir="$node_root/node-v${NODE_VERSION}-darwin-${arch}"
  local tarball="$node_root/node-v${NODE_VERSION}-darwin-${arch}.tar.gz"
  local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-${arch}.tar.gz"

  run_cmd mkdir -p "$node_root"

  if [[ ! -x "$node_dir/bin/node" ]]; then
    run_cmd rm -rf "$node_dir"
    run_cmd rm -f "$tarball"
    run_cmd curl -fsSL "$url" -o "$tarball"
    run_cmd tar -xzf "$tarball" -C "$node_root"
  fi

  export PATH="$node_dir/bin:$PATH"
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  have node || die "portable node bootstrap failed"
  have corepack || die "portable node bootstrap did not provide corepack"
}

ensure_python_module() {
  local module_name="$1"
  local package_name="${2:-$module_name}"

  if python3 - "$module_name" <<'PY' >/dev/null 2>&1
import importlib
import sys

importlib.import_module(sys.argv[1])
PY
  then
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ python3 -m pip install --user '$package_name'"
    return
  fi

  python3 -m pip install --user "$package_name"

  python3 - "$module_name" <<'PY' >/dev/null 2>&1 || die "python3 module '$module_name' is still missing after installation"
import importlib
import sys

importlib.import_module(sys.argv[1])
PY
}

ensure_jacobsalmela_tccutil() {
  ensure_python_module packaging packaging

  local tccutil_dir
  tccutil_dir="$(dirname "$TCCUTIL_PATH")"
  run_cmd mkdir -p "$tccutil_dir"

  local needs_download=0
  if [[ ! -f "$TCCUTIL_PATH" ]]; then
    needs_download=1
  elif ! grep -q "util_version = '$TCCUTIL_VERSION'" "$TCCUTIL_PATH"; then
    needs_download=1
  fi

  if [[ "$needs_download" == "1" ]]; then
    run_cmd curl -fsSL "$TCCUTIL_URL" -o "$TCCUTIL_PATH"
    run_cmd chmod 755 "$TCCUTIL_PATH"
  fi
}

infer_tcc_client_type() {
  if [[ "$1" == /* ]]; then
    echo 1
  else
    echo 0
  fi
}

grant_tcc_service() {
  local service="$1"
  local client="$2"

  run_cmd python3 "$TCCUTIL_PATH" --user "$TCC_TARGET_USER" --service "$service" --insert "$client"
  run_cmd python3 "$TCCUTIL_PATH" --user "$TCC_TARGET_USER" --service "$service" --enable "$client"
}

upsert_tcc_apple_events_permission() {
  local client="$1"
  local indirect_object="$2"
  local client_type
  client_type="$(infer_tcc_client_type "$client")"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ python3 [upsert AppleEvents permission service=kTCCServiceAppleEvents client=$client indirect_object=$indirect_object]"
    return
  fi

  TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  TCC_CLIENT="$client" \
  TCC_CLIENT_TYPE="$client_type" \
  TCC_INDIRECT_OBJECT="$indirect_object" \
  python3 - <<'PY'
import os
import sqlite3

db_path = os.environ["TCC_DB"]
client = os.environ["TCC_CLIENT"]
client_type = int(os.environ["TCC_CLIENT_TYPE"])
indirect_object = os.environ["TCC_INDIRECT_OBJECT"]

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute(
    """
    INSERT OR REPLACE INTO access (
        service,
        client,
        client_type,
        auth_value,
        auth_reason,
        auth_version,
        csreq,
        policy_id,
        indirect_object_identifier_type,
        indirect_object_identifier,
        indirect_object_code_identity,
        flags,
        last_modified,
        pid,
        pid_version,
        boot_uuid,
        last_reminded
    ) VALUES (
        'kTCCServiceAppleEvents',
        ?,
        ?,
        2,
        3,
        1,
        NULL,
        NULL,
        0,
        ?,
        NULL,
        0,
        CAST(strftime('%s','now') AS INTEGER),
        NULL,
        NULL,
        'UNUSED',
        CAST(strftime('%s','now') AS INTEGER)
    )
    """,
    (client, client_type, indirect_object),
)
conn.commit()
conn.close()
PY
}

seed_bridge_tcc_permissions() {
  local bundle_id="$1"

  ensure_jacobsalmela_tccutil

  local -a bridge_services=(
    kTCCServiceAccessibility
    kTCCServiceAddressBook
    kTCCServiceCalendar
    kTCCServiceCamera
    kTCCServiceDeveloperTool
    kTCCServiceListenEvent
    kTCCServiceMediaLibrary
    kTCCServiceMicrophone
    kTCCServicePhotos
    kTCCServicePostEvent
    kTCCServiceReminders
    kTCCServiceScreenCapture
    kTCCServiceSystemPolicyAllFiles
  )
  local -a automation_clients=(
    com.apple.Terminal
    /usr/bin/osascript
  )
  local -a automation_services=(
    kTCCServiceAccessibility
    kTCCServiceDeveloperTool
    kTCCServiceListenEvent
    kTCCServicePostEvent
    kTCCServiceScreenCapture
    kTCCServiceSystemPolicyAllFiles
  )

  for service in "${bridge_services[@]}"; do
    grant_tcc_service "$service" "$bundle_id"
  done

  for client in "${automation_clients[@]}"; do
    for service in "${automation_services[@]}"; do
      grant_tcc_service "$service" "$client"
    done
    upsert_tcc_apple_events_permission "$client" com.apple.systemevents
  done

  upsert_tcc_apple_events_permission "$bundle_id" com.apple.systemevents
}

guess_bundle_id() {
  case "$BUILD_CONFIGURATION" in
    UnsignedDebug) echo "app.openbridge.unsigneddebug" ;;
    Development|Debug) echo "app.yellowplus.openbridgetf" ;;
    Staging|Release) echo "app.afk.openbridge" ;;
    *) echo "app.openbridge.unsigneddebug" ;;
  esac
}

resolve_bundle_id() {
  if [[ "$DRY_RUN" == "1" ]]; then
    guess_bundle_id
    return
  fi

  local info_plist="$APP_PATH/Contents/Info.plist"
  [[ -f "$info_plist" ]] || die "missing built app Info.plist: $info_plist"

  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || guess_bundle_id
}

seed_bridge_runtime_state() {
  local bundle_id="$1"

  if [[ "$COMPLETE_ONBOARDING" == "1" ]]; then
    run_cmd defaults write "$bundle_id" hasCompletedOnboarding -bool true
  fi
}

bootstrap_node
run_cmd corepack enable

clone_or_update_repo() {
  local authenticated_repo_url=""
  if [[ -n "${CUEBOARD_REPO_URL:-}" ]]; then
    authenticated_repo_url="$CUEBOARD_REPO_URL"
  elif [[ -n "${CUEBOARD_GH_TOKEN:-}" ]]; then
    authenticated_repo_url="https://x-access-token:${CUEBOARD_GH_TOKEN}@github.com/${REPO_SLUG}.git"
  fi

  if [[ -d "$REPO_DIR/.git" ]]; then
    if [[ -n "$authenticated_repo_url" ]]; then
      run_cmd git -C "$REPO_DIR" remote set-url origin "$authenticated_repo_url"
    fi
    run_cmd git -C "$REPO_DIR" fetch origin "$BRANCH"
    run_cmd git -C "$REPO_DIR" checkout "$BRANCH"
    run_cmd git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
    return
  fi

  if have gh && gh auth status >/dev/null 2>&1; then
    run_cmd mkdir -p "$(dirname "$REPO_DIR")"
    run_cmd gh repo clone "$REPO_SLUG" "$REPO_DIR"
    if [[ -n "$authenticated_repo_url" ]]; then
      run_cmd git -C "$REPO_DIR" remote set-url origin "$authenticated_repo_url"
    fi
    run_cmd git -C "$REPO_DIR" fetch origin "$BRANCH"
    run_cmd git -C "$REPO_DIR" checkout "$BRANCH"
    run_cmd git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
    return
  fi

  if [[ -n "${CUEBOARD_GH_TOKEN:-}" ]]; then
    run_cmd mkdir -p "$(dirname "$REPO_DIR")"
    run_cmd git clone "$authenticated_repo_url" "$REPO_DIR"
    run_cmd git -C "$REPO_DIR" fetch origin "$BRANCH"
    run_cmd git -C "$REPO_DIR" checkout "$BRANCH"
    run_cmd git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
    return
  fi

  if [[ -n "${CUEBOARD_REPO_URL:-}" ]]; then
    run_cmd mkdir -p "$(dirname "$REPO_DIR")"
    run_cmd git clone "$authenticated_repo_url" "$REPO_DIR"
    run_cmd git -C "$REPO_DIR" fetch origin "$BRANCH"
    run_cmd git -C "$REPO_DIR" checkout "$BRANCH"
    run_cmd git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
    return
  fi

  die "cannot clone $REPO_SLUG on this machine: authenticate gh, or export CUEBOARD_GH_TOKEN, or export CUEBOARD_REPO_URL"
}

clone_or_update_repo

run_in_shell "export PATH='$PATH'; cd '$REPO_DIR/web' && corepack yarn install --immutable && corepack yarn build:embedded"
run_in_shell "cd '$REPO_DIR/macos' && SWIFTFORMAT_VERSION='$SWIFTFORMAT_VERSION' BUILD_CONFIGURATION='$BUILD_CONFIGURATION' bash DevKit/Scripts/workspace_build_debug.sh"

APP_PATH="$REPO_DIR/macos/.build/DerivedData/Build/Products/$BUILD_CONFIGURATION/OpenBridge.app"
APP_BUNDLE_ID="$(resolve_bundle_id)"
seed_bridge_runtime_state "$APP_BUNDLE_ID"
seed_bridge_tcc_permissions "$APP_BUNDLE_ID"

if [[ "$SKIP_OPEN" == "0" ]]; then
  run_in_shell "pkill -f '/OpenBridge.app/Contents/MacOS/OpenBridge' || true"
  run_cmd open -na "$APP_PATH"
fi

cat <<EOF2
OpenBridge machine setup complete.
repo_dir=$REPO_DIR
branch=$BRANCH
build_configuration=$BUILD_CONFIGURATION
app_path=$APP_PATH
app_bundle_id=$APP_BUNDLE_ID
onboarding_completed=$COMPLETE_ONBOARDING
tcc_seeded=yes
EOF2
