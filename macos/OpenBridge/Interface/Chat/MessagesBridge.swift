import AppKit
import Combine
import Foundation
import JSBridge
import Observation
import OSLog
import WebKit

private let logger = Logger(subsystem: "openbridge", category: "MessagesBridge")

private func routePathAndQuery(for source: String) -> (path: String, query: String?)? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("/") {
        if let queryIndex = trimmed.firstIndex(of: "?") {
            return (
                path: String(trimmed[..<queryIndex]),
                query: String(trimmed[trimmed.index(after: queryIndex)...])
            )
        }
        return (path: trimmed, query: nil)
    }

    guard let url = URL(string: trimmed),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
        return nil
    }

    return (path: components.path, query: components.percentEncodedQuery)
}

private func route(for source: String, prefix: String) -> String? {
    guard let components = routePathAndQuery(for: source),
          components.path.hasPrefix(prefix)
    else {
        return nil
    }

    if let query = components.query, !query.isEmpty {
        return "\(components.path)?\(query)"
    }
    return components.path
}

private func agentFileRoute(for source: String) -> String? {
    route(for: source, prefix: "/v1/user/agent/files/")
}

private func legacyAgentFilePath(for source: String) -> String? {
    guard let route = agentFileRoute(for: source) else { return nil }
    let path = String(route.dropFirst("/v1/user/agent/files".count))
    return path.isEmpty ? nil : path
}

private func storageObjectID(for source: String) -> String? {
    guard let components = routePathAndQuery(for: source),
          components.path.hasPrefix("/v1/storage/")
    else {
        return nil
    }

    let objectID = String(components.path.dropFirst("/v1/storage/".count))
    return objectID.isEmpty ? nil : objectID
}

// MARK: - Data Types

/// Follow-up state for JS bridge
@JSBridgeType
struct FollowUpState: Codable {
    let items: [FollowUpItem]
    let isGenerating: Bool
}

@JSBridgeType
struct ScheduleCard: Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let hasError: Bool
    let isPaused: Bool
    let isDeleted: Bool
    let willTriggerAgain: Bool
}

private func currentScheduleCards() -> [ScheduleCard] {
    ScheduleStore.shared.definitions.map { definition in
        ScheduleCard(
            id: definition.id,
            title: definition.displayTitle,
            subtitle: definition.detailText,
            hasError: definition.hasError,
            isPaused: definition.isPaused,
            isDeleted: definition.isDeleted,
            willTriggerAgain: definition.willTriggerAgain
        )
    }
}

@JSBridgeType
struct ChatHistoryInitPayload: Codable {
    let messages: [SessionHistoryMessage]
    let scrollTop: Double?
}

@JSBridgeType
struct WebViewPreviewSourceRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

@JSBridgeType
struct ConversationSearchResult: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let conversationTitle: String
    let messageId: String
    let role: String
    let createdAt: Double
    let snippet: String
    let score: Double
}

@JSBridgeType
struct ComposerQuotePayload: Codable, Equatable {
    let text: String
    let quoteRef: SessionHistoryMessage.QuoteReference
}

@JSBridgeType
struct QuoteFocusEvent: Codable, Equatable {
    let quoteRef: SessionHistoryMessage.QuoteReference
    let requestId: Int
}

private struct QuickLookPreviewTransition {
    let sourceFrameOnScreen: CGRect
    let transitionImage: NSImage?
}

