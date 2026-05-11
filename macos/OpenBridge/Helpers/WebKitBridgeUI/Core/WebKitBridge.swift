import CoreGraphics
import Foundation
import JSBridge
import WebKit

@MainActor
final class WebKitBridge: NSObject {
    let webView: WKWebView
    let userScriptController: WKUserContentController

    var defaultMessageHandler: ((String, Any) -> Void)?

    private let handshakeMessageName: String
    private let handshakeCompletionValue: String
    private let legacyHandshakeMessageName = "bridgeReady"
    private let jsBridgeMessageName: String = "jsb"
    private let messageHandler: BridgeMessageHandler
    private let navigationDelegate: BridgeNavigationDelegate
    private let readinessState: ReadinessStateActor
    private let contextMenuBridge: ContextMenuBridge
    private let logger: Logger
    private var messageCallbacks: [String: MessageCallback]
    private var jsBridgeBindings: [String: any JSBridge]
    private var registeredMessageNames: Set<String>
    var onReadyCallback: (() -> Void)?

    private typealias MessageCallback = (Any) -> Void

    init(
        frame: CGRect = .zero,
        configuration providedConfiguration: WKWebViewConfiguration? = nil,
        handshakeMessageName: String = "openbridgeReady",
        handshakeCompletionValue: String = "complete",
        url: URL? = nil,
        webViewFactory: ((CGRect, WKWebViewConfiguration) -> WKWebView)? = nil,
        onReady: (() -> Void)? = nil
    ) {
        let configuration = providedConfiguration ?? WKWebViewConfiguration()

        self.handshakeMessageName = handshakeMessageName
        self.handshakeCompletionValue = handshakeCompletionValue
        messageHandler = BridgeMessageHandler()
        navigationDelegate = BridgeNavigationDelegate()
        readinessState = ReadinessStateActor()
        contextMenuBridge = ContextMenuBridge()
        messageCallbacks = [:]
        jsBridgeBindings = [:]
        registeredMessageNames = Set([handshakeMessageName, legacyHandshakeMessageName])
        onReadyCallback = onReady

        let controller = configuration.userContentController
        controller.add(messageHandler, name: handshakeMessageName)
        if legacyHandshakeMessageName != handshakeMessageName {
            controller.add(messageHandler, name: legacyHandshakeMessageName)
        }
        controller.add(messageHandler, name: "jsb")
        userScriptController = controller
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            webView = webViewFactory?(frame, configuration) ?? BridgeWKWebView(frame: frame, configuration: configuration)
        #else
            webView = webViewFactory?(frame, configuration) ?? WKWebView(frame: frame, configuration: configuration)
        #endif

        logger = Logger.bridge

        super.init()

        messageHandler.owner = self
        navigationDelegate.owner = self
        webView.navigationDelegate = navigationDelegate

        // make webview transparent
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.clipsToBounds = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        updateInspectable()
        bind(contextMenuBridge)

        if let url {
            loadURL(url: url)
        } else {
            loadDefaultHTML()
        }
    }

    func updateInspectable() {
        #if DEBUG
            webView.isInspectable = true
        #else
            webView.isInspectable = LocalFeatureFlagManager.shared.isEnabled(.webviewDevTool)
        #endif
    }

