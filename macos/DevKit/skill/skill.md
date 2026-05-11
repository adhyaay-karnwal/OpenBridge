---
name: openbridge-debug
description: Debug and validate OpenBridge on a real macOS desktop through mini-machine plus full VNC computer-use. Use when local broker automation is not enough, when you need end-to-end GUI verification on macOS, or when local changes should be pushed to a branch and rebuilt from a fresh machine clone instead of transferred manually.
---

# OpenBridge Debug via Mini-Machine

This skill replaces the old local OpenBridge automation MCP flow.

Use a remote macOS machine plus full computer-use instead:

- `machine.sh` creates/lists/gets/stops mini-machine sessions and requires a request description for each new machine.
- `publish_branch_for_machine.sh` snapshots local changes to a git branch so the remote Mac can build them directly; a local compile pass is optional, not required.
- `rerun_setup_on_machine.sh` reruns setup on an already-running machine so OpenBridge reopens with the updated branch after you push.
- `setup_bridge_on_machine.sh` clones OpenBridge on the remote Mac, builds OpenBridge, and opens the app.
- `vnc` is the actual computer-use tool for screenshots, clicks, typing, keys, and scroll.

## Prerequisites

From the local machine:

```bash
gh auth status
python3 -m pip install --user --break-system-packages vnc-computer-use   # if `vnc` is missing
```

If your Python install is externally managed and you do not want `--break-system-packages`, install `vnc-computer-use` with a virtualenv or `pipx` instead.

You need `repo` + `workflow` scopes for `gh`.

For private repo clone **inside** the remote macOS machine, use one of these:

1. `gh auth login` on the machine.
2. Export `CUEBOARD_GH_TOKEN` on the machine before cloning.
3. Export `CUEBOARD_REPO_URL` to a clone URL the machine can access.

## Default workflow

You do **not** need a successful local build before creating or using a machine. A remote machine build can be your first compile/validation pass; a local build is only an optional preflight when you want faster feedback before pushing.

### 1. If local changes are not pushed yet, publish them to a branch (local compile optional)

If you want a quick local preflight before pushing, run from the repo root:

```bash
cd web && yarn install --immutable && yarn build:embedded
cd ../macos && BUILD_CONFIGURATION=UnsignedDebug bash DevKit/Scripts/workspace_build_debug.sh
```

If you do not need the local preflight, skip straight to the publish step. In either case, push the branch snapshot so the remote Mac can do the compile/validation pass:

```bash
macos/DevKit/skill/publish_branch_for_machine.sh \
  --message "wip: describe the current OpenBridge fix" \
  --branch your-branch-name
```

That prints the matching machine-side setup command.

### 1b. When a machine is already running and you want the updated OpenBridge there quickly

After you push the latest branch snapshot, run:

```bash
macos/DevKit/skill/publish_branch_for_machine.sh \
  --branch your-branch-name \
  --message "wip: describe the latest OpenBridge change"

macos/DevKit/skill/rerun_setup_on_machine.sh \
  --run-id <run-id> \
  --branch your-branch-name
```

If the branch is already committed and clean locally, omit `--message` from the publish step.

This keeps the update flow atomic:

1. stages/commits local changes when needed
2. pushes the branch to origin
3. reruns setup on the still-running machine from a second explicit command
4. updates the existing checkout, rebuilds OpenBridge, kills the older OpenBridge process, and reopens the new one

Forward any extra machine setup flags after `--`, for example:

```bash
macos/DevKit/skill/rerun_setup_on_machine.sh \
  --run-id <run-id> \
  --branch your-branch-name \
  -- --skip-open
```

### 2. Create a macOS machine

Always create a fresh mini-machine for your own validation run. Do **not** take over or reuse a machine that someone else may already be using, even if it looks idle. If you need to continue your own in-flight debugging session, only reconnect to the machine that you created for that same task.

```bash
macos/DevKit/skill/machine.sh new "Validate OpenBridge on branch your-branch-name"
```

Save:

- run id
- VNC URL
- VNC user
- VNC password
- SSH command

Use `macos/DevKit/skill/machine.sh list` to see active run titles/request descriptions, and `get <run-id>` if you need the connection info later.

### 3. Connect with full computer use

```bash
vnc connect tunnel.eyhn.in::<vnc-port> --username <user> --password=<password>
```

Always drive the UI with the full screenshot loop:

