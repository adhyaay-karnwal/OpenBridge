#!/bin/zsh
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: grant-permissions.zsh [--binary PATH] [--scope user|system] [--user NAME] [--tccutil PATH] [--service NAME]... [--check-command COMMAND] [--dry-run]

Defaults:
  binary   current repo's built SWaveAXRaceDemoApp bundle executable
  scope    user
  service  kTCCServiceAccessibility kTCCServiceScreenCapture
EOF
}

resolve_realpath() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

is_truthy() {
    case "${1:l}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
log_tool="/usr/bin/log"

binary_path="${GRANT_BINARY:-}"
scope="${GRANT_SCOPE:-user}"
user_name="${GRANT_USER:-}"
tccutil_path="${GRANT_TCCUTIL:-}"
dry_run="${GRANT_DRY_RUN:-0}"
check_command="${GRANT_CHECK_COMMAND:-}"
services_overridden=0
default_services=(
    "kTCCServiceAccessibility"
    "kTCCServiceScreenCapture"
)
services=()
tccutil_command=()

if [[ -n "${GRANT_SERVICES:-}" ]]; then
    services=(${=GRANT_SERVICES})
else
    services=("${default_services[@]}")
fi

while (($# > 0)); do
    case "$1" in
        --binary)
            shift
            (($# > 0)) || {
                print -- "missing value for --binary" >&2
                exit 1
            }
            binary_path="$1"
            ;;
        --scope)
            shift
            (($# > 0)) || {
                print -- "missing value for --scope" >&2
                exit 1
            }
            scope="$1"
            ;;
        --user)
            shift
            (($# > 0)) || {
                print -- "missing value for --user" >&2
                exit 1
            }
            user_name="$1"
            ;;
        --tccutil)
            shift
            (($# > 0)) || {
                print -- "missing value for --tccutil" >&2
                exit 1
            }
            tccutil_path="$1"
            ;;
        --check-command)
            shift
            (($# > 0)) || {
                print -- "missing value for --check-command" >&2
                exit 1
            }
            check_command="$1"
            ;;
        --service)
            shift
            (($# > 0)) || {
                print -- "missing value for --service" >&2
                exit 1
            }
            if (( services_overridden == 0 )); then
                services=()
                services_overridden=1
            fi
            services+=("$1")
            ;;
        --dry-run)
            dry_run=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$binary_path" ]]; then
                binary_path="$1"
            else
                print -- "unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

case "$scope" in
    user|system) ;;
    *)
        print -- "unsupported scope: $scope" >&2
        exit 1
        ;;
esac

if [[ "$scope" == "system" && -n "$user_name" ]]; then
    print -- "--user is only valid when --scope user" >&2
    exit 1
fi

