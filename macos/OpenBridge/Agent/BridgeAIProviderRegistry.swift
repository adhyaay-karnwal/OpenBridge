import Foundation
import KWWKAI

enum BridgeAIProviderRegistry {
    private static let sourceId = "bridge-ai"

    static func registerProviders() async {
        await APIRegistry.shared.unregisterSource(sourceId)
        var settings = await BridgeAIProviderSecretStore.readSettings()
        let anthropicConfig = settings[.anthropic]
        if anthropicConfig.authMethod == .oauth {
            await APIRegistry.shared.register(ProviderVariants.anthropicOAuth(accessToken: nil), sourceId: sourceId)
        } else {
            await APIRegistry.shared.register(AnthropicProvider(defaultAPIKey: nil), sourceId: sourceId)
        }
        await APIRegistry.shared.register(OpenAICompletionsProvider(defaultAPIKey: nil), sourceId: sourceId)
        await APIRegistry.shared.register(OpenAIResponsesProvider(defaultAPIKey: nil), sourceId: sourceId)
        var openAIConfig = settings[.openAI]
        if openAIConfig.oauthAccountID == nil {
            let access = await BridgeAIProviderSecretStore.readSecret(for: .openAI, kind: .oauthAccessToken)
            openAIConfig.oauthAccountID = openAIAccountID(fromJWT: access)
            settings[.openAI] = openAIConfig
            try? await BridgeAIProviderSecretStore.saveSettings(settings)
        }
        await APIRegistry.shared.register(ProviderVariants.chatgptCodex(
            accessToken: nil,
            accountId: openAIConfig.oauthAccountID,
            originator: "bridge"
        ), sourceId: sourceId)
        await APIRegistry.shared.register(GoogleGeminiProvider(defaultAPIKey: nil), sourceId: sourceId)
    }

    static func defaultModel() -> Model {
        ModelsCatalog.model(provider: "openai", id: "gpt-5") ?? availableModels().first ?? Models.gpt5
    }

    static func defaultModel(settings: BridgeAIProviderSettings) -> Model {
        availableModels(settings: settings).first ?? defaultModel()
    }

    static func selectedModel() async -> Model {
        let settings = await BridgeAIProviderSecretStore.readSettings()
        return runtimeModel(
            provider: settings.selectedModelProvider,
            id: settings.selectedModelID,
            settings: settings
        ) ?? defaultModel(settings: settings)
    }

    static func runtimeModel(provider: String, id: String) async -> Model? {
        let settings = await BridgeAIProviderSecretStore.readSettings()
        return runtimeModel(provider: provider, id: id, settings: settings)
    }

    static func availableModels() -> [Model] {
        let supportedAPIs: Set = [
            "anthropic-messages",
            "google-generative-ai",
            "openai-codex-responses",
            "openai-responses",
        ]
        return ModelsCatalog.all
            .filter { supportedAPIs.contains($0.api) }
            .sorted { lhs, rhs in
                let left = "\(lhs.provider)/\(lhs.name)"
                let right = "\(rhs.provider)/\(rhs.name)"
                return left.localizedStandardCompare(right) == .orderedAscending
            }
    }

    static func availableModels(settings: BridgeAIProviderSettings) -> [Model] {
        availableModels().filter { model in
            guard let provider = BridgeAIProvider.provider(for: model) else { return false }
            let config = settings[provider]
            guard config.isEnabled else { return false }
            if provider == .openAI {
                switch config.authMethod {
                case .oauth:
                    return model.provider == "openai-codex"
                case .apiKey:
                    return model.provider == "openai"
                }
            }
            return true
        }
    }

    static func displayModel(provider: String, id: String) -> Model? {
        ModelsCatalog.model(provider: provider, id: id)
    }

    static func availableModelsByProvider() -> [(provider: String, models: [Model])] {
        availableModelsByProvider(models: availableModels())
    }

    static func availableModelsByProvider(settings: BridgeAIProviderSettings) -> [(provider: String, models: [Model])] {
        availableModelsByProvider(models: availableModels(settings: settings))
    }

