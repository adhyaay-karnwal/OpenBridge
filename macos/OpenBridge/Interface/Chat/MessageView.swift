import Combine
import ComposerEditor
import SwiftUI

struct MessageView: View {
    let messagesBridge: MessagesBridge
    let chatPresentationMode: ChatPresentationMode?
    private let editorViewModel: ChatEditorViewModel
    private let paddingTop: CGFloat
    @State private var historyEventRemover: (@Sendable () -> Void)?
    @State private var isWebViewReady: Bool = false

    init(
        editorViewModel: ChatEditorViewModel,
        messagesBridge: MessagesBridge,
        chatPresentationMode: ChatPresentationMode? = .panel,
        paddingTop: CGFloat = 0
    ) {
        self.editorViewModel = editorViewModel
        self.messagesBridge = messagesBridge
        self.chatPresentationMode = chatPresentationMode
        self.paddingTop = paddingTop
    }

    var body: some View {
        ZStack {
            webViewLayer
            loadingLayer
            errorLayer
            stateObservers
        }
    }

    // MARK: - Layers

    private var webViewLayer: some View {
        ChatWebView(
            messagesBridge: messagesBridge,
            presentationMode: chatPresentationMode,
            onReady: handleWebViewReady
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .id(editorViewModel.chat?.conversationId ?? "none")
        .accessibilityIdentifier(AccessibilityID.Chat.messageContainer)
        .opacity(editorViewModel.isLoading || editorViewModel.error != nil || !isWebViewReady ? 0 : 1)
    }

    @ViewBuilder
    private var loadingLayer: some View {
        if editorViewModel.isLoading {
            AnimatedLogo(config: loadingLogoConfig)
                .frame(width: 56, height: 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
        }
    }

    @ViewBuilder
    private var errorLayer: some View {
        if let error = editorViewModel.error {
            MessageErrorView(error: error) {
                editorViewModel.reset()
            }
        }
    }

    private var stateObservers: some View {
        Rectangle()
            .hidden()
            .frame(height: 0)
            .onChange(of: editorViewModel.isStreaming, initial: true) { _, isStreaming in
                messagesBridge.isStreaming(isStreaming)
            }
            .onChange(of: editorViewModel.chat?.session.hasOpenTask, initial: true) { _, hasOpenTask in
                messagesBridge.hasOpenTask(hasOpenTask ?? false)
            }
            .onChange(of: editorViewModel.chat?.session.workspaceState) { _, workspaceState in
                handleWorkspaceStateChange(workspaceState)
            }
            .onChange(of: editorViewModel.chat?.session.assistantState) { _, assistantState in
                handleAssistantStateChange(assistantState)
            }
            .onChange(of: editorViewModel.chat?.followUp.followUpItems) { _, _ in
                syncFollowUpState()
            }
            .onChange(of: editorViewModel.chat?.followUp.isGenerating) { _, _ in
                syncFollowUpState()
            }
            .onReceive(ContinueInChatManager.shared.submissionPublisher.eraseToAnyPublisher()) {
                submission in
                editorViewModel.sendMessage(submission: submission)
            }
            .onReceive(ContinueInChatManager.shared.conversationPublisher.eraseToAnyPublisher()) {
                request in
                editorViewModel.openConversation(
                    request.conversationId,
                    focusMessageId: request.messageId
                )
            }
            .onReceive(ContinueInChatManager.shared.populatePublisher.eraseToAnyPublisher()) {
                submission in
                editorViewModel.populateFromSubmission(submission)
            }
            .onReceive(ContinueInChatManager.shared.attachmentURLsPublisher.eraseToAnyPublisher()) {
                urls in
                editorViewModel.addFileURLs(urls, source: .menu)
                editorViewModel.isFocused = true
            }
            .onChange(of: editorViewModel.chat?.conversationId) { _, _ in
                isWebViewReady = false
                setupHistoryListener()
            }
            .onChange(of: editorViewModel.pendingFocusQuoteRequest) { _, request in
                guard isWebViewReady, let request else { return }
                messagesBridge.focusQuote(
                    .init(
                        quoteRef: request.quoteRef,
                        requestId: request.requestId
                    )
                )
                editorViewModel.pendingFocusQuoteRequest = nil
            }
            .onChange(of: paddingTop, initial: true) { _, paddingTop in
                guard isWebViewReady, paddingTop > 0 else { return }
                messagesBridge.paddingTop(paddingTop)
            }
    }

    // MARK: - State Handlers

    private func handleWorkspaceStateChange(_ workspaceState: WorkspaceState?) {
        messagesBridge.workspaceState(workspaceState)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            messagesBridge.workspaceState(workspaceState)
            try? await Task.sleep(for: .milliseconds(800))
            messagesBridge.workspaceState(workspaceState)
        }
    }

    private var loadingLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .secondary.opacity(0.38)
        config.strokeWidth = 3.8
        config.enterDrawDuration = 1.15
        config.enterMoveDuration = 1.15
        config.waitDuration = 0.25
        config.exitDrawDuration = 0.75
        config.exitMoveDuration = 0.75
        config.loopInterval = 0.15
        return config
    }

