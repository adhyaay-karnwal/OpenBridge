# Sandbox VM

OpenBridge uses a local VM runtime so the agent can inspect and edit files without immediately mutating the host filesystem. The UI presents pending sandbox changes as reviewable files that the user can accept or discard.

## Goals

- Prefer sandbox execution for agent file and shell operations.
- Keep sandbox sessions isolated from each other.
- Show pending workspace changes in chat and notch UI.
- Let users accept selected files or discard all changes.
- Fall back to host operations only when the sandbox cannot complete the task and the user grants permission.

## Main Code Paths

| Area | Source |
| --- | --- |
| Swift runtime bridge | `macos/OpenBridge/Agent/LocalRuntime/EmbeddedVMRuntimeBridge.swift` |
| Session workspace refresh | `macos/OpenBridge/Agent/LocalRuntime/LocalAgentSession.swift` |
| App-level VM manager | `macos/OpenBridge/Agent/AgentSessionManager.swift` |
| Workspace UI model | `macos/OpenBridge/Agent/WorkspaceTypes.swift` |
| Web activity center | `web/src/embedded/chat/components/messages/activity-center/index.tsx` |
| Review file tree | `web/src/embedded/chat/components/messages/diff-file-tree.tsx` |
| Go runtime API | `sandbox-vm/sdk/apple/local_connector.go` |
| Go shared runtime | `sandbox-vm/internal/localconnector/shared_runtime.go` |
| Go per-session runtime | `sandbox-vm/internal/localconnector/runtime.go` |

## Runtime Flow

1. The macOS app starts the local connector runtime.
2. Each agent session is associated with a sandbox environment.
3. Agent tools prefer the sandbox environment for shell, read, write, and grep work.
4. The session periodically refreshes workspace state.
5. The WebView receives workspace state through the JS bridge.
6. Users accept selected files or reject the whole sandbox diff.
7. Accepted files are applied to the host workspace; rejected files are discarded from the sandbox overlay.

## Review State

Workspace state is represented in Swift by `WorkspaceState` and `FileDiff` in `macos/OpenBridge/Agent/WorkspaceTypes.swift`.

The web chat consumes the same state through `MessagesBridge.getWorkspaceState()` and `MessagesBridge.onWorkspaceState(...)`. The activity center renders pending files and calls:

- `MessagesBridge.acceptFiles(paths, environmentId)`
- `MessagesBridge.discardAllChanges(environmentId)`

The native bridge forwards those calls to the active `LocalAgentSession`, which resolves the sandbox environment ID and delegates to `AgentSessionManager`.

## Current Changes Tool

OpenBridge exposes a `current_changes` tool from `macos/OpenBridge/Agent/LocalRuntime/OpenBridgeCodingTools.swift`.

The system prompt asks the agent to call this tool after sandbox file operations. The tool returns a human-readable summary and structured diff metadata, which helps the agent describe what changed before ending a turn.

## Isolation Expectations

- Host paths should be mounted into the VM through the runtime, not accessed by ad hoc path translation.
- Sandbox writes should be visible in workspace state before they are accepted.
- Each OpenBridge session should have its own sandbox environment.
- Permission-gated host tools should remain separate from sandbox tools.
- The UI should treat `.app` bundles and other package-like directories as grouped review items where possible.

## Testing

Run the Go tests:

```bash
cd sandbox-vm
make go-test
```

Run web tests for workspace review rendering:

```bash
cd web
yarn test
```

For native changes, build the unsigned debug app:

```bash
cd macos
BUILD_CONFIGURATION=UnsignedDebug bash DevKit/Scripts/workspace_build_debug.sh
```

