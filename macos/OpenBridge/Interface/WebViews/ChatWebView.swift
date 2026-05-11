import SwiftUI

struct ChatWebView: View {
    @Environment(SettingsManager.self) private var settingsManager

    let messagesBridge: MessagesBridge
    let presentationMode: ChatPresentationMode?
    let utilsBridge = UtilsBridge()
    let onReady: () -> Void

    var body: some View {
        let url = resolvedURL
        BridgeView(
            frame: .zero,
            url: url,
            onReady: onReady,
            bindings: [messagesBridge, utilsBridge]
        )
        .id(url.absoluteString)
        .accessibilityIdentifier(AccessibilityID.Chat.messageWebViewHost)
        .overlay(UtilsBridgeHelperView(bridge: utilsBridge))
    }

    @MainActor
    private var resolvedURL: URL {
        _ = settingsManager.useChatDevServerInDebug
        let queryItems = presentationMode.map {
            [URLQueryItem(name: "presentation", value: $0.rawValue)]
        } ?? []

        return EmbeddedSurfaceURLResolver.url(for: .chat, queryItems: queryItems)
    }
}
