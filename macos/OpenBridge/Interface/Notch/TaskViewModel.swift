import Combine
import Foundation
import SwiftUI

@MainActor @Observable
final class TaskViewModel {
    static let shared = TaskViewModel()

    enum LiveInfoType: Equatable {
        case running
        case completed
        case others
        case failed
    }

    struct SurfaceItem: Identifiable, Equatable {
        enum Status: Equatable {
            case running
            case waiting
            case completed
            case failed
            case cancelled

            var isActive: Bool {
                switch self {
                case .running, .waiting:
                    true
                case .completed, .failed, .cancelled:
                    false
                }
            }

            var shouldClearAfterOpenInChat: Bool {
                self == .completed
            }
        }

        let id: String
        let sessionID: String
        let title: String
        let subtitle: String
        let status: Status
        let timestamp: Double
        let todos: [SessionHistoryMessage.TodoItem]
        let currentTodo: String?
        let workspaceFiles: [String]
        let environmentID: String?
        let errorText: String?

        var isDismissible: Bool {
            switch status {
            case .completed, .failed, .cancelled:
                true
            case .running, .waiting:
                false
            }
        }
    }

    /// Publisher for non-SwiftUI consumers (e.g. BarMenuCoordinator).
    @ObservationIgnored
    let didChange = PassthroughSubject<Void, Never>()

    private(set) var activeSessions: [LocalAgentSession] = []
    private(set) var closedSessionIds: Set<String> = []
    private(set) var dismissedSurfaceSessionIds: Set<String> = []
    private(set) var updateTrigger: Int = 0

    @ObservationIgnored
    private var historyCleanups: [String: @Sendable () -> Void] = [:]
    @ObservationIgnored
    private var observedSessionIDs: Set<String> = []
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []

    var visibleSessions: [LocalAgentSession] {
        activeSessions
            .filter { session in
                !closedSessionIds.contains(session.sessionID)
                    && !dismissedSurfaceSessionIds.contains(session.sessionID)
                    && hasTaskMessages(session)
            }
            .sorted { latestTaskTimestamp(for: $0) > latestTaskTimestamp(for: $1) }
    }

    var liveInfo: (type: LiveInfoType, count: Int) {
        let items = surfaceItems
        guard !items.isEmpty else { return (.others, 0) }

        let runningCount = items.count(where: { $0.status == .running })
        if runningCount > 0 { return (.running, runningCount) }

        let completedCount = items.count(where: { $0.status == .completed })
        if completedCount > 0 { return (.completed, completedCount) }

        let failedCount = items.count(where: { $0.status == .failed })
        if failedCount > 0 { return (.failed, failedCount) }

        return (.others, items.count)
    }

    var hasRunningTasks: Bool {
        liveInfo.type == .running
    }

    var hasActiveTasks: Bool {
        activeSessions.contains { sessionHasActiveTask($0) }
    }

    var surfaceItems: [SurfaceItem] {
        visibleSessions.compactMap(surfaceItem(for:))
    }

    var hasCompletedSurfaceItems: Bool {
        surfaceItems.contains { $0.status == .completed }
    }

    private init() {
        setupSubscriptions()
        syncWithLoadedSessions()
    }

    // MARK: - State Change

    private func signalChange() {
        updateTrigger += 1
        didChange.send()
    }

    // MARK: - Subscriptions

