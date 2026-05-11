#!/bin/sh

# Common shell utilities for DevKit scripts.
# Intended to be sourced by both bash and zsh scripts.

set -e

ensure_path() {
  # Self-hosted runners may run with a minimal PATH.
  # Keep existing PATH but ensure common locations are present.
  case ":${PATH-}:" in
    *":/usr/bin:"*) ;;
    *) PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH-}" ;;
  esac

  case ":${PATH-}:" in
    *":/opt/homebrew/bin:"*) ;;
    *) PATH="/opt/homebrew/bin:${PATH-}" ;;
  esac

  case ":${PATH-}:" in
    *":/usr/local/bin:"*) ;;
    *) PATH="/usr/local/bin:${PATH-}" ;;
  esac

  export PATH
}

log_info() { echo "[i] $*"; }
log_step() { echo "[*] $*"; }
log_ok() { echo "[+] $*"; }
log_err() { echo "[-] $*"; }

_die() {
  log_err "$1"
  exit "${2:-1}"
}

die() {
  _die "$@"
}

require_cmd() {
  local _cmd="$1"
  command -v "$_cmd" > /dev/null 2>&1 || die "$_cmd required"
}

require_file() {
  local _path="$1"
  local _msg="$2"
  [ -f "$_path" ] || die "$_msg"
}

# Indirect env-var access that works in both bash and zsh.
# Usage: env_get VAR_NAME
env_get() {
  local _name="$1"
  # shellcheck disable=SC2163,SC2086
  eval "printf '%s' \"\${$_name-}\""
}

require_env() {
  local _name="$1"
  local _val
  _val="$(env_get "$_name")"
  [ -n "$_val" ] || die "missing: $_name"
}

ensure_swiftformat() {
  local _force_update="${1:-0}"
  local _pinned_version="${SWIFTFORMAT_VERSION:-}"
  local _should_update="0"
  local _download_url
  local _tool_root
  local _tool_dir
  local _archive_path
  local _tmp_dir
  local _binary_path
  local _version

  ensure_path

  if [ -n "$_pinned_version" ]; then
    require_cmd curl
    require_cmd unzip

    _tool_root="${HOME}/.cache/openbridge-tools/swiftformat"
    _tool_dir="${_tool_root}/${_pinned_version}"
    _archive_path="${_tool_dir}/swiftformat.zip"
    _binary_path="${_tool_dir}/swiftformat"

    if [ ! -x "$_binary_path" ]; then
      mkdir -p "$_tool_root"
      _tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/swiftformat.${_pinned_version}.XXXXXX")"
      _download_url="https://github.com/nicklockwood/SwiftFormat/releases/download/${_pinned_version}/swiftformat.zip"

      log_step "Downloading pinned swiftformat ${_pinned_version}..."
      curl --fail --location --silent --show-error "$_download_url" -o "${_tmp_dir}/swiftformat.zip"
      unzip -q -o "${_tmp_dir}/swiftformat.zip" -d "$_tmp_dir"
      chmod +x "${_tmp_dir}/swiftformat"

      rm -rf "$_tool_dir"
      mkdir -p "$_tool_root"
      mv "$_tmp_dir" "$_tool_dir"
    fi

    PATH="${_tool_dir}:${PATH-}"
    export PATH

    command -v swiftformat > /dev/null 2>&1 || die "swiftformat install failed"
    _version="$(swiftformat --version 2> /dev/null || echo unknown)"
    log_ok "swiftformat ready (pinned): ${_version}"
    return
  fi

  require_cmd brew

  if [ "$_force_update" = "1" ]; then
    _should_update="1"
  elif [ "${SWIFTFORMAT_AUTO_UPDATE:-0}" = "1" ]; then
    _should_update="1"
  elif [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ]; then
    _should_update="1"
  fi

  if [ "${SWIFTFORMAT_BREW_REFRESHED:-0}" = "1" ] && [ "$_force_update" != "1" ]; then
    _should_update="0"
  fi

  if [ "$_should_update" = "1" ]; then
    log_step "Refreshing Homebrew metadata for swiftformat..."
    brew update
  fi

  if brew list --formula swiftformat > /dev/null 2>&1; then
    if [ "$_should_update" = "1" ]; then
      brew upgrade swiftformat || brew reinstall swiftformat
      export SWIFTFORMAT_BREW_REFRESHED=1
    fi
  else
    log_step "Installing swiftformat via Homebrew..."
    brew install swiftformat
    if [ "$_should_update" = "1" ]; then
      export SWIFTFORMAT_BREW_REFRESHED=1
    fi
  fi

  command -v swiftformat > /dev/null 2>&1 || die "swiftformat install failed"
  _version="$(swiftformat --version 2> /dev/null || echo unknown)"
  log_ok "swiftformat ready: ${_version}"
}
