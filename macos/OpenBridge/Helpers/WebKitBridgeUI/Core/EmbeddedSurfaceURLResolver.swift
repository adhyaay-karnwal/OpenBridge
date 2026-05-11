import Foundation

enum EmbeddedSurface: String {
    case chat
    case preview

    var assetDirectory: String {
        switch self {
        case .chat:
            "ChatAssets"
        case .preview:
            "PreviewAssets"
        }
    }

    var devServerURL: URL {
        switch self {
        case .chat:
            URL(string: "http://localhost:8083")!
        case .preview:
            URL(string: "http://localhost:8085")!
        }
    }
}

enum EmbeddedSurfaceURLResolver {
    @MainActor
    static func url(for surface: EmbeddedSurface, queryItems: [URLQueryItem] = []) -> URL {
        #if DEBUG
            if shouldUseDevServer(for: surface) {
                return appendQueryItems(queryItems, to: surface.devServerURL)
            }
        #endif

        guard let htmlURL = Bundle.main.url(
            forResource: surface.rawValue,
            withExtension: "html",
            subdirectory: "WebKitBridgeResources/\(surface.assetDirectory)"
        ) else {
            fatalError("Failed to find \(surface.rawValue).html")
        }

        return appendQueryItems(queryItems, to: htmlURL)
    }

    private static func appendQueryItems(_ queryItems: [URLQueryItem], to url: URL) -> URL {
        guard !queryItems.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? url
    }

    #if DEBUG
        @MainActor
        private static func shouldUseDevServer(for surface: EmbeddedSurface) -> Bool {
            switch surface {
            case .chat:
                SettingsManager.shared.useChatDevServerInDebug
            case .preview:
                SettingsManager.shared.usePreviewDevServerInDebug
            }
        }
    #endif
}