if ((${#services[@]} == 0)); then
    print -- "at least one --service is required" >&2
    exit 1
fi

if [[ -z "$binary_path" ]]; then
    binary_path="$(
        cd "$repo_root"
        ./Scripts/build-ax-race-demo-app.zsh
    )"
fi

[[ -e "$binary_path" ]] || {
    print -- "binary not found: $binary_path" >&2
    exit 1
}
[[ -x "$binary_path" ]] || {
    print -- "binary is not executable: $binary_path" >&2
    exit 1
}

binary_path="$(resolve_realpath "$binary_path")"

if [[ -z "$tccutil_path" ]]; then
    if [[ -x "/usr/local/bin/tccutil" ]]; then
        tccutil_path="/usr/local/bin/tccutil"
    else
        tccutil_path="${script_dir}/tccutil.swift"
    fi
fi

[[ -e "$tccutil_path" ]] || {
    print -- "tccutil not found: $tccutil_path" >&2
    exit 1
}

if [[ "$tccutil_path" == *.swift ]]; then
    tccutil_command=(swift "$tccutil_path")
else
    [[ -x "$tccutil_path" ]] || {
        print -- "tccutil is not executable: $tccutil_path" >&2
        exit 1
    }
    tccutil_command=("$tccutil_path")
fi

"${(@)tccutil_command}" --version >/dev/null

run_tccutil() {
    local -a arguments=("$@")

    if is_truthy "${dry_run}"; then
        print -- "dry-run: ${(@q)tccutil_command} ${(@q)arguments}"
        return 0
    fi

    "${(@)tccutil_command}" "${(@)arguments}"
}

detect_vm() {
    [[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null || print 0)" == "1" ]]
}

detect_sip_disabled() {
    csrutil status 2>&1 | grep -qi 'disabled'
}

run_check_command() {
    local command_string="$1"

    [[ -n "$command_string" ]] || return 1

    if is_truthy "${dry_run}"; then
        print -- "dry-run: zsh -lc ${(@q)command_string}"
        return 0
    fi

    zsh -lc "$command_string"
}

extract_responsible_subjects() {
    local log_output="$1"
    local target_binary="$2"

    LOG_TEXT="$log_output" TARGET_BINARY="$target_binary" python3 - <<'PY'
import os
import re

log_text = os.environ["LOG_TEXT"]
target_binary = os.environ["TARGET_BINARY"]

attribution_pattern = re.compile(r'AUTHREQ_ATTRIBUTION: msgID=([^,]+),.*binary_path=' + re.escape(target_binary))
subject_pattern = re.compile(r'AUTHREQ_SUBJECT: msgID=([^,]+), subject=([^,]+),')
responsible_path_pattern = re.compile(r'AUTHREQ_ATTRIBUTION: msgID=([^,]+),.*responsible_path=([^,]+),')
responsible_identifier_pattern = re.compile(r'AUTHREQ_ATTRIBUTION: msgID=([^,]+), attribution=\{responsible=\{TCCDProcess: identifier=([^,]+),')

message_ids = []
for line in log_text.splitlines():
    match = attribution_pattern.search(line)
    if match:
        message_ids.append(match.group(1))

subjects = []
seen = set()
message_id_set = set(message_ids)

for line in log_text.splitlines():
    match = responsible_path_pattern.search(line)
    if not match:
        continue
    message_id, subject = match.groups()
    if message_id not in message_id_set:
        continue
    subject = subject.strip()
    if not subject or subject == target_binary or subject in seen:
        continue
    seen.add(subject)
    subjects.append(subject)

for line in log_text.splitlines():
    match = responsible_identifier_pattern.search(line)
    if not match:
        continue
    message_id, subject = match.groups()
    if message_id not in message_id_set:
        continue
    subject = subject.strip()
    if not subject or subject == target_binary or subject in seen:
        continue
    seen.add(subject)
    subjects.append(subject)

for line in log_text.splitlines():
    match = subject_pattern.search(line)
    if not match:
        continue
    message_id, subject = match.groups()
    if message_id not in message_id_set:
        continue
    subject = subject.strip()
    if not subject or subject == target_binary or subject in seen:
        continue
    seen.add(subject)
    subjects.append(subject)

print("\n".join(subjects))
PY
}

run_tccutil_for_scope() {
    local command_scope="$1"
    shift
    local -a arguments=("$@")
    local -a command_prefix=()

    if [[ "$command_scope" == "system" ]]; then
        command_prefix=(sudo -n)
    fi

    if is_truthy "${dry_run}"; then
        print -- "dry-run: ${(@q)command_prefix} ${(@q)tccutil_command} ${(@q)arguments}"
        return 0
    fi

    "${(@)command_prefix}" "${(@)tccutil_command}" "${(@)arguments}"
}

capture_tcc_logs_for_check() {
    local command_string="$1"
    local log_file
    local logger_pid

    log_file="$(mktemp)"

    "$log_tool" stream --style compact --predicate 'subsystem == "com.apple.TCC"' >"$log_file" 2>&1 &
    logger_pid=$!
    sleep 1

    if run_check_command "$command_string"; then
        check_command_status=0
    else
        check_command_status=$?
    fi

    sleep 1
    kill "$logger_pid" 2>/dev/null || true
    wait "$logger_pid" 2>/dev/null || true
    captured_tcc_log_output="$(cat "$log_file")"
    rm -f "$log_file"
}

grant_client_for_all_services() {
    local client="$1"
    local client_scope="$2"
    local -a client_scope_args=()

    if [[ "$client_scope" == "user" ]]; then
        client_scope_args=("${(@)scope_args}")
    fi

    print -- "granting responsible process: $client ($client_scope)"

    for service in "${services[@]}"; do
        run_tccutil_for_scope "$client_scope" \
            --service "$service" \
            --insert "$client" \
            "${(@)client_scope_args}"

        run_tccutil_for_scope "$client_scope" \
            --service "$service" \
            --enable "$client" \
            "${(@)client_scope_args}"
    done
}

scope_args=()
if [[ "$scope" == "user" ]]; then
    if [[ -n "$user_name" ]]; then
        scope_args=(--user "$user_name")
    else
        scope_args=(--user)
    fi
fi

print -- "tccutil: $tccutil_path"
print -- "binary: $binary_path"
print -- "scope: $scope"

if [[ "$scope" == "user" && -n "$user_name" ]]; then
    print -- "user: $user_name"
fi

if [[ -z "$check_command" && "${binary_path:t}" == "computeruse" ]]; then
    check_command="${(q)binary_path} check-permission"
fi

if [[ -z "$check_command" && "${binary_path:t}" == "SWaveAXRaceDemo" ]]; then
    check_command="${(q)binary_path} --bundle-id com.apple.finder --strategy inspect"
fi

if [[ -z "$check_command" && "${binary_path:t}" == "SWaveAXRaceDemoApp" ]]; then
    check_command="${(q)binary_path} --bundle-id com.apple.finder --strategy inspect"
fi

for service in "${services[@]}"; do
    print -- "granting: $service"

    run_tccutil \
        --service "$service" \
        --insert "$binary_path" \
        "${(@)scope_args}"

    run_tccutil \
        --service "$service" \
        --enable "$binary_path" \
        "${(@)scope_args}"

    if is_truthy "${dry_run}"; then
        continue
    fi

    list_output="$("${(@)tccutil_command}" --service "$service" --list "${(@)scope_args}" 2>/dev/null || true)"
    print -- "$list_output" | grep -Fqx -- "$binary_path" || {
        print -- "verification failed for $service" >&2
        exit 1
    }
    print -- "verified: $service"
done

if detect_vm && detect_sip_disabled && [[ -n "$check_command" ]]; then
    print -- "vm mode: checking for responsible process supplement"

    if is_truthy "${dry_run}"; then
        print -- "dry-run: responsible process check enabled"
    else
        print -- "running check: $check_command"
        capture_tcc_logs_for_check "$check_command"

        if (( check_command_status == 0 )); then
            print -- "initial check passed"
        else
            print -- "initial check reported missing permissions"
        fi

        responsible_subjects=()
        while IFS= read -r subject; do
            [[ -n "$subject" ]] || continue
            responsible_subjects+=("$subject")
        done <<< "$(extract_responsible_subjects "$captured_tcc_log_output" "$binary_path")"

        if ((${#responsible_subjects[@]} > 0)); then
            print -- "responsible subjects: ${responsible_subjects[*]}"
            for subject in "${responsible_subjects[@]}"; do
                subject_scope="$scope"
                if [[ "$subject" == /* ]] && [[ "$subject" != "${HOME}"* ]]; then
                    subject_scope="system"
                fi
                grant_client_for_all_services "$subject" "$subject_scope"
            done

            print -- "rerunning check after responsible process supplement"
            if run_check_command "$check_command"; then
                print -- "follow-up check passed"
            else
                print -- "follow-up check still reported missing permissions"
            fi
        else
            print -- "no responsible process subject found in TCC logs"
        fi
    fi
fi

print -- "grant complete"
