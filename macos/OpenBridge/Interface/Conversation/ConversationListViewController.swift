//
//  ConversationListViewController.swift
//  OpenBridge
//
//  Created by OpenBridge on 2025/11/25.
//

import Foundation
import OSLog

// MARK: - Conversation List View Controller

@MainActor
@Observable
final class ConversationListViewController {
    static let shared = ConversationListViewController()

    // MARK: - State

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                true
            case (.loading, .loading):
                true
            case (.loaded, .loaded):
                true
            case (.failed, .failed):
                true
            default:
                false
            }
        }
    }

    // MARK: - Properties

    private(set) var state: State = .idle
    private(set) var sessions: [SessionListInfo] = []
    private(set) var sessionsRevision: Int = 0
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    private let logger = Logger.ui
    private var refreshTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var isStarted = false
    private var isRefreshing = false
    private var pendingBootstrapResetRefresh = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start background loading and realtime sync while the chat window is open.
    func start() {
        guard !isStarted else { return }

        isStarted = true

        if sessions.isEmpty {
            refresh(force: true, silent: false)
            return
        }

        if state == .idle {
            state = .loaded
        }
    }

    /// Stop background work when the chat window disappears.
    func stop() {
        isStarted = false
        refreshTask?.cancel()
        refreshTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        isRefreshing = false
        if sessions.isEmpty {
            state = .idle
        } else if case .loading = state {
            state = .loaded
        }
    }

    /// Refresh the session list without clearing the current snapshot.
    func refresh(force: Bool = true, silent: Bool = true) {
        if !isStarted {
            isStarted = true
        }

        if isRefreshing {
            return
        }

        refreshTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil

        isRefreshing = true
        isLoadingMore = false
        errorMessage = nil
        if !silent || sessions.isEmpty {
            state = .loading
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await fetchFirstPage(force: force, silent: silent)
        }
    }

    func loadMoreIfNeeded() {}

    /// Delete a session by ID.
    func deleteConversation(conversationId: String) async throws {
        try await AgentSessionManager.shared.deleteSession(sessionId: conversationId)
        AnalyticsManager.track(.init(do: .chatConversationDeleted, at: .chat))
        updateSessions(sessions.filter { $0.id != conversationId })
        hasMore = false
        logger.info("Deleted session: \(conversationId)")
    }

    /// Rename a session by ID.
    func renameConversation(conversationId: String, title: String) async throws {
        try await AgentSessionManager.shared.renameSession(sessionId: conversationId, title: title)
        syncConversationTitle(conversationId: conversationId, title: title)
        logger.info("Renamed session: \(conversationId)")
    }

    func syncConversationTitle(
        conversationId: String,
        title: String,
        purpose: String? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        guard let updatedSessions = ConversationListSessionMerge.syncTitle(
            current: sessions,
            conversationId: conversationId,
            title: normalizedTitle,
            purpose: purpose,
            createdAt: createdAt,
            updatedAt: updatedAt
        ) else {
            return
        }

        updateSessions(updatedSessions)
    }

    /// Cancel any ongoing load operation.
    func cancel() {
        stop()
    }

    // MARK: - Private Methods

    private var isFailureState: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private func fetchFirstPage(force: Bool, silent: Bool) async {
        defer {
            isRefreshing = false
            refreshTask = nil
            if pendingBootstrapResetRefresh {
                pendingBootstrapResetRefresh = false
                refresh(force: true, silent: true)
            }
        }

        do {
            let loadedSessions = try await AgentSessionManager.shared.listSessions()

            guard !Task.isCancelled else { return }

            updateSessions(loadedSessions)
            hasMore = false
            if !isStarted {
                isStarted = true
            }
            state = .loaded
            logger.info("Loaded \(loadedSessions.count) local session summaries")
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            if sessions.isEmpty || !silent || force {
                state = .failed(error)
            }
            logger.error("Failed to load session summaries: \(error.localizedDescription)")
        }
    }

    private func fetchNextPage(cursor: String) async {
        _ = cursor
        isLoadingMore = false
        loadMoreTask = nil
    }

    private func updateSessions(_ newSessions: [SessionListInfo]) {
        sessions = newSessions
        sessionsRevision &+= 1
    }

    private func resetSessionSummaryBootstrapState() {
        hasMore = false
    }

    private func requestSessionSummaryBootstrapRefresh() {
        resetSessionSummaryBootstrapState()
        if isRefreshing {
            pendingBootstrapResetRefresh = true
            return
        }
        pendingBootstrapResetRefresh = false
        refresh(force: true, silent: true)
    }
}

enum ConversationListSessionMerge {
    static func makeSessionListInfo(
        summary: LocalAgentSessionInfo,
        existing: SessionListInfo?
    ) -> SessionListInfo {
        SessionListInfo(
            id: summary.sessionId,
            title: summary.name,
            messageCount: existing?.messageCount,
            lastMessagePreview: existing?.lastMessagePreview,
            createdAt: summary.createdAt,
            updatedAt: summary.lastActivityAt ?? summary.createdAt
        )
    }

    static func merge(
        current: [SessionListInfo],
        incoming: [SessionListInfo]
    ) -> [SessionListInfo] {
        var sessionsByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        for session in incoming {
            if let existing = sessionsByID[session.id] {
                sessionsByID[session.id] = SessionListInfo(
                    id: session.id,
                    title: session.title,
                    messageCount: session.messageCount ?? existing.messageCount,
                    lastMessagePreview: session.lastMessagePreview ?? existing.lastMessagePreview,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt
                )
            } else {
                sessionsByID[session.id] = session
            }
        }

        return SessionListInfo.sortedNewestFirst(Array(sessionsByID.values))
    }

    static func syncTitle(
        current: [SessionListInfo],
        conversationId: String,
        title: String,
        purpose: String? = nil,
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) -> [SessionListInfo]? {
        if let index = current.firstIndex(where: { $0.id == conversationId }) {
            var updatedSessions = current
            let existing = updatedSessions[index]
            guard existing.title != title else { return nil }
            updatedSessions[index] = SessionListInfo(
                id: existing.id,
                title: title,
                messageCount: existing.messageCount,
                lastMessagePreview: existing.lastMessagePreview,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt
            )
            return updatedSessions
        }

        guard AgentSessionVisibility.isVisibleInConversationList(purpose: purpose) else {
            return nil
        }
        guard let createdAt, let updatedAt else { return nil }

        return SessionListInfo.sortedNewestFirst(
            current + [
                SessionListInfo(
                    id: conversationId,
                    title: title,
                    messageCount: nil,
                    lastMessagePreview: nil,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                ),
            ]
        )
    }
}
