# OpenBridge macOS App

OpenBridge 桌面端（SwiftUI + AppKit + WebKit），现在专注于聊天界面、本地 Agent、skills、记忆、定时任务和本地 VM 文件工作流。

## 快速开始

```bash
cd macos

# Debug 构建
bash DevKit/Scripts/workspace_build_debug.sh

# Unit 测试
bash DevKit/Scripts/workspace_test_unit.sh

# UI 测试
bash DevKit/Scripts/workspace_test_ui.sh
```

构建产物：`.build/DerivedData/Build/Products/Debug/OpenBridge.app`

## 主要模块

```text
OpenBridge/
├── Application/     # 启动流程（窗口、服务、本地 Agent preload）
├── Agent/           # 本地 Agent 桥接层（Session/History/Event/VM）
├── Backend/         # 本地业务服务（settings/skills/storage/...）
├── Interface/       # UI 层（Chat/Settings/Notch/...）
├── Helpers/         # 工具与 WebKitBridge
└── Resources/       # kernel/rootfs、内置资源
```

## Agent 集成路径

- `OpenBridge/Agent/AgentSessionManager.swift`
- `OpenBridge/Agent/LocalRuntime/LocalAgentSession.swift`
- `OpenBridge/Agent/SessionHistory.swift`
- `OpenBridge/Agent/LocalRuntime/LocalAgentEventAdapter.swift`

关键点：

- App 启动时后台预热本地 Agent 和本地 VM runtime
- 每个会话映射一个本地 KWWK agent session
- 历史消息、流式增量、工具状态都通过本地事件驱动 UI
- 工作区文件采用“接受/丢弃变更”流程

## WebView 集成路径

- Chat: `OpenBridge/Interface/WebViews/ChatWebView.swift`
- Chat OpenBridge: `OpenBridge/Interface/Chat/MessagesBridge.swift`

默认加载的内嵌资源：

- `WebKitBridgeResources/ChatAssets/chat.html`
- `WebKitBridgeResources/PreviewAssets/preview.html`

Debug 下 chat 资源缺失时会回退 `http://localhost:8083`。

## 开发注意事项

- 优先使用 `DevKit/Scripts/*`，不要手写 `xcodebuild` 流程。
- 不要直接编辑 `.xcstrings`，使用 `DevKit/XcodeStringsHelper/i18n.py apply`。
- 修改 Go 事件/消息结构时，必须同步更新 Swift 类型与 web embedded 类型。
