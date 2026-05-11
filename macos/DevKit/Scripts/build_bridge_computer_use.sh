#!/bin/zsh
# Build the BridgeComputerUseDaemon SwiftPM product and assemble a signed
# OpenBridge Computer Use.app bundle that gets embedded in OpenBridge.app/Contents/Helpers/.
#
# Inputs (env):
#   CONFIG                  release (default) | debug
#   DAEMON_OUTPUT_DIR       where OpenBridge Computer Use.app is written
#                           (default: $PROJECT_ROOT/.build/apps)
#   HELPER_ARCHS            optional space-separated SwiftPM architectures
#                           (e.g. "arm64 x86_64"); unset builds host arch
#   CODE_SIGNING_IDENTITY   codesign identity (e.g. "Developer ID Application")
#                           when unset, we fall back to ad-hoc signing
#   CODE_SIGNING_TEAM       development team; required when using Developer ID
#
# The helper ships with bundle id `app.afk.openbridge.BridgeComputerUse`. That
# id must stay stable across releases so macOS TCC grants (Accessibility +
# Screen Recording) survive upgrades.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

while [[ ! -e OpenBridge.xcworkspace ]] && [[ ! -f OpenBridge.xcodeproj ]] && [[ "$(pwd)" != "/" ]]; do
  cd ..
done

if [[ ! -e OpenBridge.xcworkspace ]] && [[ ! -f OpenBridge.xcodeproj ]]; then
  echo "[!] could not locate project root"
  exit 1
fi

PROJECT_ROOT=$(pwd)
PACKAGE_ROOT="$PROJECT_ROOT/BridgeComputerUse"
APP_NAME="BridgeComputerUse"
APP_BUNDLE_NAME="OpenBridge Computer Use"
EXECUTABLE_NAME="BridgeComputerUseDaemon"
BUNDLE_ID="app.afk.openbridge.BridgeComputerUse"
PLIST_SRC="$PACKAGE_ROOT/Resources/${APP_NAME}-Info.plist"
FALLBACK_ICON_SRC="$PROJECT_ROOT/OpenBridge/ResourcesBundles/AppIcons/AppIconDev.icon/Assets/logo.png"

CONFIG="${CONFIG:-release}"
DAEMON_OUTPUT_DIR="${DAEMON_OUTPUT_DIR:-$PROJECT_ROOT/.build/apps}"

APP="$DAEMON_OUTPUT_DIR/${APP_BUNDLE_NAME}.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

SWIFT_ARCH_ARGS=()
if [[ -n "${HELPER_ARCHS:-}" ]]; then
  for arch in ${(z)HELPER_ARCHS}; do
    [[ -n "$arch" ]] || continue
    [[ "$arch" == "arm64e" ]] && continue
    SWIFT_ARCH_ARGS+=(--arch "$arch")
  done
fi

SWIFT_BUILD_ENV=(
  env
  -i
  "PATH=${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
  "HOME=${HOME:-}"
)
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  SWIFT_BUILD_ENV+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi
if [[ -n "${SDKROOT:-}" ]]; then
  SWIFT_BUILD_ENV+=("SDKROOT=$SDKROOT")
fi
if [[ -n "${TMPDIR:-}" ]]; then
  SWIFT_BUILD_ENV+=("TMPDIR=$TMPDIR")
