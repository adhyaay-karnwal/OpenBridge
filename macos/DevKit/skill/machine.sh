#!/usr/bin/env bash
set -euo pipefail

MINIMACHINE_REPO="${MINIMACHINE_REPO:-AFK-surf/mini-machine}"
MINIMACHINE_WORKFLOW="${MINIMACHINE_WORKFLOW:-mini-machine.yml}"
MINIMACHINE_ARTIFACT="${MINIMACHINE_ARTIFACT:-connection-info}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  machine.sh new <request-info> [--json]
  machine.sh new --request-info <request-info> [--json]
  machine.sh list [--json]
  machine.sh get <run-id> [--json]
  machine.sh stop <run-id>

Description:
  Manage mini-machine macOS sessions for OpenBridge OpenBridge debugging without
  requiring a separate minimachine install.

Environment:
  MINIMACHINE_REPO      GitHub repo that hosts the workflow (default: AFK-surf/mini-machine)
  MINIMACHINE_WORKFLOW  Workflow filename (default: mini-machine.yml)
  MINIMACHINE_ARTIFACT  Connection artifact name (default: connection-info)

Request info:
  Every new mini-machine must include a short reason. It appears in the
  mini-machine workflow run title and connection artifact so active machines
  can be identified.
USAGE
}

have_json_flag() {
  [[ "${1:-}" == "--json" ]]
}

parse_connection_info() {
  local info_file="$1"
  local run_id="$2"
  python3 - "$info_file" "$run_id" <<'PY'
import json
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
run_id = sys.argv[2]

fields = {}
for prefix, key in [
    ("Requested by:", "requested_by"),
    ("Request info:", "request_info"),
    ("SSH:", "ssh_cmd"),
    ("VNC:", "vnc_url"),
    ("noVNC:", "novnc_url"),
    ("VNC user:", "vnc_user"),
    ("VNC/System pass:", "vnc_password"),
]:
    value = ""
    for line in text.splitlines():
        if line.startswith(prefix):
            value = line.split(prefix, 1)[1].strip()
            break
    fields[key] = value

host = ""
port = ""
match = re.match(r"vnc://([^:]+):(\d+)", fields["vnc_url"])
if match:
    host, port = match.group(1), match.group(2)

key_match = re.search(r"--- SSH Private Key ---\n(.*?)\n--- End SSH Private Key ---", text, re.S)
fields.update({
    "run_id": run_id,
    "vnc_host": host,
    "vnc_port": port,
    "ssh_private_key": key_match.group(1).strip() if key_match else "",
})

print(json.dumps(fields, indent=2))
PY
}

print_connection_info() {
  local run_id="$1"
  local json_output="$2"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" RETURN

  gh run download "$run_id" -R "$MINIMACHINE_REPO" -n "$MINIMACHINE_ARTIFACT" -D "$tmpdir" >/dev/null 2>&1 \
    || die "failed to download connection info for run $run_id"

  local info_file="$tmpdir/connection-info.txt"
  [[ -f "$info_file" ]] || die "connection-info.txt not found for run $run_id"

  if [[ "$json_output" == "1" ]]; then
    parse_connection_info "$info_file" "$run_id"
  else
    cat "$info_file"
  fi
}

latest_active_run_id() {
  local triggered_epoch="$1"
  local payload
  payload="$(gh run list -R "$MINIMACHINE_REPO" -w "$MINIMACHINE_WORKFLOW" --limit 20 --json databaseId,status,createdAt,url 2>/dev/null)"
  GH_JSON="$payload" python3 - "$triggered_epoch" <<'PY'
import json
import os
import sys
from datetime import datetime

triggered_epoch = int(sys.argv[1])
runs = json.loads(os.environ.get("GH_JSON", "[]") or "[]")
active = [r for r in runs if r.get("status") in {"queued", "in_progress"}]
if not active:
    print("")
    raise SystemExit

def to_epoch(value: str) -> int:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return int(dt.timestamp())

recent = [r for r in active if to_epoch(r["createdAt"]) >= triggered_epoch - 120]
source = recent or active
source.sort(key=lambda item: (to_epoch(item["createdAt"]), item["databaseId"]), reverse=True)
print(source[0]["databaseId"])
PY
}

artifact_ready() {
  local run_id="$1"
  local payload
  payload="$(gh api "repos/${MINIMACHINE_REPO}/actions/runs/${run_id}/artifacts" 2>/dev/null)"
  GH_JSON="$payload" python3 - "$MINIMACHINE_ARTIFACT" <<'PY'
import json
import os
import sys

artifact_name = sys.argv[1]
payload = json.loads(os.environ.get("GH_JSON", "{}") or "{}")
ready = any(item.get("name") == artifact_name for item in payload.get("artifacts", []))
print("1" if ready else "0")
PY
}

