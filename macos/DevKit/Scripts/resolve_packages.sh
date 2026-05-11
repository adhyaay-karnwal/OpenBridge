#!/bin/zsh

set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -workspace OpenBridge.xcworkspace \
  -scheme OpenBridge \
  -resolvePackageDependencies \
  -skipPackagePluginValidation \
  -skipMacroValidation
