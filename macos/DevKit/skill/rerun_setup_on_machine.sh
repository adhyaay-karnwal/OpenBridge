#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  rerun_setup_on_machine.sh --run-id <run-id> [--branch <branch>] [--machine-repo-dir <path>] [--dry-run] [-- <extra setup args>]

Description:
  Look up an already-running mini-machine by run id and rerun setup_bridge_on_machine.sh on that
  machine so OpenBridge is rebuilt and reopened in place.

Examples:
  macos/DevKit/skill/rerun_setup_on_machine.sh \
    --run-id 123456789 \
    --branch my-branch

Notes:
  - Push your branch first (for example with publish_branch_for_machine.sh).
  - Extra args after `--` are forwarded to setup_bridge_on_machine.sh on the machine.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_ID=""
BRANCH=""
MACHINE_REPO_DIR='~/openbridge'
DRY_RUN=0
FORWARDED_SETUP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --machine-repo-dir|--repo-dir)
      MACHINE_REPO_DIR="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      FORWARDED_SETUP_ARGS=("$@")
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$RUN_ID" ]] || die "pass --run-id <run-id>"

if [[ -z "$BRANCH" ]]; then
  current_branch="$(git -C "$SCRIPT_DIR/../../.." symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  BRANCH="$current_branch"
fi
[[ -n "$BRANCH" ]] || die "pass --branch <branch>"

connection_json="$("$SCRIPT_DIR/machine.sh" get "$RUN_ID" --json)"
eval "$(
  CONNECTION_JSON="$connection_json" python3 - <<'PY'
import json
import os
import shlex

data = json.loads(os.environ["CONNECTION_JSON"])
ssh_parts = shlex.split(data["ssh_cmd"])

ssh_port = "22"
for index, part in enumerate(ssh_parts):
    if part == "-p" and index + 1 < len(ssh_parts):
        ssh_port = ssh_parts[index + 1]
        break

ssh_target = ssh_parts[-1]
ssh_user, ssh_host = ssh_target.split("@", 1)

for key, value in {
    "SSH_PORT": ssh_port,
    "SSH_USER": ssh_user,
    "SSH_HOST": ssh_host,
    "SSH_PRIVATE_KEY": data["ssh_private_key"],
}.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"

key_file="$(mktemp "${TMPDIR:-/tmp}/openbridge-machine-key.XXXXXX")"
cleanup() {
  rm -f "$key_file"
}
trap cleanup EXIT

if [[ "$DRY_RUN" == "1" ]]; then
  echo "+ cat > '$key_file' <<'EOF'"
  echo "+ [redacted ssh private key from machine.sh get --json]"
  echo "+ EOF"
  echo "+ chmod 600 '$key_file'"
else
  printf '%s\n' "$SSH_PRIVATE_KEY" > "$key_file"
  chmod 600 "$key_file"
fi

gh_token=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_token="$(gh auth token 2>/dev/null || true)"
fi

remote_command=(
  ssh
  -i "$key_file"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -p "$SSH_PORT"
  "$SSH_USER@$SSH_HOST"
)

setup_args=(--branch "$BRANCH" --repo-dir "$MACHINE_REPO_DIR")
if ((${#FORWARDED_SETUP_ARGS[@]} > 0)); then
  setup_args=("${FORWARDED_SETUP_ARGS[@]}" "${setup_args[@]}")
fi

if [[ "$DRY_RUN" == "1" ]]; then
  if [[ -n "$gh_token" ]]; then
    echo "+ ${remote_command[*]} env CUEBOARD_GH_TOKEN=[from gh auth token] bash -s -- ${setup_args[*]} < '$SCRIPT_DIR/setup_bridge_on_machine.sh'"
  else
    echo "+ ${remote_command[*]} bash -s -- ${setup_args[*]} < '$SCRIPT_DIR/setup_bridge_on_machine.sh'"
  fi
  exit 0
fi

start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

if [[ -n "$gh_token" ]]; then
  "${remote_command[@]}" env "CUEBOARD_GH_TOKEN=$gh_token" bash -s -- "${setup_args[@]}" < "$SCRIPT_DIR/setup_bridge_on_machine.sh"
else
  "${remote_command[@]}" bash -s -- "${setup_args[@]}" < "$SCRIPT_DIR/setup_bridge_on_machine.sh"
fi

end_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

python3 - <<PY
start = float("$start_epoch")
end = float("$end_epoch")
print(f"Machine setup rerun completed for run $RUN_ID on branch $BRANCH in {end - start:.2f}s.")
PY
