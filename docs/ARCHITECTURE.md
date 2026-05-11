# OpenBridge Architecture

OpenBridge is a local-first macOS agent app. The native app owns product state and user interaction, the embedded web package renders chat surfaces, `kwwk` runs the agent loop, and `sandbox-vm` provides isolated execution and reviewable file changes.

## Runtime Shape

```text
OpenBridge.app
├─ macos/
│  ├─ SwiftUI and AppKit UI
│  ├─ local agent sessions
│  ├─ provider settings and auth resolution
│  ├─ skill discovery and activation
│  └─ WebKit bridge methods exposed to embedded React
├─ web/
│  ├─ chat WebView bundle
│  └─ preview WebView bundle
├─ kwwk/
│  └─ agent SDK, model providers, tools, and CLI primitives
└─ sandbox-vm/
   └─ local VM runtime, sandbox environments, and workspace review APIs
```

## Native App

The macOS target lives under `macos/OpenBridge`.

- Agent orchestration starts in `Agent/LocalRuntime/LocalAgentSession.swift`.
- Provider configuration is modeled in `Agent/BridgeAIProviderSettings.swift`.
- Provider registration and runtime credential resolution live in `Agent/BridgeAIProviderRegistry.swift`.
- Provider secrets and settings are persisted locally by `Agent/BridgeAIProviderSecretStore.swift`.
- Title generation is intentionally separate from the main agent run in `Agent/LocalRuntime/LocalAgentSession+TitleGeneration.swift`.
- WebView bridge methods are exposed from `Interface/Chat/MessagesBridge.swift`.
- Settings and skill UI live under `Interface/Settings`.

The Swift layer should keep OpenBridge-specific behavior here. Shared agent primitives that are useful outside OpenBridge belong in `kwwk`.

## Embedded WebViews

The web package lives under `web`.

- `src/embedded/chat` renders the chat transcript, tool activity, review cards, attachments, and workspace state.
- `src/embedded/preview` renders preview surfaces.
- `src/utils/jsbridge-client.ts` and related bridge utilities isolate the WebKit JS bridge contract.
- `src/embedded/chat/hooks/use-swift-bridge.ts` subscribes to native session updates and workspace review state.

The embedded assets are built with:

```bash
cd web
yarn build:embedded
```

The macOS app packages the generated assets, so rebuild them before app builds when the bridge surface or bundled WebView code changes.

## Agent Runtime

OpenBridge registers model providers from `kwwk`, then supplies OpenBridge-owned credentials at request time. This keeps provider modeling and model catalogs in `kwwk` while letting the app manage OAuth, API keys, refresh, usage display, and enabled-provider filtering.

Key boundaries:

- `kwwk` owns general agent SDK concepts: providers, models, tools, streaming events, and provider auth resolver hooks.
- OpenBridge owns product state: settings, per-user provider enablement, credential storage, usage refresh, skills UI, schedules, and native permissions.
- The bridge from OpenBridge to `kwwk` should stay generic enough that improvements can be proposed upstream.

## Sandbox Runtime

The sandbox VM is split between Swift orchestration and the Go runtime in `sandbox-vm`.

- Swift starts and talks to the runtime through `Agent/LocalRuntime/EmbeddedVMRuntimeBridge.swift`.
- Session code reads workspace state and applies review actions through `AgentSessionManager.swift` and `LocalAgentSession.swift`.
- Go exposes local connector APIs in `sandbox-vm/sdk/apple/local_connector.go`.
- The shared runtime is implemented in `sandbox-vm/internal/localconnector`.

See [SANDBOX_VM.md](SANDBOX_VM.md) for the review and isolation model.

## Contribution Rules

- Keep app-specific UI and persistence in `macos/OpenBridge`.
- Keep browser-rendered chat behavior in `web/src/embedded`.
- Keep VM state, overlay behavior, and accept/reject semantics in `sandbox-vm`.
- Keep broadly reusable agent-provider work in `kwwk`.
- Update tests in the component that owns the behavior.