render_active_runs() {
  local json_output="$1"
  local payload
  payload="$(gh run list -R "$MINIMACHINE_REPO" -w "$MINIMACHINE_WORKFLOW" --limit 20 --json databaseId,status,conclusion,createdAt,updatedAt,headBranch,url,displayTitle)"
  if [[ "$json_output" == "1" ]]; then
    GH_JSON="$payload" python3 - <<'PY'
import json
import os
runs = [r for r in json.loads(os.environ.get("GH_JSON", "[]") or "[]") if r.get("status") in {"queued", "in_progress"}]
print(json.dumps(runs, indent=2))
PY
    return
  fi

  GH_JSON="$payload" python3 - <<'PY'
import json
import os
runs = [r for r in json.loads(os.environ.get("GH_JSON", "[]") or "[]") if r.get("status") in {"queued", "in_progress"}]
if not runs:
    print("No active mini-machine runs.")
    raise SystemExit
for run in runs:
    title = run.get('displayTitle') or run.get('headBranch') or ''
    print(f"{run['databaseId']}\t{run.get('status','')}\t{title}\t{run.get('createdAt','')}\t{run.get('url','')}")
PY
}

cmd_new() {
  local json_output="$1"
  shift
  local request_info="$*"
  [[ -n "${request_info//[[:space:]]/}" ]] || die "usage: machine.sh new <request-info> [--json]"

  local triggered_epoch
  triggered_epoch="$(date -u +%s)"

  gh workflow run "$MINIMACHINE_WORKFLOW" -R "$MINIMACHINE_REPO" -f request_info="$request_info" >/dev/null

  local run_id=""
  for _ in $(seq 1 45); do
    run_id="$(latest_active_run_id "$triggered_epoch")"
    if [[ -n "$run_id" ]]; then
      break
    fi
    sleep 2
  done
  [[ -n "$run_id" ]] || die "timed out waiting for a mini-machine run to start"

  for _ in $(seq 1 60); do
    if [[ "$(artifact_ready "$run_id")" == "1" ]]; then
      print_connection_info "$run_id" "$json_output"
      return
    fi

    local status
    local status_payload
    status_payload="$(gh run view "$run_id" -R "$MINIMACHINE_REPO" --json status,conclusion 2>/dev/null)"
    status="$(GH_JSON="$status_payload" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("GH_JSON", "{}") or "{}")
print(payload.get('status', ''))
print(payload.get('conclusion', ''))
PY
)"
    local run_status run_conclusion
    run_status="$(printf '%s' "$status" | sed -n '1p')"
    run_conclusion="$(printf '%s' "$status" | sed -n '2p')"
    if [[ "$run_status" == "completed" ]]; then
      die "run $run_id completed with conclusion: ${run_conclusion:-unknown} before connection info appeared"
    fi
    sleep 3
  done

  die "timed out waiting for connection info for run $run_id"
}

cmd_get() {
  local run_id="$1"
  local json_output="$2"
  [[ -n "$run_id" ]] || die "usage: machine.sh get <run-id> [--json]"
  print_connection_info "$run_id" "$json_output"
}

cmd_stop() {
  local run_id="$1"
  [[ -n "$run_id" ]] || die "usage: machine.sh stop <run-id>"
  gh run cancel "$run_id" -R "$MINIMACHINE_REPO"
}

main() {
  need gh
  need python3

  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    new)
      local json_output=0
      local request_info=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --json)
            json_output=1
            shift
            ;;
          --request-info)
            [[ -n "${2:-}" ]] || die "usage: machine.sh new --request-info <request-info> [--json]"
            request_info="${request_info}${request_info:+ }$2"
            shift 2
            ;;
          --help|-h)
            usage
            exit 0
            ;;
          *)
            request_info="${request_info}${request_info:+ }$1"
            shift
            ;;
        esac
      done
      cmd_new "$json_output" "$request_info"
      ;;
    list|ls)
      render_active_runs "$([[ "${1:-}" == "--json" ]] && echo 1 || echo 0)"
      ;;
    get)
      local run_id="${1:-}"
      shift || true
      cmd_get "$run_id" "$([[ "${1:-}" == "--json" ]] && echo 1 || echo 0)"
      ;;
    stop)
      cmd_stop "${1:-}"
      ;;
    help|-h|--help|"")
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"
