#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
install_dir="${TCCUTIL_INSTALL_DIR:-/usr/local/bin}"
target_path="${install_dir}/tccutil"

mkdir -p "$install_dir"
swiftc "${script_dir}/tccutil.swift" -o "$target_path"

print -- "tccutil: $target_path"
"$target_path" --version
