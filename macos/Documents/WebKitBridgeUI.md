# WebKitBridgeUI 文档

## 概述

WebKitBridgeUI 是一个 Swift 包，提供原生代码与 WebKit 网页视图之间的双向通信桥梁。支持 async/await 并发模式，类型安全的错误处理，以及结构化日志。

## 核心特性

- **双向通信**：Swift ↔ JavaScript 消息传递
- **Async/Await**：现代 Swift 并发支持
- **类型安全**：完整的错误类型定义
- **结构化日志**：集成 SwiftLog
- **平台支持**：macOS 14+, iOS 17+, tvOS 17+, watchOS 10+

## 快速开始

### 1. 创建 OpenBridge

```swift
import WebKitBridgeUI

let bridge = WebKitBridge()
```

### 2. 等待就绪

```swift
try await bridge.waitUntilReady(timeout: 10.0)
```

### 3. 注册消息处理器

```swift
bridge.registerMessageHandler(named: "myHandler") { message in
    print("收到消息: \(message)")
}
```

### 4. 在 SwiftUI 中使用

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        BridgeView()
            .registerMessageHandler(named: "hello") { message in
                print("Hello: \(message)")
            }
    }
}
```

## API 参考

### WebKitBridge

主要的 OpenBridge 类，管理 WKWebView 和消息通信。

#### 初始化

```swift
init(
    frame: CGRect = .zero,
    configuration: WKWebViewConfiguration = WKWebViewConfiguration(),
    handshakeMessageName: String = "bridgeReady",
    handshakeCompletionValue: String = "complete",
    autoLoadDefaultHTML: Bool = true
)
```

#### 关键方法

| 方法 | 说明 |
|------|------|
| `registerMessageHandler(named:handler:)` | 注册 JS 消息处理器 |
| `removeMessageHandler(named:)` | 移除消息处理器 |
| `waitUntilReady(timeout:)` | 等待 OpenBridge 就绪（async） |
| `isReady()` | 检查 OpenBridge 是否就绪（async） |
| `loadDefaultHTML()` | 加载默认 HTML 资源 |

#### 属性

| 属性 | 说明 |
|------|------|
| `webView` | 底层 WKWebView 实例 |
| `userScriptController` | WKUserContentController |
| `defaultMessageHandler` | 默认消息处理器回调 |

### BridgeView

SwiftUI 视图包装器，自动处理平台差异（macOS/iOS）。

```swift
BridgeView(
    frame: CGRect = .zero,
    configuration: WKWebViewConfiguration = WKWebViewConfiguration(),
    handshakeMessageName: String = "bridgeReady",
    handshakeCompletionValue: String = "complete"
)
.registerMessageHandler(named: "handler1") { message in ... }
.onDefaultMessage { name, message in ... }
```

### 错误处理

```swift
public enum WebKitBridgeError: Error {
    case readinessTimedOut(TimeInterval)
}
```

## 通信流程

### JavaScript → Swift

1. JS 调用 `window.webkit.messageHandlers.handlerName.postMessage(data)`
2. OpenBridge 接收消息并调用对应的 Swift 处理器
3. 处理器执行业务逻辑

### Swift → JavaScript

1. 通过 `WKWebView.evaluateJavaScript()` 执行 JS 代码
2. 或在 HTML 中预定义回调函数供 Swift 调用

## 日志配置

OpenBridge 使用 SwiftLog，支持以下日志级别：

- **DEBUG**：消息处理、脚本执行详情
- **INFO**：初始化、就绪事件
- **WARNING**：警告条件
- **ERROR**：错误条件

### 自定义日志

```swift
import Logging

let handler = ConsoleLogHandler(label: "MyApp", level: .debug)
LoggingSystem.bootstrap { _ in handler }
```

## 生命周期

1. **初始化**：创建 WebKitBridge 实例
2. **加载**：自动加载默认 HTML（或自定义 HTML）
3. **握手**：JS 发送 `bridgeReady` 消息
4. **就绪**：OpenBridge 标记为就绪状态
5. **通信**：双向消息传递
6. **清理**：deinit 时自动移除所有处理器

## 最佳实践

1. **等待就绪**：始终在通信前调用 `waitUntilReady()`
2. **错误处理**：使用 try-catch 处理超时错误
3. **内存管理**：避免在处理器中持有 OpenBridge 的强引用
4. **线程安全**：OpenBridge 使用 `@MainActor` 确保主线程执行
5. **日志调试**：启用 DEBUG 日志排查通信问题

## 常见问题

**Q: OpenBridge 超时怎么办？**  
A: 检查 HTML 是否正确加载，确保 JS 代码执行了握手消息。

**Q: 如何自定义 HTML？**  
A: 创建 OpenBridge 后，使用 `webView.load()` 加载自定义 HTML。

**Q: 支持哪些数据类型？**  
A: 支持 JSON 序列化的所有类型（String, Number, Bool, Array, Dictionary）。

## 相关文件

- `WebKitBridge.swift` - 核心 OpenBridge 类
- `BridgeView.swift` - SwiftUI 视图包装
- `BridgeMessageHandler.swift` - 消息处理器
- `BridgeNavigationDelegate.swift` - 导航委托
- `ReadinessState.swift` - 就绪状态管理
