//
//  ChatViewModel.swift
//  OpenBridge
//
//  Created by EYHN on 2025/12/1.
//

import Combine
import ComposerEditor
import Foundation
import KeyboardShortcuts
import OSLog

@MainActor
@Observable
final class ChatViewModel {
    static let shared = ChatViewModel()

    struct AgentTemplateGroup {
        let provider: String
        let templates: [LocalAgentAvailableTemplate]
    }

    var chats: [String: Chat] = [:]
    private var availableAgentTemplates: [LocalAgentAvailableTemplate] = []
    private let logger: os.Logger = .ui

    /// Set of conversation IDs that are currently streaming
    private(set) var streamingConversationIds: Set<String> = []

    /// Latest known scroll offsets for each conversation in the current app session.
    private var conversationScrollCache: [String: Double] = [:]

    var hasAnyStreaming: Bool {
        !streamingConversationIds.isEmpty
    }

    /// Check if there's any streaming conversation excluding the specified one
    func hasBackgroundStreaming(excluding conversationId: String?) -> Bool {
        if let conversationId {
            return streamingConversationIds.contains(where: { $0 != conversationId })
        }
        return hasAnyStreaming
    }

    private func updateStreamingState(conversationId: String, isStreaming: Bool) {
        if isStreaming {
            streamingConversationIds.insert(conversationId)
        } else {
            streamingConversationIds.remove(conversationId)
        }
    }

    func cacheScrollPosition(conversationId: String, scrollTop: Double) {
        conversationScrollCache[conversationId] = max(0, scrollTop)
    }

    func cachedScrollPosition(for conversationId: String) -> Double? {
        conversationScrollCache[conversationId]
    }

    private init() {
        registerShortcut()
        Task {
            await refreshAvailableTemplates()
        }
    }

    private func registerShortcut() {
        GlobalShortcutManager.shared.register(
            GlobalShortcutManager.ShortcutFeature(
                key: "openChat",
                name: "Open Chat",
                description: "Open the chat panel to start messaging.",
                defaultShortcut: KeyboardShortcuts.Shortcut(.d, modifiers: [.command]),
                showInStatusMenu: true,
                iconSystemName: "message"
            ) {
                Windows.shared.open(.chat)
            }
        )
    }

    func openChat(conversationId: String?) async throws -> Chat {
        if let conversationId, let existingChat = chats[conversationId] {
            return existingChat
        }

        let session: LocalAgentSession = if let conversationId {
            try await AgentSessionManager.shared.loadSession(sessionId: conversationId)
        } else {
            try await AgentSessionManager.shared.createSession()
        }

        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            if conversationId == nil {
                _ = await AgentSessionManager.shared.deleteSessionIfPristine(sessionId: session.sessionID)
            }
            throw CancellationError()
        }

        let chatId = conversationId ?? session.sessionID
        let chat = Chat(conversationId: chatId, session: session)
        chats[chatId] = chat