    private func handleAssistantStateChange(_ assistantState: AssistantState?) {
        messagesBridge.assistantState(assistantState)
    }

    private func syncFollowUpState() {
        messagesBridge.followUpState(
            FollowUpState(
                items: editorViewModel.chat?.followUp.followUpItems ?? [],
                isGenerating: editorViewModel.chat?.followUp.isGenerating ?? false
            )
        )
    }

    private func syncSchedules() {
        messagesBridge.schedules(messagesBridge.getSchedules())
    }

    private func setupHistoryListener() {
        // Remove old listener
        historyEventRemover?()
        historyEventRemover = nil

        guard let session = editorViewModel.chat?.session else { return }

        historyEventRemover = session.addHistoryEventListener { event in
            Task { @MainActor in
                switch event {
                case let .added(message):
                    messagesBridge.historyMessageAdded(message)
                case let .reset(messages):
                    messagesBridge.historyInit(
                        .init(messages: messages, scrollTop: nil)
                    )
                case let .workspaceStateChanged(workspaceState):
                    handleWorkspaceStateChange(workspaceState)
                }
            }
        }
    }

    private func handleWebViewReady() {
        isWebViewReady = true
        syncSchedules()

        if paddingTop > 0 {
            messagesBridge.paddingTop(paddingTop)
        }

        guard let chat = editorViewModel.chat else {
            messagesBridge.hasOpenTask(false)
            messagesBridge.workspaceState(nil)
            messagesBridge.assistantState(nil)
            messagesBridge.historyInit(.init(messages: [], scrollTop: nil))
            messagesBridge.followUpState(FollowUpState(items: [], isGenerating: false))
            return
        }

        // Sync streaming state
        messagesBridge.isStreaming(chat.isStreaming)
        messagesBridge.hasOpenTask(chat.session.hasOpenTask)
        messagesBridge.assistantState(chat.session.assistantState)

        // Send full history
        messagesBridge.historyInit(
            .init(
                messages: chat.session.historyMessages,
                scrollTop: ChatViewModel.shared.cachedScrollPosition(
                    for: chat.conversationId
                )
            )
        )

        // Send workspace state
        messagesBridge.workspaceState(chat.session.workspaceState)

        // Set up history event listener
        setupHistoryListener()

        if let messageId = editorViewModel.pendingFocusMessageId {
            messagesBridge.focusMessage(messageId)
            editorViewModel.pendingFocusMessageId = nil
        }

        if let request = editorViewModel.pendingFocusQuoteRequest {
            messagesBridge.focusQuote(
                .init(
                    quoteRef: request.quoteRef,
                    requestId: request.requestId
                )
            )
            editorViewModel.pendingFocusQuoteRequest = nil
        }

        // Send initial follow-up state
        messagesBridge.followUpState(
            FollowUpState(
                items: chat.followUp.followUpItems,
                isGenerating: chat.followUp.isGenerating
            )
        )
    }
}