    func loadURL(url: URL) {
        if url.scheme == "http" || url.scheme == "https" {
            webView.load(URLRequest(url: url))
        } else {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func loadDefaultHTML() {
        guard let htmlURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WebKitBridgeResources"
        ) else {
            logger.error("Failed to find default HTML resource")
            assertionFailure()
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    deinit {
        let names = registeredMessageNames
        let controller = userScriptController
        let view = webView
        Task { @MainActor [names, controller, view] in
            for name in names {
                controller.removeScriptMessageHandler(forName: name)
            }
            view.navigationDelegate = nil
        }
    }

    /// Bind a JSBridge (registers for JS → Swift calls)
    func bind(_ binding: some JSBridge) {
        var mutableBinding = binding
        mutableBinding.evaluator = { [weak self] script in
            let bridge = self
            _ = try await bridge?.webView.evaluateJavaScriptAsync(script)
        }
        if let webViewAwareBinding = mutableBinding as? WebViewAwareJSBridge {
            webViewAwareBinding.attachWebView(webView)
        }
        jsBridgeBindings[binding.name] = mutableBinding
    }

    func unbind(_ name: String) {
        jsBridgeBindings.removeValue(forKey: name)
    }

    func registerMessageHandler(named name: String, handler: @escaping (Any) -> Void) {
        messageCallbacks[name] = handler
        registerScriptMessageHandlerIfNeeded(named: name)
    }

    func removeMessageHandler(named name: String) {
        messageCallbacks.removeValue(forKey: name)
    }

    func messageHandler(for name: String) -> ((Any) -> Void)? {
        messageCallbacks[name]
    }

    func waitUntilReady(timeout: TimeInterval) async throws {
        if await readinessState.isReady() {
            return
        }

        let normalizedTimeout = max(0, timeout)
        guard normalizedTimeout > 0 else {
            throw WebKitBridgeError.readinessTimedOut(timeout)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [readinessState] in
                do {
                    try await readinessState.waitForReady()
                } catch is CancellationError {
                    return
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw WebKitBridgeError.readinessTimedOut(timeout)
            }

            try await group.next()
            group.cancelAll()
        }
    }

    func isReady() async -> Bool {
        await readinessState.isReady()
    }

    nonisolated func handleNavigationDidStart() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await readinessState.reset()
        }
    }

    nonisolated func handleNavigationDidFinish() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await readinessState.markNavigationCompleted()
        }
    }

    nonisolated func process(message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let name = message.name
            let body = message.body

            if name == handshakeMessageName || name == legacyHandshakeMessageName,
               let bodyString = body as? String,
               bodyString == handshakeCompletionValue
            {
                await readinessState.markHandshakeCompleted()
                onReadyCallback?()
            } else if name == jsBridgeMessageName {
                do {
                    try await processJsBridgeMessage(body: body)
                } catch {
                    logger.error("Failed to process JS bridge message: \(error.localizedDescription)")
                }
            } else {
                let handler = messageHandler(for: name)
                handler?(body)
                defaultMessageHandler?(name, body)
            }
        }
    }

    private func processJsBridgeMessage(body: Any) async throws {
        guard let bodyArray = body as? [Any],
              bodyArray.count == 4,
              let callId = bodyArray[0] as? String,
              let bridgeName = bodyArray[1] as? String,
              let method = bodyArray[2] as? String,
              let args = bodyArray[3] as? String
        else {
            return
        }
        let binding = jsBridgeBindings[bridgeName]
        guard let binding else {
            try await executeJsBridgeCallback(callId: callId, success: false, ret: "Unknown bridge name: \(bridgeName)")
            return
        }
        Task { @MainActor in
            do {
                let result = try await binding.jsBridgeCall(name: method, args: args)
                try await executeJsBridgeCallback(callId: callId, success: true, ret: result)
            } catch {
                try await executeJsBridgeCallback(callId: callId, success: false, ret: error.localizedDescription)
                return
            }
        }
    }

    private func executeJsBridgeCallback(callId: String, success: Bool, ret: String?) async throws {
        struct JsBridgeCallbackData: Encodable {
            let callId: String
            let success: Bool
            let ret: String?
        }
        let data = JsBridgeCallbackData(callId: callId, success: success, ret: ret)
        let jsonData = try JSONEncoder().encode(data)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to encode JSON data")
            return
        }
        try await webView.evaluateJavaScript(
            """
            __jsbCallback__(\(jsonString))
            """
        )
    }

    private func registerScriptMessageHandlerIfNeeded(named name: String) {
        guard name != handshakeMessageName, name != legacyHandshakeMessageName else { return }
        if registeredMessageNames.insert(name).inserted {
            userScriptController.add(messageHandler, name: name)
        }
    }
}
