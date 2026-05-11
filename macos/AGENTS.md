# macOS App (macos)

This file provides guidance to coding agents working in `macos/`.

> Read repo-wide rules first: [`/AGENTS.md`](../../AGENTS.md)

## What This Component Is

OpenBridge macOS app is a SwiftUI + AppKit + WebKit application that combines:

- embedded AI chat UI
- local agent orchestration through vendored `kwwk`
- sandbox VM execution through `sandbox-vm`

## Current Structure

```text
macos/
├── OpenBridge/
│   ├── Application/      app lifecycle (`AppDelegate`)
│   ├── Agent/            agent bridge (`AgentSessionManager`, `Session`, `SessionHistory`)
│   ├── Backend/          local services (settings, skills, storage helpers, etc.)
│   ├── Interface/        SwiftUI/AppKit views + controllers
│   ├── Helpers/          shared utilities + WebKitBridgeUI
│   ├── Resources/        kernel/rootfs, built-in assets, skills
│   └── ResourcesBundles/ localized strings + app assets
├── Frameworks/           local Swift packages (ComposerEditor, ...)
├── JSBridge/             bridge macros/codegen package
├── DevKit/Scripts/       build/test/release scripts
├── OpenBridgeUITests/
└── OpenBridgeUnitTests/
```

## Build and Test

Run from `macos`:

- `bash DevKit/Scripts/workspace_build_debug.sh`
- `BUILD_CONFIGURATION=UnsignedDebug bash DevKit/Scripts/workspace_build_debug.sh` only when the user explicitly asks for an unsigned local build or the target machine truly lacks signing certificates
- `bash DevKit/Scripts/workspace_test_unit.sh`
- `bash DevKit/Scripts/workspace_test_ui.sh`

After finishing a macOS app feature, prefer doing one end-to-end smoke pass with the mini-machine OpenBridge debug skill in `DevKit/skill/` before wrapping up. Start with `DevKit/skill/skill.md`, use `machine.sh` to manage the remote macOS session, use `publish_branch_for_machine.sh` to snapshot local changes after a successful compile pass when needed, use `setup_bridge_on_machine.sh` to clone/build/open OpenBridge on the machine, and drive the actual UI with the `vnc` computer-use loop (`get_screenshot -> inspect -> click/type/key -> re-screenshot`).

Notes:

- Use DevKit scripts instead of invoking `xcodebuild` manually.
- Build output goes to `.build/DerivedData/Build/Products/Debug/OpenBridge.app`.
- Default to signed `Debug` or `Release` for local debugging, reproduction, UI validation, and any `local-vm` work. The `UnsignedDebug` configuration/profile uses ad-hoc bundle signing without a developer certificate and switches session auth storage from Keychain to local disk, so keep it limited to explicit unsigned requests or machines that cannot sign.
- UI test script writes result bundle to `.build/TestResults/OpenBridgeUITests.xcresult`.
- Unit test script writes result bundle to `.build/TestResults/OpenBridgeUnitTests.xcresult`.

## Swift ↔ Go Agent Boundary

Main bridge code:

- `OpenBridge/Agent/AgentSessionManager.swift`
- `OpenBridge/Agent/LocalRuntime/LocalAgentSession.swift`
- `OpenBridge/Agent/SessionHistory.swift`
- `OpenBridge/Agent/LocalRuntime/LocalAgentEventAdapter.swift`

Important behaviors:

- app preloads VM runtime on launch (`AgentSessionManager.shared.preload()`)
- each chat conversation maps to one local KWWK agent session
- history and runtime events are emitted locally into the existing chat UI contract
- workspace accept/discard flows call `applySessionDiff`/`discardSessionAllChanges`

## Swift ↔ WebView Boundary

Key files:

- `OpenBridge/Interface/WebViews/ChatWebView.swift`
- `OpenBridge/Interface/Chat/MessagesBridge.swift`

Embedded assets loaded from app bundle:

- `WebKitBridgeResources/ChatAssets/chat.html`
- `WebKitBridgeResources/PreviewAssets/preview.html`

In Debug, embedded surfaces can be pointed at localhost dev servers explicitly via environment configuration; do not rely on missing bundled assets as the switch.

## Event Contracts You Must Respect

History message schema in Swift mirror:

- `SessionHistoryMessage` (`message`, `task`, `question`, `question_reply`, `sandbox_*`)
- `AssistantState`

If you change payload shape in Go, update corresponding Swift + web mirror types together.

## High-Impact Areas

- `OpenBridge/Backend/SettingsManager/`: persisted local settings and feature toggles
- `OpenBridge/Backend/Skills/`: local skill install/update lifecycle
- `OpenBridge/Backend/Supplements/`: local media and storage helpers
- `OpenBridge/Interface/Chat/`: message sending, retry, confirmations, attachments
- `OpenBridge/Interface/Windows/`: panel/window lifecycle

## Localization Rules

- use `String(localized:)` for user-visible strings
- never edit `.xcstrings` directly
- use `macos/DevKit/XcodeStringsHelper/i18n.py apply`

## Guardrails for Agents

- Do not reference removed symbols like `AgentTaskManager`.
- Do not document session storage as `~/.bridge/tasks`; runtime now uses sessions.
- Keep docs and bridge contracts aligned across Swift, Go, and `web/src/embedded/*`.
- Do not add comments that only explain chat context; comments must be durable.
