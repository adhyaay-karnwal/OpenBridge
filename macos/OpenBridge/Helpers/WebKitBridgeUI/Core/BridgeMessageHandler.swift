import WebKit

final class BridgeMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebKitBridge?

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        owner?.process(message: message)
    }
}
