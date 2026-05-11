import JSBridge
import SwiftUI
import WebKit

@MainActor
struct BridgeView {
    @State private var bridgeHolder: BridgeHolder = .init()
    private let frame: CGRect
    private let configuration: WKWebViewConfiguration
    private let handshakeMessageName: String
    private let handshakeCompletionValue: String
    private let url: URL?
    private let webViewFactory: ((CGRect, WKWebViewConfiguration) -> WKWebView)?

    private var onReadyCallback: (() -> Void)?
    private var bindings: [any JSBridge] = []

    init(
        frame: CGRect = .zero,
        configuration: WKWebViewConfiguration? = nil,
        handshakeMessageName: String = "openbridgeReady",
        handshakeCompletionValue: String = "complete",
        url: URL? = nil,
        webViewFactory: ((CGRect, WKWebViewConfiguration) -> WKWebView)? = nil,
        onReady: (() -> Void)? = nil,
        bindings: [any JSBridge] = []
    ) {
        let resolvedConfiguration = configuration ?? WKWebViewConfiguration()
        // enable developer extras for debugging
        #if DEBUG && os(macOS)
            resolvedConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        self.configuration = resolvedConfiguration
        self.frame = frame
        self.handshakeMessageName = handshakeMessageName
        self.handshakeCompletionValue = handshakeCompletionValue
        self.url = url
        self.webViewFactory = webViewFactory
        onReadyCallback = onReady
        self.bindings = bindings
    }

    class BridgeHolder {
        var bridge: WebKitBridge?
    }

    func createBridge() -> WebKitBridge {
        if let bridge = bridgeHolder.bridge {
            return bridge
        }

        let bridgeInstance = WebKitBridge(
            frame: frame,
            configuration: configuration,
            handshakeMessageName: handshakeMessageName,
            handshakeCompletionValue: handshakeCompletionValue,
            url: url,
            webViewFactory: webViewFactory
        )
        bridgeHolder.bridge = bridgeInstance
        return bridgeInstance
    }

    func configureBridge() {
        guard let bridge = bridgeHolder.bridge else {
            return
        }
        bridge.onReadyCallback = onReadyCallback
        for binding in bindings {
            bridge.bind(binding)
        }
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit

    extension BridgeView: NSViewRepresentable {
        func makeNSView(context _: Context) -> WKWebView {
            let bridge = createBridge()
            configureBridge()
            return bridge.webView
        }

        func updateNSView(_: WKWebView, context _: Context) {
            configureBridge()
        }

        static func dismantleNSView(_ nsView: WKWebView, coordinator _: ()) {
            nsView.navigationDelegate = nil
            nsView.uiDelegate = nil
        }
    }
#endif

#if canImport(UIKit) && !os(watchOS)
    import UIKit

    extension BridgeView: UIViewRepresentable {
        func makeUIView(context _: Context) -> WKWebView {
            let bridge = createBridge()
            configureBridge()
            return bridge.webView
        }

        func updateUIView(_: WKWebView, context _: Context) {
            configureBridge()
        }

        static func dismantleUIView(_ uiView: WKWebView, coordinator _: ()) {
            uiView.navigationDelegate = nil
            uiView.uiDelegate = nil
        }
    }
#endif
