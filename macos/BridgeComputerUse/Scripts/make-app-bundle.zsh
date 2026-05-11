#!/usr/bin/env zsh
# Build ComputerUseDaemon and assemble a signed ComputerUse.app bundle.
# Stable designated requirement comes from the bundle id + self-signed
# "ComputerUseNext dev" identity (see Scripts/bootstrap-signing.zsh), so TCC
# grants survive rebuilds as long as the bundle id doesn't change.

set -euo pipefail

CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/.build/apps}"
APP_NAME="ComputerUse"
EXECUTABLE_NAME="ComputerUseDaemon"
BUNDLE_ID="${BUNDLE_ID:-com.computerusenext.ComputerUse}"
PLIST_SRC="${ROOT}/Resources/${APP_NAME}-Info.plist"

APP="${BUILD_DIR}/${APP_NAME}.app"
MACOS="${APP}/Contents/MacOS"
RES="${APP}/Contents/Resources"

echo ">> building ${EXECUTABLE_NAME} (${CONFIG})"
swift build --package-path "${ROOT}" --product "${EXECUTABLE_NAME}" --configuration "${CONFIG}"

BIN="$(swift build --package-path "${ROOT}" --product "${EXECUTABLE_NAME}" --configuration "${CONFIG}" --show-bin-path)/${EXECUTABLE_NAME}"
if [[ ! -x "${BIN}" ]]; then
    echo "error: built binary not found at ${BIN}" >&2
    exit 1
fi

echo ">> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${MACOS}" "${RES}"

cp "${BIN}" "${MACOS}/${EXECUTABLE_NAME}"
chmod +x "${MACOS}/${EXECUTABLE_NAME}"

cp "${PLIST_SRC}" "${APP}/Contents/Info.plist"
# PkgInfo is technically optional but Finder/LaunchServices still read it.
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Copy SwiftPM-produced resource bundles into Contents/Resources so that
# Bundle.module continues to resolve inside the .app. SwiftPM emits them
# as `<Package>_<Target>.bundle` next to the product binary.
for resource_bundle in "$(dirname "${BIN}")"/*_*.bundle(N); do
    [[ -d "${resource_bundle}" ]] || continue
    cp -R "${resource_bundle}" "${RES}/"
done

# Prefer a local self-signed identity (see Scripts/bootstrap-signing.zsh) so
# the designated requirement is stable across rebuilds and TCC grants stick.
# Fall back to ad-hoc for contributors who haven't bootstrapped yet.
SIGN_IDENTITY="${COMPUTERUSE_SIGN_IDENTITY:-ComputerUseNext dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "\"${SIGN_IDENTITY}\""; then
    echo ">> codesigning with identity \"${SIGN_IDENTITY}\" (identifier=${BUNDLE_ID})"
    codesign --force --sign "${SIGN_IDENTITY}" \
        --identifier "${BUNDLE_ID}" \
        --options runtime \
        --timestamp=none \
        "${APP}"
else
    echo ">> codesigning ad-hoc — run ./Scripts/bootstrap-signing.zsh for TCC stability"
    codesign --force --sign - \
        --identifier "${BUNDLE_ID}" \
        --options runtime \
        --timestamp=none \
        "${APP}"
fi

echo "${APP}"