        return chat
    }

    func removeChat(conversationId: String) {
        chats[conversationId]?.teardown()
        chats.removeValue(forKey: conversationId)
        updateStreamingState(conversationId: conversationId, isStreaming: false)
        conversationScrollCache.removeValue(forKey: conversationId)
    }

    var availableTemplateOverrides: [LocalAgentAvailableTemplate] {
        availableAgentTemplates
    }

    var groupedTemplateOverridesByProvider: [AgentTemplateGroup] {
        var orderedProviders: [String] = []
        var grouped: [String: [LocalAgentAvailableTemplate]] = [:]

        for template in availableTemplateOverrides {
            let provider = classifyTemplateGroup(template)
            if grouped[provider] == nil {
                orderedProviders.append(provider)
                grouped[provider] = []
            }
            grouped[provider]?.append(template)
        }

        var groups: [AgentTemplateGroup] = []
        groups.reserveCapacity(orderedProviders.count)
        for provider in orderedProviders {
            groups.append(
                AgentTemplateGroup(
                    provider: provider,
                    templates: grouped[provider] ?? []
                )
            )
        }
        return groups
    }

    func templateOverrideLabel(for template: LocalAgentAvailableTemplate) -> String {
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = template.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? template.templateId : trimmedName
        if trimmedModel.isEmpty || trimmedModel.caseInsensitiveCompare(title) == .orderedSame {
            return title
        }
        return "\(title) · \(trimmedModel)"
    }

    func refreshAvailableTemplates() async {
        availableAgentTemplates = []
        SettingsManager.shared.lastSelectedAgentTemplateID = ""
    }

    private func classifyTemplateGroup(_ template: LocalAgentAvailableTemplate) -> String {
        let provider = template.providerType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !provider.isEmpty {
            return displayNameForProvider(provider)
        }

        let modelName = template.model.split(separator: "/").last.map(String.init)?.lowercased()
            ?? template.name.lowercased()
        if modelName.hasPrefix("claude-") {
            return displayNameForProvider("anthropic")
        }
        if modelName.hasPrefix("gpt-") {
            return displayNameForProvider("openai")
        }
        if modelName.hasPrefix("gemini-") {
            return displayNameForProvider("gemini")
        }
        if modelName.hasPrefix("kimi-") {
            return displayNameForProvider("moonshot")
        }

        let fallbackProvider = template.model.split(separator: "/").first.map(String.init)?.lowercased() ?? "unknown"
        return displayNameForProvider(fallbackProvider)
    }

    private func displayNameForProvider(_ provider: String) -> String {
        switch provider {
        case "anthropic":
            "Anthropic"
        case "openai":
            "OpenAI"
        case "gemini":
            "Google"
        case "moonshot":
            "Moonshot"
        default:
            provider.capitalized
        }
    }

    @MainActor
    @Observable
    final class Chat {
        let conversationId: String
        let session: LocalAgentSession
        private(set) var currentTitle: String = ""
        private(set) var hasLoadedTitle: Bool = false

        var selectedSkill: Skill?
        private var titleDidChangeListeners: [UUID: @Sendable (String) -> Void] = [:]

        private let isStreamingSubject = PassthroughSubject<Bool, Never>()
        var isStreaming: Bool = false {
            didSet {
                isStreamingSubject.send(isStreaming)
                ChatViewModel.shared.updateStreamingState(conversationId: conversationId, isStreaming: isStreaming)
                if isStreaming {
                    followUp.cancel()
                }
            }
        }

        var isStreamingPublisher: AnyPublisher<Bool, Never> {
            isStreamingSubject.eraseToAnyPublisher()
        }

        var sendTask: Task<Void, Never>?
        let followUp: ChatFollowUpViewModel
        private let logger: os.Logger = .ui
        private var stopRequestCleanup: (@Sendable () -> Void)?

        init(conversationId: String, session: LocalAgentSession) {
            self.conversationId = conversationId
            self.session = session
            followUp = ChatFollowUpViewModel(session: session)

            session.onSessionStarted = { [weak self] in
                self?.isStreaming = true
            }
            session.onSessionFinished = { [weak self] state, error in
                self?.handleSessionFinished(state: state, error: error)
            }
            session.onTitleChanged = { [weak self] title in
                ConversationListViewController.shared.syncConversationTitle(
                    conversationId: conversationId,
                    title: title,
                    purpose: session.listPurpose,
                    createdAt: session.listCreatedAt,
                    updatedAt: session.listUpdatedAt
                )
                self?.updateTitle(title)
            }
            stopRequestCleanup = session.addStopRequestListener { [weak self] in
                Task { @MainActor [weak self] in
                    self?.prepareForStop()
                }
            }

            isStreaming = session.isProcessing
        }

        func addTitleDidChangeListener(_ listener: @escaping @Sendable (String) -> Void) -> @Sendable () -> Void {
            let id = UUID()
            titleDidChangeListeners[id] = listener
            return { [weak self] in
                Task { @MainActor [weak self] in
                    self?.titleDidChangeListeners.removeValue(forKey: id)
                }
            }
        }

        func loadTitleIfNeeded() async -> String? {
            if hasLoadedTitle {
                return currentTitle
            }

            let title: String
            do {
                title = try await session.getTitle()
            } catch {
                logger.warning("Failed to load session title: \(error.localizedDescription)")
                return nil
            }
            if hasLoadedTitle {
                return currentTitle
            }

            currentTitle = title
            hasLoadedTitle = true
            return title
        }

        func teardown() {
            stopRequestCleanup?()
            stopRequestCleanup = nil
        }

        @discardableResult
        func send(
            content: [SessionHistoryMessage.Content],
            reasoningEffort: String? = nil
        ) -> Bool {
            followUp.reset()

            let attachmentCount = content.count(where: { $0.type == "image" || $0.type == "file" })
            sendTask = Task {
                await sendTaskBody(
                    content: content,
                    reasoningEffort: reasoningEffort,
                    attachmentCount: attachmentCount
                )
            }

            return true
        }

        private func sendTaskBody(
            content: [SessionHistoryMessage.Content],
            reasoningEffort: String?,
            attachmentCount: Int
        ) async {
            let textLength = content.reduce(0) { $0 + ($1.text?.count ?? 0) }
            let historyMessageCountBeforeSend = session.historyMessages.count
            let isFreshChat = !session.historyMessages.contains(where: { $0.role == "user" })
            let sendRequestStart = Date()

            LocalAgentLogger.log(
                "chat.message.started", category: .chatService,
                data: [
                    "conversation.id": conversationId,
                    "message.length": textLength,
                    "message.has_attachments": attachmentCount > 0,
                    "message.attachment_count": attachmentCount,
                    "message.history_count_before_send": historyMessageCountBeforeSend,
                    "message.is_fresh_chat": isFreshChat,
                ]
            )

            do {
                // session.send() returns immediately (Go loop runs async).
                // isStreaming is driven by Go events:
                //   session.started  → isStreaming = true
                //   session.finished → isStreaming = false
                try await session.send(
                    content: content,
                    reasoningEffort: reasoningEffort ?? ""
                )

                LocalAgentLogger.log(
                    "chat.message.completed", category: .chatService,
                    data: [
                        "conversation.id": conversationId,
                        "message.history_count_before_send": historyMessageCountBeforeSend,
                        "message.is_fresh_chat": isFreshChat,
                        "message.send_request_ms": max(0, Int((Date().timeIntervalSince(sendRequestStart) * 1000).rounded())),
                    ]
                )

            } catch is CancellationError {
                return
            } catch {
                logger.warning("Failed to send message: \(error.localizedDescription)")
                LocalAgentLogger.log(
                    "chat.message.failed", category: .chatService, severity: .error,
                    data: [
                        "conversation.id": conversationId,
                        "message.history_count_before_send": historyMessageCountBeforeSend,
                        "message.is_fresh_chat": isFreshChat,
                        "message.send_request_ms": max(0, Int((Date().timeIntervalSince(sendRequestStart) * 1000).rounded())),
                        "error": error.localizedDescription,
                    ]
                )
                return
            }
        }

        private func updateTitle(_ title: String) {
            currentTitle = title
            hasLoadedTitle = true
            for listener in titleDidChangeListeners.values {
                listener(title)
            }
        }

        private func handleSessionFinished(state: String, error _: String?) {
            guard isStreaming else { return }
            isStreaming = false
            _ = state
        }

        private func prepareForStop() {
            sendTask?.cancel()
            isStreaming = false
            followUp.cancel()
        }

        func cancel() {
            session.requestStop()
        }
    }
}