private extension SessionHistoryMessage {
    var searchableText: String {
        var parts: [String] = []
        parts.append(contentsOf: content?.compactMap(\.text) ?? [])
        if let taskTitle {
            parts.append(taskTitle)
        }
        if let error {
            parts.append(error)
        }
        if let questionText = question?.question {
            parts.append(questionText)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - MessagesBridge (Bidirectional JS ↔ Swift)

/// OpenBridge for chat WebView bidirectional communication
@MainActor
@JSBridge
class MessagesBridge {
    let chatEditorViewModel: ChatEditorViewModel
    let attachmentPreviewStore = ChatAttachmentPreviewStore()
    private let recentSessionsBinder = RecentSessionsBridgeBinder()
    private var scheduleChangeCancellable: AnyCancellable?
    private weak var webView: WKWebView?

    init(chatEditorViewModel: ChatEditorViewModel) {
        self.chatEditorViewModel = chatEditorViewModel
        scheduleChangeCancellable = ScheduleStore.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                schedules(getSchedules())
            }
        recentSessionsBinder.start(bridge: self)
    }

    func getSchedules() -> [ScheduleCard] {
        currentScheduleCards()
    }

    private static func snippet(in text: String, query: String, radius: Int = 80) -> String {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(radius * 2))
        }

        let lowerBound = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upperBound = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lowerBound ..< upperBound])
    }

    // MARK: - JS → Swift methods

    /// Get file icon/thumbnail as data URL
    func getFileIcon(_ path: String) async -> String? {
        let fileURL = URL(fileURLWithPath: path)
        return await FileProcessor.shared.generateThumbnailDataURL(for: fileURL)
    }

    /// Directories from which local image reads are permitted.
    private static var allowedImageDirectories: [URL] {
        [
            Constant.imagesDirectoryURL,
            TempImageStorage.shared.directoryURL,
        ]
    }

    /// Only files inside known image directories are served to prevent
    /// the WebView from reading arbitrary local files.
    func getLocalImageDataURL(_ path: String) async -> String? {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        let filePath = fileURL.path

        let isAllowed = Self.allowedImageDirectories.contains { dir in
            let dirPath = dir.standardizedFileURL.path
            return filePath == dirPath || filePath.hasPrefix(dirPath + "/")
        }
        guard isAllowed else {
            return nil
        }

        guard let mimeType = fileURL.detectedMimeType(),
              mimeType.hasPrefix("image/"),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return data.dataURL(mimeType: mimeType)
    }

    func revealInFinder(_ path: [String]) async throws {
        let fileURLs = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
    }

    /// Open a folder in Finder without selecting any files
    func openFolder(_ path: String) async throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.open(url)
    }

    /// Preview a workspace file in OpenBridge's preview window.
    func previewWorkspaceFile(
        _ path: String,
        environmentId: String,
        sourceRect: WebViewPreviewSourceRect?
    ) async throws {
        guard let session = chatEditorViewModel.chat?.session else {
            throw RuntimeError(localized: "No active session")
        }
        let tempPath = try await session.getWorkspaceFileForPreview(path: path, environmentID: environmentId)
        let tempURL = URL(fileURLWithPath: tempPath)
        let quickLookTransition = quickLookPreviewTransition(for: sourceRect)
        FilePreviewWindowController.shared.show(
            fileURL: tempURL,
            title: tempURL.lastPathComponent,
            quickLookSourceFrameOnScreen: quickLookTransition?.sourceFrameOnScreen,
            quickLookTransitionImage: quickLookTransition?.transitionImage
        )
    }

    /// Preview a host file (already accepted) in OpenBridge's preview window.
    func previewHostFile(_ relPath: String, sourceRect: WebViewPreviewSourceRect?) async throws {
        let resolvedPath = (relPath.hasPrefix("/") || relPath.hasPrefix("~"))
            ? (relPath as NSString).expandingTildeInPath
            : ("~/" + relPath as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: resolvedPath)
        let quickLookTransition = quickLookPreviewTransition(for: sourceRect)
        FilePreviewWindowController.shared.show(
            fileURL: fileURL,
            title: fileURL.lastPathComponent,
            quickLookSourceFrameOnScreen: quickLookTransition?.sourceFrameOnScreen,
            quickLookTransitionImage: quickLookTransition?.transitionImage
        )
    }

    func previewAttachment(
        _ source: String,
        fileName: String?,
        mimeType: String?,
        sourceRect: WebViewPreviewSourceRect?
    ) async throws {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw RuntimeError(localized: "Preview source is empty")
        }

        let fileURL = try await attachmentPreviewStore.fileURL(
            source: trimmedSource,
            fileName: fileName,
            mimeType: mimeType
        )
        let quickLookTransition = quickLookPreviewTransition(for: sourceRect)
        FilePreviewWindowController.shared.show(
            fileURL: fileURL,
            title: fileName ?? fileURL.lastPathComponent,
            quickLookSourceFrameOnScreen: quickLookTransition?.sourceFrameOnScreen,
            quickLookTransitionImage: quickLookTransition?.transitionImage
        )
    }

    func prepareAttachmentPreview(_ source: String, fileName: String?, mimeType: String?) async throws {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return }
        try await attachmentPreviewStore.prepare(
            source: trimmedSource,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func clearAttachmentPreviews() async {
        await attachmentPreviewStore.clear()
    }

    /// Check if files/folders exist at the given paths
    func checkFilesExist(_ paths: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        let fileManager = FileManager.default
        for path in paths {
            let expandedPath = (path as NSString).expandingTildeInPath
            result[path] = fileManager.fileExists(atPath: expandedPath)
        }
        return result
    }

    /// Cancel the running session
    func cancelTask(_: String) async throws {
        guard let chat = chatEditorViewModel.chat else {
            throw RuntimeError(localized: "No active chat")
        }
        chat.cancel()
    }

    func acceptFiles(_ paths: [String], environmentId: String) async throws {
        AnalyticsManager.track(.init(do: .agentFilesAccepted(fileCount: paths.count), at: .chat))
        guard let chat = chatEditorViewModel.chat else {
            throw RuntimeError(localized: "No active chat")
        }
        try await chat.session.acceptFiles(paths, environmentID: environmentId)
    }

    func discardAllChanges(_ environmentId: String) async throws {
        AnalyticsManager.track(.init(do: .agentFilesDiscarded(fileCount: 0), at: .chat))
        guard let chat = chatEditorViewModel.chat else {
            throw RuntimeError(localized: "No active chat")
        }
        try await chat.session.discardAllChanges(environmentID: environmentId)
    }

    func getWorkspaceState() async -> WorkspaceState? {
        chatEditorViewModel.chat?.session.workspaceState
    }

    /// Request any missing OpenBridge app TCC permissions required by Computer Use.
    func openComputerUsePermissionFlow() async throws {
        for pane in ComputerUsePermissionService.status() where !pane.granted {
            _ = try ComputerUsePermissionService.request(pane.pane)
        }
    }

    func requestComputerUsePermission(_ pane: String) async throws -> [SessionHistoryMessage.ComputerUsePermissionPane] {
        try ComputerUsePermissionService.request(pane)
    }

    /// Fetch OpenBridge app TCC status. The chat permission card polls this
    /// after the user grants in System Settings so the allow button appears
    /// without waiting for the agent to retry.
    func getComputerUsePermissionsStatus() async throws -> [SessionHistoryMessage.ComputerUsePermissionPane] {
        ComputerUsePermissionService.status()
    }

    /// Reply to a user interaction. Handles runtime confirmation replies.
    /// The reply JSON may carry an optional `mode` string when the card was a
    /// ComputerUse mode picker.
    func replyInteraction(_ confirmationId: String, replyJSON: String) async throws {
        guard let data = replyJSON.data(using: .utf8),
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let approved = reply["approved"] as? Bool
        else {
            throw RuntimeError(localized: "Invalid reply format")
        }
        let mode = reply["mode"] as? String

        if let session = chatEditorViewModel.chat?.session,
           session.canResolveLocalConfirmation(id: confirmationId)
        {
            session.resolveLocalConfirmation(id: confirmationId, approved: approved, mode: mode)
            return
        }

        if AgentSessionManager.shared.resolveConnectorConfirmation(id: confirmationId, approved: approved, mode: mode) {
            return
        }

        throw RuntimeError(localized: "Unknown confirmation: \(confirmationId)")
    }

    /// Save an agent file from the VM to the host file system.
    func saveRemoteFile(_: String) async throws {
        throw RuntimeError(localized: "File save is not available in this local agent mode")
    }

    /// Send a message with the given text
    func sendMessage(_ text: String) {
        let submission = ChatEditorViewModel.Submission(
            text: text,
            attachments: [],
            quote: nil,
            reasoningEffort: nil
        )
        chatEditorViewModel.sendMessage(submission: submission)
    }

    func setComposerQuote(_ payload: ComposerQuotePayload) {
        let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        chatEditorViewModel.applyQuote(
            .init(
                type: "quote",
                text: trimmedText,
                quoteRef: payload.quoteRef
            )
        )
    }

    /// Send a retry trigger message to restart the current round.
    func retryMessage() {
        chatEditorViewModel.sendRetryMessage()
    }

    func pauseSchedule(_ scheduleID: String) async throws {
        try await ScheduleStore.shared.pause(scheduleID: scheduleID)
    }

    func resumeSchedule(_ scheduleID: String) async throws {
        try await ScheduleStore.shared.resume(scheduleID: scheduleID)
    }

    func deleteSchedule(_ scheduleID: String) async throws {
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete schedule")
        alert.informativeText = String(localized: "Are you sure you want to delete this schedule? This action cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        try await ScheduleStore.shared.delete(scheduleID: scheduleID)
    }

    /// Track copy from chat
    func trackCopyFromChat(_ contentType: String) {
        AnalyticsManager.track(.init(do: .copyFromChat(contentType: contentType), at: .chat))
    }

    func copyText(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Mark a message as good
    func goodMessage(_ userMessageId: String) {
        AnalyticsManager.track(.init(
            do: .chatGoodMessage(userMessageId: userMessageId),
            at: .chat
        ))
    }

    /// Mark a message as bad
    func badMessage(_ userMessageId: String) {
        AnalyticsManager.track(.init(
            do: .chatBadMessage(userMessageId: userMessageId),
            at: .chat
        ))
    }

    /// Return the latest recent conversations from the in-memory session summary list.
    func fetchRecentConversations() async -> [SessionListInfo] {
        recentConversationSnapshot()
    }

    /// open a conversation
    func openConversation(_ conversationId: String) async throws {
        ContinueInChatManager.shared.openConversation(conversationId)
    }

    func searchConversations(_ query: String) async throws -> [ConversationSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let sessionList = try await AgentSessionManager.shared.listSessions()
        var results: [ConversationSearchResult] = []
        let lowercasedQuery = trimmedQuery.localizedLowercase

        for sessionInfo in sessionList {
            let session = try await AgentSessionManager.shared.loadSession(sessionId: sessionInfo.id)
            for message in session.messages {
                let searchableText = message.searchableText
                guard searchableText.localizedLowercase.contains(lowercasedQuery) else {
                    continue
                }

                results.append(ConversationSearchResult(
                    id: "\(sessionInfo.id):\(message.id)",
                    conversationId: sessionInfo.id,
                    conversationTitle: sessionInfo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "Untitled")
                        : sessionInfo.title,
                    messageId: message.id,
                    role: message.role ?? message.type,
                    createdAt: message.timestamp,
                    snippet: Self.snippet(in: searchableText, query: trimmedQuery),
                    score: 1.0
                ))
            }
        }

        return results.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    func openConversationSearchResult(_ conversationId: String, messageId: String?) async throws {
        let trimmedConversationID = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConversationID.isEmpty else {
            throw RuntimeError(localized: "Conversation ID is required")
        }

        let trimmedMessageID = messageId?.trimmingCharacters(in: .whitespacesAndNewlines)
        ContinueInChatManager.shared.openConversation(
            trimmedConversationID,
            messageId: trimmedMessageID?.isEmpty == false ? trimmedMessageID : nil
        )
    }

    /// Resolve a URL for display in WebView.
    /// - For data URLs: returns as-is
    /// - For local file paths: materializes a preview file URL
    /// - For legacy agent file routes: maps the route back to a local path when possible
    /// - For other URLs: returns as-is
    func getStorageDownloadUrl(_ url: String) async throws -> String {
        if url.hasPrefix("data:") {
            return url
        }

        let source = legacyAgentFilePath(for: url) ?? url
        if source.hasPrefix("/") || source.hasPrefix("~") || source.hasPrefix("file://") {
            let fileURL = try await attachmentPreviewStore.fileURL(
                source: source,
                fileName: nil,
                mimeType: nil
            )
            return fileURL.absoluteString
        }

        guard let objectId = storageObjectID(for: url) else {
            return url
        }

        throw RuntimeError(localized: "Remote storage files are unavailable in the local app: \(objectId)")
    }

    /// Get current assistant state snapshot.
    func getAssistantState() async -> AssistantState? {
        chatEditorViewModel.chat?.session.assistantState
    }

    /// Persist the latest visible scroll offset for the active conversation.
    func updateScrollPosition(_ scrollTop: Double) {
        guard let conversationId = chatEditorViewModel.chat?.conversationId else {
            return
        }
        ChatViewModel.shared.cacheScrollPosition(conversationId: conversationId, scrollTop: scrollTop)
    }

    // MARK: - Swift → JS events

    /// Emit streaming state change
    @EmitEvent
    func isStreaming(_ value: Bool)

    /// Emit whether the current session still has an open task.
    @EmitEvent
    func hasOpenTask(_ value: Bool)

    /// Emit a new history message was added
    @EmitEvent
    func historyMessageAdded(_ message: SessionHistoryMessage)

    /// Emit full history reset (load/init)
    @EmitEvent
    func historyInit(_ payload: ChatHistoryInitPayload)

    /// Emit workspace state update
    @EmitEvent
    func workspaceState(_ state: WorkspaceState?)

    /// Emit aggregated session state update
    @EmitEvent
    func assistantState(_ state: AssistantState?)

    /// Emit customized padding top
    @EmitEvent
    func paddingTop(_ padding: CGFloat)

    /// Emit follow-up state update
    @EmitEvent
    func followUpState(_ state: FollowUpState)
    /// Emit visible schedules for the current chat surface.
    @EmitEvent
    func schedules(_ schedules: [ScheduleCard])

    /// Emit retry-availability state for the current session.
    @EmitEvent
    func canRetry(_ value: Bool)

    /// Emit recent histories
    @EmitEvent
    func recentSessions(_ sessions: [SessionListInfo])

    /// Ask the embedded web chat UI to present the conversation search panel.
    @EmitEvent
    func conversationSearchRequested(_ token: Int)

    /// Ask the embedded web chat UI to focus a specific stored message.
    @EmitEvent
    func focusMessage(_ messageId: String)

    /// Ask the embedded web chat UI to focus and highlight a quoted text range.
    @EmitEvent
    func focusQuote(_ event: QuoteFocusEvent)
}

extension MessagesBridge: WebViewAwareJSBridge {
    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
    }
}

@MainActor
private extension MessagesBridge {
    func recentConversationSnapshot(limit: Int = 3) -> [SessionListInfo] {
        ConversationListViewController.shared.sessions
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(limit)
            .map(\.self)
    }
}

@MainActor
private final class RecentSessionsBridgeBinder {
    func start(bridge: MessagesBridge) {
        broadcast(bridge: bridge)
        observe(bridge: bridge)
    }

    private func observe(bridge: MessagesBridge) {
        withObservationTracking {
            _ = ConversationListViewController.shared.sessionsRevision
        } onChange: { [weak self, weak bridge] in
            Task { @MainActor in
                guard let self, let bridge else { return }
                self.broadcast(bridge: bridge)
                self.observe(bridge: bridge)
            }
        }
    }

    private func broadcast(bridge: MessagesBridge) {
        bridge.recentSessions(bridge.recentConversationSnapshot())
    }
}

// MARK: - Quick Look Preview Transition Helpers

extension MessagesBridge {
    private func quickLookPreviewTransition(for sourceRect: WebViewPreviewSourceRect?) -> QuickLookPreviewTransition? {
        guard let sourceRect,
              sourceRect.width > 0,
              sourceRect.height > 0,
              let webView,
              let window = webView.window
        else {
            return nil
        }

        let rectInView = CGRect(
            x: sourceRect.x,
            y: sourceRect.y,
            width: sourceRect.width,
            height: sourceRect.height
        )
        let adjustedRectInView = normalizedPreviewSourceRect(rectInView, in: webView)
        guard !adjustedRectInView.isEmpty else {
            return nil
        }
        let rectInWindow = webView.convert(adjustedRectInView, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        let transitionImage = previewTransitionImage(in: webView, rect: adjustedRectInView)

        return QuickLookPreviewTransition(
            sourceFrameOnScreen: rectOnScreen,
            transitionImage: transitionImage
        )
    }

    private func normalizedPreviewSourceRect(_ rect: CGRect, in webView: WKWebView) -> CGRect {
        let bounds = webView.bounds
        var adjusted = rect

        if !webView.isFlipped {
            adjusted.origin.y = bounds.height - rect.maxY
        }

        let visibleRect = adjusted.intersection(bounds)
        if visibleRect.isNull || visibleRect.isEmpty {
            return .zero
        }

        return visibleRect
    }

    private func previewTransitionImage(in webView: WKWebView, rect: CGRect) -> NSImage? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        guard let bitmapRepresentation = webView.bitmapImageRepForCachingDisplay(in: rect) else {
            return nil
        }

        bitmapRepresentation.size = rect.size
        webView.cacheDisplay(in: rect, to: bitmapRepresentation)

        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmapRepresentation)
        return image
    }
}
