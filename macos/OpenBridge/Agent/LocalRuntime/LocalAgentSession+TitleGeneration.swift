import Foundation
import KWWKAI
import OSLog

private let titleGenerationPrompt = "Generate a concise title (3-8 words) for this conversation. Return ONLY the title, no quotes, no punctuation at the end, no explanation."
private let titleGenerationLogger = Logger(subsystem: Logger.loggingSubsystem, category: "TitleGeneration")

private actor LocalSessionTitleGenerationCoordinator {
    static let shared = LocalSessionTitleGenerationCoordinator()

    private var runningSessionIDs: Set<String> = []

    func begin(sessionID: String) -> Bool {
        runningSessionIDs.insert(sessionID).inserted
    }

    func finish(sessionID: String) {
        runningSessionIDs.remove(sessionID)
    }
}

extension LocalAgentSession {
    func scheduleTitleGenerationIfNeeded() {
        guard Self.shouldGenerateTitle(currentTitle: currentTitleForList) else { return }

        let parts = Self.titleConversationParts(from: historyMessages, limit: 6)
        guard !parts.isEmpty else { return }

        let conversationText = parts.joined(separator: "\n")
        let sessionID = sessionID
        titleGenerationLogger.debug("Scheduling title generation for session \(sessionID, privacy: .public)")

        Task { [weak self] in
            guard await LocalSessionTitleGenerationCoordinator.shared.begin(sessionID: sessionID) else { return }
            defer {
                Task {
                    await LocalSessionTitleGenerationCoordinator.shared.finish(sessionID: sessionID)
                }
            }

            guard let title = await Self.generateConversationTitle(
                conversationText: conversationText,
                sessionID: sessionID
            ) else {
                titleGenerationLogger.warning("Title generation produced no title for session \(sessionID, privacy: .public)")
                return
            }

            await MainActor.run {
                guard let self,
                      Self.shouldGenerateTitle(currentTitle: self.currentTitleForList)
                else {
                    return
                }
                titleGenerationLogger.notice("Applying generated title for session \(sessionID, privacy: .public): \(title, privacy: .public)")
                self.setLocalTitle(title)
            }
        }
    }

    static func titleConversationParts(
        from messages: [SessionHistoryMessage],
        limit: Int
    ) -> [String] {
        var parts: [String] = []

        for message in messages.reversed() {
            guard let part = titleConversationPart(from: message) else { continue }
            parts.append(part)
            if parts.count >= limit {
                break
            }
        }

        return parts.reversed()
    }

    private static func titleConversationPart(from message: SessionHistoryMessage) -> String? {
        guard message.type == "message" else { return nil }

        let role: String
        switch message.role {
        case "user":
            role = "user"
        case "assistant":
            role = "assistant"
        default:
            return nil
        }

        let text = message.content?
            .filter { $0.type == "text" }
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }

        return "\(role): \(text.truncatedForTitleContext(maxLength: 500))"
    }

    private static func shouldGenerateTitle(currentTitle: String) -> Bool {
        let normalized = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || normalized == String(localized: "New Chat")
    }

    private static func generateConversationTitle(
        conversationText: String,
        sessionID: String
    ) async -> String? {
        await BridgeAIProviderRegistry.registerProviders()
        let model = await BridgeAIProviderRegistry.selectedModel()
        let resolvedAuth = await BridgeAIProviderRegistry.authResolver()(model, sessionID)
        guard resolvedAuth?.token?.isEmpty == false else {
            titleGenerationLogger.warning("No auth resolved for title generation model \(model.provider, privacy: .public)/\(model.id, privacy: .public)")
            return nil
        }
        let context = Context(
            systemPrompt: titleGenerationPrompt,
            messages: [.user(UserMessage(text: conversationText))]
        )
        let options = StreamOptions(
            sessionId: "\(sessionID)-title",
            resolvedAuth: resolvedAuth
        )

        do {
            titleGenerationLogger.debug("Starting title generation with \(model.provider, privacy: .public)/\(model.id, privacy: .public) for session \(sessionID, privacy: .public)")
            let message = try await withTimeout(seconds: 30) {
                try await KWWKAI.complete(model: model, context: context, options: options)
            }
            guard message.stopReason != .error else {
                titleGenerationLogger.warning("Title generation model returned error stop reason for session \(sessionID, privacy: .public): \(message.errorMessage ?? "unknown", privacy: .public)")
                return nil
            }
            return sanitizeGeneratedTitle(message.titleText)
        } catch {
            titleGenerationLogger.warning("Title generation failed for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func sanitizeGeneratedTitle(_ rawTitle: String) -> String? {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ".。!！?？:：;；"))
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return title.truncatedForTitleContext(maxLength: 80)
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }

            guard let value = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return value
        }
    }
}

private extension AssistantMessage {
    var titleText: String {
        content.compactMap { block -> String? in
            if case let .text(content) = block {
                return content.text
            }
            return nil
        }.joined(separator: "\n")
    }
}

private extension String {
    func truncatedForTitleContext(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let index = index(startIndex, offsetBy: maxLength)
        return String(self[..<index]) + "..."
    }
}