```bash
vnc get_screenshot -o /tmp/bridge-machine.png
# inspect the screenshot
vnc left_click <x> <y>
vnc type "text"
vnc key enter
vnc scroll down:400 700 500
vnc get_screenshot -o /tmp/bridge-machine-after.png
```

Rules:

- Take a screenshot before clicking.
- Click the center of the target, not the edge.
- Re-screenshot after every important action.
- Use keyboard shortcuts when they are simpler than pixel hunting.

### 4. Clone/build/open OpenBridge on the machine

Over SSH:

```bash
ssh -i <key> -o StrictHostKeyChecking=no -p <ssh-port> admin@tunnel.eyhn.in
```

For a fresh machine with no repo checkout yet, run the setup script from your **local** machine and stream it over SSH:

```bash
ssh -i <key> -o StrictHostKeyChecking=no -p <ssh-port> <user>@tunnel.eyhn.in \
  'bash -s -- --branch your-branch-name --repo-dir ~/openbridge' \
  < macos/DevKit/skill/setup_bridge_on_machine.sh
```

That keeps the heavy transfer on the machine side: the script itself is tiny, but the repository clone and build happen on the remote Mac.

For the first clone against the private OpenBridge repo, the easiest path is to inject your local GitHub token into the remote command:

```bash
ssh -i <key> -o StrictHostKeyChecking=no -p <ssh-port> <user>@tunnel.eyhn.in \
  "CUEBOARD_GH_TOKEN='$(gh auth token)' bash -s -- --branch your-branch-name --repo-dir ~/openbridge" \
  < macos/DevKit/skill/setup_bridge_on_machine.sh
```

`setup_bridge_on_machine.sh` will also bootstrap a portable Node.js toolchain on the machine when `node`/`corepack` are missing, pin the same SwiftFormat version used in CI, mark onboarding as complete, seed the user TCC database through a pinned copy of `jacobsalmela/tccutil` plus the required AppleEvents rows for OpenBridge / Terminal / `osascript`, and open the local OpenBridge build.

If the repo is already present on the machine, you can instead SSH in and run:

```bash
bash ~/openbridge/macos/DevKit/skill/setup_bridge_on_machine.sh \
  --branch your-branch-name \
  --repo-dir ~/openbridge
```

If the repo is private and the machine is not authenticated yet, first do one of:

```bash
gh auth login
# or
export CUEBOARD_GH_TOKEN=...
```

For day-to-day iteration, prefer `publish_branch_for_machine.sh` followed by `rerun_setup_on_machine.sh` instead of typing the SSH command manually; that keeps “push code” and “rerun machine setup” as two explicit steps while still making the warm-machine rebuild short.

### 5. Validate the bug or the new feature in OpenBridge

After the script opens OpenBridge.app, switch back to VNC and test the real UI.

Common loop:

1. `vnc get_screenshot`
2. inspect the current window
3. click/type/key/scroll
4. `vnc get_screenshot` again
5. repeat until the bug is reproduced or the feature is verified

By default the setup script marks onboarding as complete for the private repo workflow, so a fresh UnsignedDebug machine should open directly into the local app. Override `BRIDGE_COMPLETE_ONBOARDING` when you need a different bootstrap state.

### 6. Stop the machine when done

```bash
vnc disconnect
macos/DevKit/skill/machine.sh stop <run-id>
```

## Fast paths

### Reconnect to a machine you created yourself

Only use this when you are resuming **your own** existing debugging session. Do not use `list`/`get` to adopt a machine created by someone else; start a new machine instead for any new validation run.

```bash
macos/DevKit/skill/machine.sh list
macos/DevKit/skill/machine.sh get <run-id>
```

### Dry-run the helper scripts before using them for real

```bash
macos/DevKit/skill/publish_branch_for_machine.sh --branch test-branch --message "test" --dry-run
macos/DevKit/skill/rerun_setup_on_machine.sh --run-id 123456789 --branch test-branch --dry-run
macos/DevKit/skill/setup_bridge_on_machine.sh --branch test-branch --repo-dir ~/openbridge --dry-run
```

## Troubleshooting

- `machine.sh new` fails immediately: provide a request description, then re-check `gh auth status` and token scopes.
- `vnc` is missing: `python3 -m pip install --user vnc-computer-use`.
- machine clone fails: authenticate `gh` on the machine or export `CUEBOARD_GH_TOKEN`.
- OpenBridge builds but does not open the right app: rerun `setup_bridge_on_machine.sh`; it kills older `OpenBridge.app` processes before opening the fresh build.
- VNC password starts with `-`: use `--password=<password>`.
