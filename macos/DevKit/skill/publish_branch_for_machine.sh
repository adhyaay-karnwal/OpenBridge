#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  publish_branch_for_machine.sh [--branch <branch>] --message <commit-message> [--machine-repo-dir <path>] [--dry-run]

Description:
  Stage the current OpenBridge changes, commit them to a git branch, push that branch
  to origin, and print the matching setup commands for the remote mini-machine.

Notes:
  Run your initial local compile pass before using this helper.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

BRANCH=""
COMMIT_MESSAGE=""
MACHINE_REPO_DIR='~/openbridge'
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --message|-m)
      COMMIT_MESSAGE="${2:-}"
      shift 2
      ;;
    --machine-repo-dir)
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
    *)
      die "unknown argument: $1"
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo_root" ]] || die "run this inside the openbridge git repository"
cd "$repo_root"

current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$current_branch" && -z "$BRANCH" ]]; then
  die "detached HEAD: pass --branch <branch>"
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$current_branch"
fi

if [[ -z "$current_branch" || "$current_branch" != "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    run git switch "$BRANCH"
  else
    run git switch -c "$BRANCH"
  fi
fi

changes="$(git status --porcelain)"
if [[ -n "$changes" ]]; then
  [[ -n "$COMMIT_MESSAGE" ]] || die "working tree is dirty: pass --message <commit-message>"
  run git add -A
  run git commit -m "$COMMIT_MESSAGE"
fi

run git push -u origin "$BRANCH"

cat <<EOF2
Branch ready for mini-machine: $BRANCH
Suggested first-run command from your local machine (streams the setup script over SSH, then the machine clones/builds locally):
  ssh -i <key> -o StrictHostKeyChecking=no -p <ssh-port> <user>@tunnel.eyhn.in 'bash -s -- --branch $BRANCH --repo-dir $MACHINE_REPO_DIR' < macos/DevKit/skill/setup_bridge_on_machine.sh
If this is the first clone on a private machine, inject your local GitHub token into that same command:
  ssh -i <key> -o StrictHostKeyChecking=no -p <ssh-port> <user>@tunnel.eyhn.in "CUEBOARD_GH_TOKEN='\$(gh auth token)' bash -s -- --branch $BRANCH --repo-dir $MACHINE_REPO_DIR" < macos/DevKit/skill/setup_bridge_on_machine.sh
Once the repo already exists on the machine, you can rerun setup directly there:
  bash $MACHINE_REPO_DIR/macos/DevKit/skill/setup_bridge_on_machine.sh --branch $BRANCH --repo-dir $MACHINE_REPO_DIR
For an already-running machine when you want to rerun setup after this push:
  macos/DevKit/skill/rerun_setup_on_machine.sh --run-id <run-id> --branch $BRANCH
EOF2
