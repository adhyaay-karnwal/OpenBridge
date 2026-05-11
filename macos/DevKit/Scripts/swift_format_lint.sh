#!/bin/zsh

# Swift Code Style Enforcements

set -euo pipefail

ENABLE_STRICT_MODE=false

for arg in "$@"; do
  case "$arg" in
    --strict)
      ENABLE_STRICT_MODE=true
      ;;
  esac
done

# Auto-configure git hooks on first build (runs before any skip logic)
REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null || true)"
if [[ -n "$REPO_ROOT" ]] && [[ -d "$REPO_ROOT/.githooks" ]]; then
  CURRENT_HOOKS_PATH=$(git config core.hooksPath 2> /dev/null || true)
  if [[ "$CURRENT_HOOKS_PATH" != ".githooks" ]]; then
    git config core.hooksPath .githooks 2> /dev/null || true
    echo "[hooks] Auto-configured git pre-commit hook for Swift lint checks."
  fi
fi

# Skip in preview mode (SwiftUI Preview)
if [[ "${ENABLE_PREVIEWS:-}" == "YES" ]] || [[ "${CONFIGURATION:-}" == *"preview"* ]]; then
  echo "[-] Running in SwiftUI Preview mode. Skipping Swift code style checks."
  exit 0
fi

# Skip in Debug mode for faster incremental builds (CI/Release will still run)
# Use FORCE_LINT=1 to override, or run with --strict flag
if [[ "${CONFIGURATION:-}" == "Debug" ]] && [[ "${FORCE_LINT:-}" != "1" ]] && [[ ! " $* " =~ " --strict " ]]; then
  echo "[-] Skipping code style checks in Debug mode. Use FORCE_LINT=1 or --strict to override."
  exit 0
fi

# Skip build-phase auto-formatting on CI so xcodebuild doesn't mutate the checkout mid-build.
# Dedicated formatting workflows should continue to use --strict.
if [[ ("${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true") && "$ENABLE_STRICT_MODE" != true ]]; then
  echo "[-] Running in CI build mode. Skipping in-place Swift code style checks."
  exit 0
fi

ROOT_DIR=""
if [[ -n "${SRCROOT:-}" ]]; then
  ROOT_DIR="$SRCROOT"
else
  ROOT_DIR="$(dirname "$0")/../.."
fi
ROOT_DIR="$(realpath "$ROOT_DIR")"
cd "$ROOT_DIR"

source "$ROOT_DIR/DevKit/Scripts/shell-utils.sh"
ensure_path

SWIFT_VERSION="6.0"

# Cache directory for swiftformat and swiftlint
CACHE_DIR="$ROOT_DIR/.build/lint-cache"
mkdir -p "$CACHE_DIR"

echo "[+] Swift Code Style Enforcements"
echo "[+] Working directory: $ROOT_DIR"
echo "[+] Swift version: $SWIFT_VERSION"

if [[ "$ENABLE_STRICT_MODE" == true ]]; then
  ensure_swiftformat 1
else
  ensure_swiftformat
fi

if ! command -v swiftlint &> /dev/null; then
  echo "[+] Installing swiftlint via brew..."
  if command -v brew &> /dev/null; then
    brew install swiftlint || {
      echo "[-] Failed to install swiftlint"
      exit 1
    }
  else
    echo "[-] brew is not installed. Please install swiftlint manually."
    exit 1
  fi
fi

SWIFT_LINT_TARGETS=()
if [[ -n "${SWIFT_LINT_TARGETS_FILE:-}" ]]; then
  if [[ ! -f "$SWIFT_LINT_TARGETS_FILE" ]]; then
    echo "[-] Swift lint targets file not found: $SWIFT_LINT_TARGETS_FILE"
    exit 1
  fi

  while IFS= read -r target || [[ -n "$target" ]]; do
    [[ -z "$target" ]] && continue
    if [[ "$target" == /* ]]; then
      SWIFT_LINT_TARGETS+=("$target")
    else
      SWIFT_LINT_TARGETS+=("$ROOT_DIR/$target")
    fi
  done < "$SWIFT_LINT_TARGETS_FILE"

  if (( ${#SWIFT_LINT_TARGETS[@]} == 0 )); then
    echo "[+] No Swift lint targets selected. Skipping Swift code style checks."
    exit 0
  fi

  echo "[+] Swift lint targets:"
  for target in "${SWIFT_LINT_TARGETS[@]}"; do
    echo "    - ${target#$ROOT_DIR/}"
  done
fi

echo "[+] Running swiftformat (with cache)..."
APP_DIR="$ROOT_DIR/OpenBridge"
SWIFTFORMAT_CONFIG="$ROOT_DIR/.swiftformat"
SWIFTFORMAT_TARGETS=("$APP_DIR")
if (( ${#SWIFT_LINT_TARGETS[@]} > 0 )); then
  SWIFTFORMAT_TARGETS=("${SWIFT_LINT_TARGETS[@]}")
fi
SWIFTFORMAT_FLAGS=()
if [[ "$ENABLE_STRICT_MODE" == true ]]; then
  SWIFTFORMAT_FLAGS+=(--lint)
fi

swiftformat \
  --config "$SWIFTFORMAT_CONFIG" \
  --swiftversion "$SWIFT_VERSION" \
  --indent 4 \
  --cache "$CACHE_DIR/swiftformat.cache" \
  --exclude "DevKit,DerivedData,.build,Pods,*.xcodeproj,*.xcworkspace" \
  "${SWIFTFORMAT_FLAGS[@]}" \
  "${SWIFTFORMAT_TARGETS[@]}"

echo "[+] Running swiftlint (with cache)..."
SWIFTLINT_CONFIG="$ROOT_DIR/.swiftlint.yml"
SWIFTLINT_FLAGS=(lint --config "$SWIFTLINT_CONFIG" --cache-path "$CACHE_DIR/swiftlint")
if [[ "$ENABLE_STRICT_MODE" != true ]]; then
  # Use --lenient to treat errors as warnings (non-blocking)
  SWIFTLINT_FLAGS+=(--lenient)
fi
swiftlint "${SWIFTLINT_FLAGS[@]}" "${SWIFT_LINT_TARGETS[@]}"

echo "[+] Swift code style checks passed"
