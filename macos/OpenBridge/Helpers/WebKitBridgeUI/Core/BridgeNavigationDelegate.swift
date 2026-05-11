import WebKit

final class BridgeNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var owner: WebKitBridge?

    func webView(
        _: WKWebView,
        didStartProvisionalNavigation _: WKNavigation!
    ) {
        owner?.handleNavigationDidStart()
    }

    func webView(
        _: WKWebView,
        didFinish _: WKNavigation!
    ) {
        owner?.handleNavigationDidFinish()
    }
}