fi
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SWIFT_BUILD_ENV+=("SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
fi

echo "[*] building $EXECUTABLE_NAME ($CONFIG)"
if (( ${#SWIFT_ARCH_ARGS[@]} > 0 )); then
  echo "[*] helper architectures: ${HELPER_ARCHS}"
fi
SWIFT_BUILD_ARGS=(
  build
  --package-path "$PACKAGE_ROOT" \
  --product "$EXECUTABLE_NAME" \
  --configuration "$CONFIG"
)
if (( ${#SWIFT_ARCH_ARGS[@]} > 0 )); then
  SWIFT_BUILD_ARGS+=("${SWIFT_ARCH_ARGS[@]}")
fi

"${SWIFT_BUILD_ENV[@]}" swift "${SWIFT_BUILD_ARGS[@]}"

BIN_DIR="$("${SWIFT_BUILD_ENV[@]}" swift "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/$EXECUTABLE_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "[!] built binary not found at $BIN"
  exit 1
fi

echo "[*] assembling $APP"
rm -rf "$APP" "$DAEMON_OUTPUT_DIR/${APP_NAME}.app"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/$EXECUTABLE_NAME"
chmod +x "$MACOS/$EXECUTABLE_NAME"

cp "$PLIST_SRC" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICON_SRC="${BRIDGE_COMPUTER_USE_ICON_SOURCE:-}"
if [[ -z "$ICON_SRC" && -n "${BRIDGE_APP_PATH:-}" ]]; then
  for bridge_icon in "$BRIDGE_APP_PATH/Contents/Resources"/AppIcon*.icns; do
    [[ -f "$bridge_icon" ]] || continue
    ICON_SRC="$bridge_icon"
    break
  done
fi
if [[ -z "$ICON_SRC" && -f "$FALLBACK_ICON_SRC" ]]; then
  ICON_SRC="$FALLBACK_ICON_SRC"
fi
if [[ -n "$ICON_SRC" && -f "$ICON_SRC" ]]; then
  case "${ICON_SRC:e:l}" in
    icns)
      cp "$ICON_SRC" "$RES/${APP_NAME}.icns"
      ;;
    png)
      iconset="$RES/${APP_NAME}.iconset"
      mkdir -p "$iconset"
      sips -z 16 16 "$ICON_SRC" --out "$iconset/icon_16x16.png" >/dev/null
      sips -z 32 32 "$ICON_SRC" --out "$iconset/icon_16x16@2x.png" >/dev/null
      sips -z 32 32 "$ICON_SRC" --out "$iconset/icon_32x32.png" >/dev/null
      sips -z 64 64 "$ICON_SRC" --out "$iconset/icon_32x32@2x.png" >/dev/null
      sips -z 128 128 "$ICON_SRC" --out "$iconset/icon_128x128.png" >/dev/null
      sips -z 256 256 "$ICON_SRC" --out "$iconset/icon_128x128@2x.png" >/dev/null
      sips -z 256 256 "$ICON_SRC" --out "$iconset/icon_256x256.png" >/dev/null
      sips -z 512 512 "$ICON_SRC" --out "$iconset/icon_256x256@2x.png" >/dev/null
      sips -z 512 512 "$ICON_SRC" --out "$iconset/icon_512x512.png" >/dev/null
      sips -z 1024 1024 "$ICON_SRC" --out "$iconset/icon_512x512@2x.png" >/dev/null
      iconutil -c icns "$iconset" -o "$RES/${APP_NAME}.icns"
      rm -rf "$iconset"
      ;;
    *)
      echo "[!] unsupported icon source format: $ICON_SRC"
      ;;
  esac
fi

# SwiftPM emits any processed resource bundles next to the binary; copy them
# into Contents/Resources so `Bundle.module` still resolves inside the .app.
for resource_bundle in "$BIN_DIR"/*_*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$RES/"
done

if [[ -n "${CODE_SIGNING_IDENTITY:-}" ]]; then
  echo "[*] codesigning with identity \"$CODE_SIGNING_IDENTITY\" (identifier=$BUNDLE_ID)"
  CODESIGN_ARGS=(
    --force
    --sign "$CODE_SIGNING_IDENTITY"
    --identifier "$BUNDLE_ID"
    --options runtime
  )
  if [[ "$CODE_SIGNING_IDENTITY" == "-" ]]; then
    CODESIGN_ARGS+=(--timestamp=none)
  else
    CODESIGN_ARGS+=(--timestamp)
  fi
  if [[ -n "${CODE_SIGNING_TEAM:-}" ]]; then
    CODESIGN_ARGS+=(--prefix "$CODE_SIGNING_TEAM.")
  fi
  codesign "${CODESIGN_ARGS[@]}" "$APP"
else
  echo "[*] codesigning ad-hoc (set CODE_SIGNING_IDENTITY for distribution builds)"
  codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    --options runtime \
    --timestamp=none \
    "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "[*] ${APP_BUNDLE_NAME}.app at $APP"

# If BRIDGE_APP_PATH is provided, drop the helper into OpenBridge.app/Contents/Helpers/.
# Debug builds and local iterations use this to co-locate the helper without
# relying on the archive pipeline.
if [[ -n "${BRIDGE_APP_PATH:-}" ]]; then
  if [[ ! -d "$BRIDGE_APP_PATH" ]]; then
    echo "[!] BRIDGE_APP_PATH not a directory: $BRIDGE_APP_PATH"
    exit 1
  fi
  HELPERS="$BRIDGE_APP_PATH/Contents/Helpers"
  mkdir -p "$HELPERS"
  rm -rf "$HELPERS/${APP_BUNDLE_NAME}.app" "$HELPERS/${APP_NAME}.app"
  cp -R "$APP" "$HELPERS/${APP_BUNDLE_NAME}.app"
  echo "[*] embedded helper into $HELPERS/${APP_BUNDLE_NAME}.app"
fi