    private static func availableModelsByProvider(models: [Model]) -> [(provider: String, models: [Model])] {
        Dictionary(grouping: models, by: \.provider)
            .map { provider, models in
                (
                    provider: provider,
                    models: models.sorted { lhs, rhs in
                        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                lhs.provider.localizedStandardCompare(rhs.provider) == .orderedAscending
            }
    }

    static func authResolver() -> @Sendable (Model, String?) async -> ResolvedProviderAuth? {
        { model, sessionId in
            await resolveAuth(for: model, sessionId: sessionId)
        }
    }

    private static func resolveAuth(for model: Model, sessionId _: String?) async -> ResolvedProviderAuth? {
        guard let provider = BridgeAIProvider.provider(for: model) else { return nil }
        let config = await BridgeAIProviderSecretStore.readSettings()[provider]
        guard config.isEnabled else { return nil }

        let token = await resolvedToken(for: provider, config: config, model: model)
        guard !token.isEmpty else { return nil }

        var headers: [String: String] = [:]
        if provider == .anthropic, config.authMethod == .oauth {
            headers["anthropic-beta"] = "oauth-2025-04-20"
        }

        return ResolvedProviderAuth(
            token: token,
            scheme: authScheme(for: provider, method: config.authMethod),
            headers: headers,
            baseURL: config.resolvedBaseURL(for: provider)
        )
    }

    private static func runtimeModel(
        provider: String,
        id: String,
        settings: BridgeAIProviderSettings
    ) -> Model? {
        if provider == "openai-codex" || (provider == "openai" && settings[.openAI].authMethod == .oauth) {
            return codexRuntimeModel(id: id)
        }
        return ModelsCatalog.model(provider: provider, id: id)
    }

    private static func codexRuntimeModel(id: String) -> Model? {
        let catalog = ModelsCatalog.model(provider: "openai-codex", id: id)
        guard catalog != nil || ModelsCatalog.model(provider: "openai", id: id) != nil else { return nil }
        return Model(
            id: id,
            name: catalog?.name ?? id,
            api: "chatgpt-codex",
            provider: "chatgpt-codex",
            baseUrl: "https://chatgpt.com",
            reasoning: catalog?.reasoning ?? true,
            input: catalog?.input ?? [.text, .image],
            cost: catalog?.cost ?? .init(),
            contextWindow: catalog?.contextWindow ?? 272_000,
            maxTokens: 0,
            headers: catalog?.headers
        )
    }

    private static func authScheme(
        for provider: BridgeAIProvider,
        method: BridgeAIProviderAuthMethod
    ) -> AuthScheme {
        switch method {
        case .oauth:
            .bearer
        case .apiKey:
            switch provider {
            case .openAI:
                .bearer
            case .anthropic:
                .apiKeyHeader(name: "x-api-key")
            case .googleGemini:
                .queryKey(name: "key")
            }
        }
    }

    private static func resolvedToken(
        for provider: BridgeAIProvider,
        config: BridgeAIProviderConfig,
        model: Model
    ) async -> String {
        if config.authMethod == .apiKey {
            return await BridgeAIProviderSecretStore.readSecret(for: provider, kind: .apiKey)
        }

        let access = await BridgeAIProviderSecretStore.readSecret(for: provider, kind: .oauthAccessToken)
        let refresh = await BridgeAIProviderSecretStore.readSecret(for: provider, kind: .oauthRefreshToken)
        guard !refresh.isEmpty, config.oauthExpiresAt.map({ $0 <= Date() }) == true else {
            return access
        }
        guard let oauthProvider = oauthProvider(for: provider, model: model) else {
            return access
        }

        let credentials = OAuthCredentials(
            access: access,
            refresh: refresh,
            expires: Int64((config.oauthExpiresAt ?? Date()).timeIntervalSince1970 * 1000)
        )
        guard let refreshed = try? await oauthProvider.refresh(credentials, using: URLSessionHTTPClient()) else {
            return access
        }

        try? await BridgeAIProviderSecretStore.saveSecret(
            refreshed.access,
            for: provider,
            kind: .oauthAccessToken
        )
        try? await BridgeAIProviderSecretStore.saveSecret(
            refreshed.refresh,
            for: provider,
            kind: .oauthRefreshToken
        )
        var settings = await BridgeAIProviderSecretStore.readSettings()
        var nextConfig = settings[provider]
        nextConfig.oauthExpiresAt = Date(timeIntervalSince1970: Double(refreshed.expires) / 1000)
        if provider == .openAI {
            nextConfig.oauthAccountID = Self.openAIAccountID(fromJWT: refreshed.access)
        }
        settings[provider] = nextConfig
        try? await BridgeAIProviderSecretStore.saveSettings(settings)
        return refreshed.access
    }

    static func openAIAccountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        let base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = obj["https://api.openai.com/auth"] as? [String: Any],
              let accountID = auth["chatgpt_account_id"] as? String
        else {
            return nil
        }
        return accountID
    }

    private static func oauthProvider(
        for provider: BridgeAIProvider,
        model _: Model
    ) -> (any OAuthProvider)? {
        switch provider {
        case .openAI:
            OpenAICodexOAuthProvider()
        case .anthropic:
            AnthropicOAuthProvider()
        case .googleGemini:
            nil
        }
    }
}
