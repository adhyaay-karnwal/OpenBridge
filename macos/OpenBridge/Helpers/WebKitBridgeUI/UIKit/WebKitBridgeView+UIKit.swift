#if canImport(UIKit) && !os(watchOS)
    import UIKit
    import WebKit

    @MainActor
    final class WebKitBridgeView: UIView {
        let bridge: WebKitBridge

        init(
            frame: CGRect = .zero,
            configuration: WKWebViewConfiguration? = nil,
            handshakeMessageName: String = "openbridgeReady",
            handshakeCompletionValue: String = "complete"
        ) {
            bridge = WebKitBridge(
                frame: frame,
                configuration: configuration,
                handshakeMessageName: handshakeMessageName,
                handshakeCompletionValue: handshakeCompletionValue
            )
            super.init(frame: frame)
            setupWebView()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private func setupWebView() {
            addSubview(bridge.webView)
            bridge.webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bridge.webView.topAnchor.constraint(equalTo: topAnchor),
                bridge.webView.bottomAnchor.constraint(equalTo: bottomAnchor),
                bridge.webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                bridge.webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }
#endif