    private func setupSubscriptions() {
        AgentSessionManager.shared.sessionListDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.syncWithLoadedSessions()
            }
            .store(in: &cancellables)
    }

    private func syncWithLoadedSessions() {
        let loaded = AgentSessionManager.shared.loadedSessions
        let loadedIDs = Set(loaded.map(\.sessionID))

        // Prune sessions removed from AgentSessionManager
        let removed = activeSessions.filter { !loadedIDs.contains($0.sessionID) }
        for session in removed {
            removeSession(session.sessionID)
        }

        // Subscribe to history on every newly-loaded session so we detect
        // the first task message and activate the session at that point.
        for session in loaded {
            let sid = session.sessionID
            guard historyCleanups[sid] == nil else { continue }
            subscribeToHistory(session)
            observeSessionState(of: session)

            // If session already has task messages (e.g. restored from disk)
            if hasTaskMessages(session) {
                activateSession(session)
            }
        }
    }

    // MARK: - Session Tracking

    private func activateSession(_ session: LocalAgentSession) {
        closedSessionIds.remove(session.sessionID)
        guard !activeSessions.contains(where: { $0.sessionID == session.sessionID }) else { return }
        activeSessions.append(session)
        signalChange()
    }

    private func observeSessionState(of session: LocalAgentSession) {
        let sessionID = session.sessionID
        guard !observedSessionIDs.contains(sessionID) else { return }
        observedSessionIDs.insert(sessionID)

        withObservationTracking {
            _ = session.hasOpenTask
            _ = session.isWaiting
            _ = session.lastWaitReason
        } onChange: { [weak self, weak session] in
            Task { @MainActor [weak self, weak session] in
                guard let self, let session else { return }
                if sessionHasActiveTask(session) {
                    dismissedSurfaceSessionIds.remove(session.sessionID)
                }
                if hasTaskMessages(session) {
                    activateSession(session)
                }
                signalChange()
                observedSessionIDs.remove(session.sessionID)
                if AgentSessionManager.shared.getSession(session.sessionID) != nil {
                    observeSessionState(of: session)
                }
            }
        }
    }

    private func removeSession(_ sessionID: String) {
        activeSessions.removeAll { $0.sessionID == sessionID }
        if let cleanup = historyCleanups.removeValue(forKey: sessionID) {
            cleanup()
        }
        observedSessionIDs.remove(sessionID)
        closedSessionIds.remove(sessionID)
        dismissedSurfaceSessionIds.remove(sessionID)
        signalChange()
    }

    private func subscribeToHistory(_ session: LocalAgentSession) {
        let cleanup = session.addHistoryEventListener { [weak self, weak session] event in
            Task { @MainActor [weak self, weak session] in
                guard let self, let session else { return }
                if case let .added(message) = event, message.type == "task" {
                    activateSession(session)
                    if message.action == "start" {
                        closedSessionIds.remove(session.sessionID)
                        dismissedSurfaceSessionIds.remove(session.sessionID)
                        SoundsService.play(event: .agentTaskCreated)
                    } else if message.action == "end" {
                        SoundsService.play(event: .agentTaskComplete)
                    }
                    signalChange()
                }
            }
        }
        historyCleanups[session.sessionID] = cleanup
    }

    // MARK: - Public Actions

    func closeSession(_ sessionId: String) {
        closedSessionIds.insert(sessionId)
        dismissedSurfaceSessionIds.remove(sessionId)
        signalChange()
    }

    func dismissSurfaceItem(_ sessionId: String) {
        dismissedSurfaceSessionIds.insert(sessionId)
        signalChange()
    }

    func dismissCompletedSurfaceItems() {
        let completedSessionIds = surfaceItems
            .filter { $0.status == .completed }
            .map(\.sessionID)
        guard !completedSessionIds.isEmpty else { return }

        dismissedSurfaceSessionIds.formUnion(completedSessionIds)
        signalChange()
    }

    func reopenSession(_ sessionId: String) {
        closedSessionIds.remove(sessionId)
        dismissedSurfaceSessionIds.remove(sessionId)
        signalChange()
    }

    func reopenAllSessions() {
        closedSessionIds.removeAll()
        dismissedSurfaceSessionIds.removeAll()
        signalChange()
    }

    // MARK: - Task State Helpers

    func hasTaskMessages(_ session: LocalAgentSession) -> Bool {
        session.messages.contains { $0.type == "task" }
    }

    func latestTaskAction(for session: LocalAgentSession) -> String? {
        session.messages.last(where: { $0.type == "task" })?.action
    }

    private func latestTaskTimestamp(for session: LocalAgentSession) -> Double {
        session.messages.last(where: { $0.type == "task" })?.timestamp ?? 0
    }

    private func sessionHasActiveTask(_ session: LocalAgentSession) -> Bool {
        guard session.hasOpenTask else { return false }
        guard let action = latestTaskAction(for: session) else { return false }
        return action == "start" || action == "update"
    }

    private func surfaceItem(for session: LocalAgentSession) -> SurfaceItem? {
        guard let latestTask = session.messages.last(where: { $0.type == "task" }) else { return nil }

        let title = displayTitle(for: session)
        let fallbackError = latestTask.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorText = fallbackError?.isEmpty == false ? fallbackError : nil
        let aggregatedTodos = aggregatedTodos(for: session, latestTask: latestTask)
        let statusInfo = surfaceStatusInfo(
            for: session,
            latestTask: latestTask,
            todos: aggregatedTodos,
            errorText: errorText
        )

        return SurfaceItem(
            id: session.sessionID,
            sessionID: session.sessionID,
            title: title,
            subtitle: statusInfo.subtitle,
            status: statusInfo.status,
            timestamp: latestTask.timestamp,
            todos: aggregatedTodos,
            currentTodo: aggregatedTodos.first(where: { $0.status == "in_progress" })?.content,
            workspaceFiles: session.workspaceState?.fileDiff.map(\.path) ?? [],
            environmentID: session.workspaceState?.environmentId,
            errorText: errorText
        )
    }

    private func surfaceStatusInfo(
        for session: LocalAgentSession,
        latestTask: SessionHistoryMessage,
        todos: [SessionHistoryMessage.TodoItem],
        errorText: String?
    ) -> (status: SurfaceItem.Status, subtitle: String) {
        if !session.hasOpenTask {
            return terminalSurfaceStatusInfo(for: session, errorText: errorText)
        }

        switch latestTask.action {
        case "start", "update":
            return activeSurfaceStatusInfo(
                for: session,
                todos: todos,
                errorText: errorText
            )
        case "end":
            if session.lastFinishState == "error" {
                return (.failed, errorText ?? String(localized: "Task failed"))
            }
            return (.completed, String(localized: "Task has been completed"))
        case "cancel":
            return (.cancelled, String(localized: "Task cancelled"))
        default:
            return terminalSurfaceStatusInfo(for: session, errorText: errorText)
        }
    }

    private func activeSurfaceStatusInfo(
        for session: LocalAgentSession,
        todos: [SessionHistoryMessage.TodoItem],
        errorText: String?
    ) -> (status: SurfaceItem.Status, subtitle: String) {
        if session.lastFinishState == "error" {
            return (.failed, errorText ?? String(localized: "Task failed"))
        }
        if session.isWaiting {
            return (.waiting, session.lastWaitReason ?? String(localized: "Waiting for the next update"))
        }
        return (
            .running,
            todos.first(where: { $0.status == "in_progress" })?.content
                ?? String(localized: "Planning next moves...")
        )
    }

    private func terminalSurfaceStatusInfo(
        for session: LocalAgentSession,
        errorText: String?
    ) -> (status: SurfaceItem.Status, subtitle: String) {
        switch session.lastFinishState {
        case "waiting":
            (.waiting, session.lastWaitReason ?? String(localized: "Waiting for the next update"))
        case "cancelled":
            (.cancelled, String(localized: "Task cancelled"))
        case "error":
            (.failed, errorText ?? String(localized: "Task failed"))
        default:
            (.completed, String(localized: "Task has been completed"))
        }
    }

    private func displayTitle(for session: LocalAgentSession) -> String {
        session.taskDisplayTitle
    }

    private func aggregatedTodos(
        for session: LocalAgentSession,
        latestTask: SessionHistoryMessage
    ) -> [SessionHistoryMessage.TodoItem] {
        let taskMessages = latestTaskTimeline(in: session, latestTask: latestTask)

        var order: [String] = []
        var latestByContent: [String: SessionHistoryMessage.TodoItem] = [:]

        for message in taskMessages {
            guard let todos = message.todos, !todos.isEmpty else { continue }

            for todo in todos {
                if latestByContent[todo.content] == nil {
                    order.append(todo.content)
                }
                latestByContent[todo.content] = todo
            }
        }

        let aggregated = order.compactMap { latestByContent[$0] }
        if !aggregated.isEmpty {
            return aggregated
        }

        return latestTask.todos ?? []
    }

    private func latestTaskTimeline(
        in session: LocalAgentSession,
        latestTask: SessionHistoryMessage
    ) -> [SessionHistoryMessage] {
        let taskMessages = session.messages.filter { $0.type == "task" }
        guard let latestIndex = taskMessages.lastIndex(where: { $0.id == latestTask.id }) else {
            return [latestTask]
        }

        let latestTaskID = latestTask.taskId
        var timeline: [SessionHistoryMessage] = []

        for index in stride(from: latestIndex, through: 0, by: -1) {
            let message = taskMessages[index]

            if !timeline.isEmpty {
                if let latestTaskID,
                   let messageTaskID = message.taskId,
                   !messageTaskID.isEmpty,
                   messageTaskID != latestTaskID
                {
                    break
                }

                if latestTaskID == nil,
                   let action = message.action,
                   action == "end" || action == "cancel"
                {
                    break
                }
            }

            timeline.append(message)

            if message.action == "start" {
                break
            }
        }

        return timeline.reversed()
    }
}
