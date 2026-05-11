#!/bin/sh

set -e

RUNTIME_LABEL="sandbox-vm runtime"

if [ "${ENABLE_PREVIEWS:-}" = "YES" ] || echo "${CONFIGURATION:-}" | grep -qi "preview"; then
  echo "[-] Running in SwiftUI Preview mode. Skipping ${RUNTIME_LABEL} sync."
  exit 0
fi

cd "${SRCROOT}"

LOCAL_SANDBOXVM_FRAMEWORK="${SRCROOT}/../sandbox-vm/dist/SandboxVM.xcframework"
LOCAL_SANDBOXVM_KERNEL="${SRCROOT}/../sandbox-vm/resources/vm/kernel.bin"
LOCAL_SANDBOXVM_ROOTFS="${SRCROOT}/../sandbox-vm/resources/vm/rootfs.img"

if [ ! -d "$LOCAL_SANDBOXVM_FRAMEWORK" ]; then
  echo "[!] Missing local ${RUNTIME_LABEL} framework at $LOCAL_SANDBOXVM_FRAMEWORK"
  echo "    Build it with: make -C ../sandbox-vm framework"
  exit 1
fi

if [ ! -f "$LOCAL_SANDBOXVM_KERNEL" ]; then
  echo "[!] Missing local ${RUNTIME_LABEL} kernel at $LOCAL_SANDBOXVM_KERNEL"
  echo "    Build it with: make -C ../sandbox-vm vm"
  exit 1
fi

if [ ! -f "$LOCAL_SANDBOXVM_ROOTFS" ]; then
  echo "[!] Missing local ${RUNTIME_LABEL} rootfs at $LOCAL_SANDBOXVM_ROOTFS"
  echo "    Build it with: make -C ../sandbox-vm vm"
  exit 1
fi

rm -rf "./SandboxVM.xcframework"
ditto "$LOCAL_SANDBOXVM_FRAMEWORK" "./SandboxVM.xcframework"
mkdir -p "./OpenBridge/Resources"
cp "$LOCAL_SANDBOXVM_KERNEL" "./OpenBridge/Resources/kernel.bin"
cp "$LOCAL_SANDBOXVM_ROOTFS" "./OpenBridge/Resources/rootfs.img"

echo "Using local ${RUNTIME_LABEL} artifacts from ${SRCROOT}/../sandbox-vm"
