import Foundation
import JSBridge
import WebKit

@MainActor
final class WebKitBridgeController {
    let bridge: WebKitBridge

    init(url: URL, configuration: WKWebViewConfiguration? = nil, webViewFactory: ((CGRect, WKWebViewConfiguration) -> WKWebView)? = nil) {
        bridge = WebKitBridge(
            frame: .zero,
            configuration: configuration,
            url: url,
            webViewFactory: webViewFactory
        )
    }

    func registerMessageHandler(named name: String, handler: @escaping (Any) -> Void) {
        bridge.registerMessageHandler(named: name, handler: handler)
    }

    func load(url: URL) {
        bridge.loadURL(url: url)
    }

    func bind(_ binding: some JSBridge) {
        bridge.bind(binding)
    }
}
