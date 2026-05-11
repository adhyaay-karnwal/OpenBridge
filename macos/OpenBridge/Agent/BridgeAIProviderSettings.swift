import Foundation
import KWWKAI

nonisolated enum BridgeAIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI = "openai"
    case openAIChatCompletions = "openai-chat-completions"
    case anthropic
    case googleGemini = "google-gemini"

    var id: String {
        rawValue
    }

    static var displayOrder: [BridgeAIProvider] {
        [.openAI, .anthropic, .googleGemini, .openAIChatCompletions]
    }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAIChatCompletions: "OpenAI Chat Completions"
        case .anthropic: "Anthropic"
        case .googleGemini: "Google Gemini"
        }
    }

    var iconName: String {
        switch self {
        case .openAI, .openAIChatCompletions: "sparkles"
        case .anthropic: "brain.head.profile"
        case .googleGemini: "diamond"
        }
    }

    var logoImageName: String {
        switch self {
        case .openAI, .openAIChatCompletions: "openai"
        case .anthropic: "claude"
        case .googleGemini: "google"
        }
    }

    var usesTemplateLogoRendering: Bool {
        switch self {
        case .openAI, .openAIChatCompletions: true
        case .anthropic, .googleGemini: false
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI, .openAIChatCompletions: "https://api.openai.com"
        case .anthropic: "https://api.anthropic.com"
        case .googleGemini: "https://generativelanguage.googleapis.com"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openAI, .openAIChatCompletions: "sk-..."
        case .anthropic: "sk-ant-..."
        case .googleGemini: "AIza..."
        }
    }

    var supportedAuthMethods: [BridgeAIProviderAuthMethod] {
        switch self {
        case .openAI, .anthropic:
            [.oauth, .apiKey]
        case .openAIChatCompletions:
            [.apiKey]
        case .googleGemini:
            [.apiKey]
        }
    }

    var defaultAuthMethod: BridgeAIProviderAuthMethod {
        supportedAuthMethods.first ?? .apiKey
    }

    var modelProviderIDs: Set<String> {
        switch self {
        case .openAI:
            ["chatgpt-codex", "openai", "openai-codex"]
        case .openAIChatCompletions:
            ["openai"]
        case .anthropic:
            ["anthropic"]
        case .googleGemini:
            ["google", "google-gemini", "google-gemini-cli", "google-antigravity", "google-vertex"]
        }
    }

    static func provider(for model: Model) -> BridgeAIProvider? {
        if model.provider == "openai", model.api == "openai-completions" {
            return .openAIChatCompletions
        }
        return allCases.first { $0.modelProviderIDs.contains(model.provider) }
    }
}

nonisolated enum BridgeAIProviderAuthMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case apiKey
    case oauth

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .apiKey: "API Key"
        case .oauth: "OAuth"
        }
    }
}

nonisolated struct BridgeAIProviderConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var authMethod: BridgeAIProviderAuthMethod
    var baseURL: String
    var oauthExpiresAt: Date?
    var oauthAccountID: String?

    init(
        isEnabled: Bool = false,
        authMethod: BridgeAIProviderAuthMethod = .oauth,
        baseURL: String = "",
        oauthExpiresAt: Date? = nil,
        oauthAccountID: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.authMethod = authMethod
        self.baseURL = baseURL
        self.oauthExpiresAt = oauthExpiresAt
        self.oauthAccountID = oauthAccountID
    }

    func resolvedBaseURL(for provider: BridgeAIProvider) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != provider.defaultBaseURL else { return nil }
        return trimmed
    }
}

nonisolated struct BridgeAIProviderSettings: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case providers
        case selectedModelProvider
        case selectedModelID
    }

    var providers: [BridgeAIProvider: BridgeAIProviderConfig]
    var selectedModelProvider: String
    var selectedModelID: String

    init(
        providers: [BridgeAIProvider: BridgeAIProviderConfig] = [:],
        selectedModelProvider: String = "openai",
        selectedModelID: String = "gpt-5"
    ) {
        var configs = providers
        for provider in BridgeAIProvider.allCases {
            if configs[provider] == nil {
                configs[provider] = BridgeAIProviderConfig(
                    authMethod: provider.defaultAuthMethod,
                    baseURL: provider.defaultBaseURL
                )
            }
        }
        self.providers = configs
        self.selectedModelProvider = selectedModelProvider
        self.selectedModelID = selectedModelID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providers: container.decodeIfPresent(
                [BridgeAIProvider: BridgeAIProviderConfig].self,
                forKey: .providers
            ) ?? [:],
            selectedModelProvider: container.decodeIfPresent(String.self, forKey: .selectedModelProvider)
                ?? "openai",
            selectedModelID: container.decodeIfPresent(String.self, forKey: .selectedModelID)
                ?? "gpt-5"
        )
    }

    subscript(provider: BridgeAIProvider) -> BridgeAIProviderConfig {
        get {
            providers[provider] ?? BridgeAIProviderConfig(
                authMethod: provider.defaultAuthMethod,
                baseURL: provider.defaultBaseURL
            )
        }
        set { providers[provider] = newValue }
    }
}
