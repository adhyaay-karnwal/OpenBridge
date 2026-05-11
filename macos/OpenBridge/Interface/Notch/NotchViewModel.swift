import Combine
import Foundation
import SwiftUI

@MainActor @Observable
final class NotchViewModel {
    struct NotificationItem: Identifiable {
        let id: String
        let symbolName: String
        let tint: Color
        let title: String
        let message: String
        let actionTitle: String?
        let timestamp: Double
        let action: (@MainActor () -> Void)?
        let onDismiss: (@MainActor () -> Void)?
    }

    struct PermissionItem: Identifiable, Equatable {
        let id: String
        let confirmationId: String
        let sessionID: String
        let sessionTitle: String
        let environmentLabel: String
        let kind: String?
        let description: String
        let computerUseStart: SessionHistoryMessage.ComputerUseStartInfo?
        let timestamp: Double

        init(
            id: String,
            confirmationId: String,
            sessionID: String,
            sessionTitle: String,
            environmentLabel: String,
            kind: String? = nil,
            description: String,
            computerUseStart: SessionHistoryMessage.ComputerUseStartInfo? = nil,
            timestamp: Double
        ) {
            self.id = id
            self.confirmationId = confirmationId
            self.sessionID = sessionID
            self.sessionTitle = sessionTitle
            self.environmentLabel = environmentLabel
            self.kind = kind
            self.description = description
            self.computerUseStart = computerUseStart
            self.timestamp = timestamp
        }
    }

    enum EventItem: Identifiable {
        case permission(PermissionItem)
        case notification(NotificationItem)

        var id: String {
            switch self {
            case let .permission(item):
                item.id
            case let .notification(item):
                item.id
            }
        }

        var timestamp: Double {
            switch self {
            case let .permission(item):
                item.timestamp
            case let .notification(item):
                item.timestamp
            }
        }
    }

    enum CompactState: Equatable {
        case hidden
        case alert(count: Int)
        case running(text: String, count: Int)
        case status(type: TaskViewModel.LiveInfoType, count: Int)

        var count: Int {
            switch self {
            case .hidden:
                0
            case let .alert(count),
                 let .running(_, count),
                 let .status(_, count):
                count
            }
        }

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }
    }

    enum ExpandedMode: Equatable {
        case events
        case taskList
        case taskDetail
    }

    enum ExpandedTransitionDirection: Equatable {
        case forward
        case backward
    }

    enum ExpandedTransitionKind: Equatable {
        case modeChange
        case detailNavigation
    }

    private struct MockTaskState: Identifiable {
        let id: String
        let sessionID: String
        var title: String
        var subtitle: String
        var status: TaskViewModel.SurfaceItem.Status
        var timestamp: Double
        var todos: [SessionHistoryMessage.TodoItem]
        var permissionTriggerIndex: Int
        var hasTriggeredPermission = false
        var workspaceFiles: [String] = []
        var environmentID: String?
        var errorText: String?

        var surfaceItem: TaskViewModel.SurfaceItem {
            TaskViewModel.SurfaceItem(
                id: id,
                sessionID: sessionID,
                title: title,
                subtitle: subtitle,
                status: status,
                timestamp: timestamp,
                todos: todos,
                currentTodo: todos.first(where: { $0.status == "in_progress" })?.content,
                workspaceFiles: workspaceFiles,
                environmentID: environmentID,
                errorText: errorText
            )
        }
    }

    private struct MockNotificationTemplate {
        let symbolName: String
        let tint: Color
        let title: String
        let message: String
    }

    @ObservationIgnored
    let didChange = PassthroughSubject<Void, Never>()

    private(set) var revision = 0
    private(set) var selectedTaskSessionID: String?
    private(set) var notifications: [NotificationItem] = []
    private(set) var isMockModeEnabled = false
    private(set) var expandedTransitionDirection: ExpandedTransitionDirection = .forward
    private(set) var expandedTransitionKind: ExpandedTransitionKind = .modeChange
    private(set) var measuredEventListContentHeight: CGFloat?

    @ObservationIgnored
    private let taskViewModel: TaskViewModel
    @ObservationIgnored
    private var historyCleanups: [String: @Sendable () -> Void] = [:]
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored
    private var mockTaskStates: [MockTaskState] = []
    @ObservationIgnored
    private var mockPermissionItems: [PermissionItem] = []
    @ObservationIgnored
    private var mockNotifications: [NotificationItem] = []
    @ObservationIgnored
    private var mockSimulationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var lastEventMeasurementSignature = ""
    @ObservationIgnored
    private var measuredEventListWidth: CGFloat?

    init(taskViewModel: TaskViewModel = .shared) {
        self.taskViewModel = taskViewModel

        taskViewModel.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.handleStateChange()
            }
            .store(in: &cancellables)

        AgentSessionManager.shared.sessionListDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.syncWithLoadedSessions()
            }
            .store(in: &cancellables)

        syncWithLoadedSessions()
    }

    var taskItems: [TaskViewModel.SurfaceItem] {
        _ = revision
        if isMockModeEnabled {
            return mockTaskStates
                .sorted { $0.timestamp > $1.timestamp }
                .map(\.surfaceItem)
        }
        return taskViewModel.surfaceItems
    }

    var permissionItems: [PermissionItem] {
        _ = revision

        if isMockModeEnabled {
            return mockPermissionItems.sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.confirmationId > rhs.confirmationId
                }
                return lhs.timestamp > rhs.timestamp
            }
        }

        let taskTitleBySessionID = Dictionary(
            uniqueKeysWithValues: taskItems.map { ($0.sessionID, $0.title) }
        )

        return AgentSessionManager.shared.loadedSessions
            .flatMap { session in
                unresolvedPermissionItems(
                    in: session,
                    fallbackTitle: taskTitleBySessionID[session.sessionID] ?? displayTitle(for: session)
                )
            }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.confirmationId > rhs.confirmationId
                }
                return lhs.timestamp > rhs.timestamp
            }
    }

    var eventItems: [EventItem] {
        _ = revision

        let permissionEvents = permissionItems.map(EventItem.permission)
        let notificationEvents = activeNotifications
            .sorted { $0.timestamp > $1.timestamp }
            .map(EventItem.notification)

        return permissionEvents + notificationEvents
    }

    var eventMeasurementSignature: String {
        _ = revision
        return rawEventMeasurementSignature(for: eventItems)
    }

    var hasActivities: Bool {
        !taskItems.isEmpty || !eventItems.isEmpty
    }

    var hasCompletedTaskItems: Bool {
        taskItems.contains { $0.status == .completed }
    }

    var compactState: CompactState {
        let events = eventItems
        if !events.isEmpty {
            return .alert(count: events.count)
        }

        if isMockModeEnabled {
            guard !taskItems.isEmpty else { return .hidden }
            let runningCount = taskItems.count { $0.status == .running }
            if runningCount > 0 {
                let text = taskItems
                    .first(where: { $0.status == .running })?
                    .currentTodo ?? String(localized: "Planning next moves...")
                return .running(text: text, count: runningCount)
            }
            let completedCount = taskItems.count { $0.status == .completed }
            if completedCount > 0 {
                return .status(type: .completed, count: completedCount)
            }
            let failedCount = taskItems.count { $0.status == .failed }
            if failedCount > 0 {
                return .status(type: .failed, count: failedCount)
            }
            return .status(type: .others, count: taskItems.count)
        }

        let liveInfo = taskViewModel.liveInfo
        guard liveInfo.count > 0 else { return .hidden }

        if liveInfo.type == .running {
            let text = taskItems
                .first(where: { $0.status == .running })?
                .currentTodo ?? String(localized: "Planning next moves...")
            return .running(text: text, count: liveInfo.count)
        }

        return .status(type: liveInfo.type, count: liveInfo.count)
    }

    var expandedMode: ExpandedMode {
        _ = revision

        if !eventItems.isEmpty {
            return .events
        }

        guard let selectedTaskSessionID,
              taskItems.contains(where: { $0.sessionID == selectedTaskSessionID })
        else {
            return .taskList
        }

        return .taskDetail
    }

    var selectedTaskItem: TaskViewModel.SurfaceItem? {
        guard expandedMode == .taskDetail,
              let selectedTaskSessionID
        else { return nil }

        let sessionID = selectedTaskSessionID
        return taskItems.first(where: { $0.sessionID == sessionID })
    }

    var taskListContentHeight: CGFloat {
        _ = revision
        return NotchExpandedSurfaceMetrics.taskListContentHeight(taskCount: taskItems.count)
    }

    var taskDetailPosition: (index: Int, total: Int)? {
        guard let selectedTaskItem,
              let index = taskItems.firstIndex(where: { $0.sessionID == selectedTaskItem.sessionID })
        else {
            return nil
        }

        return (index, taskItems.count)
    }

    var canNavigateToPreviousTask: Bool {
        guard let position = taskDetailPosition else { return false }
        return position.index > 0
    }

    var canNavigateToNextTask: Bool {
        guard let position = taskDetailPosition else { return false }
        return position.index < position.total - 1
    }

    func showTaskList() {
        guard selectedTaskSessionID != nil else { return }
        expandedTransitionDirection = .backward
        expandedTransitionKind = .modeChange
        selectedTaskSessionID = nil
        signalChange()
    }

    func showTaskDetail(_ sessionID: String) {
        guard taskItems.contains(where: { $0.sessionID == sessionID }) else { return }
        guard selectedTaskSessionID != sessionID else { return }
        expandedTransitionDirection = .forward
        expandedTransitionKind = .modeChange
        selectedTaskSessionID = sessionID
        signalChange()
    }

    func showPreviousTask() {
        expandedTransitionDirection = .backward
        expandedTransitionKind = .detailNavigation
        navigateTask(offset: -1)
    }

    func showNextTask() {
        expandedTransitionDirection = .forward
        expandedTransitionKind = .detailNavigation
        navigateTask(offset: 1)
    }

    func openChat(for sessionID: String) {
        guard !isMockModeEnabled else { return }
        let shouldDismiss = taskItems
            .first(where: { $0.sessionID == sessionID })?
            .status
            .shouldClearAfterOpenInChat ?? false
        ContinueInChatManager.shared.openConversation(sessionID)
        if shouldDismiss {
            taskViewModel.dismissSurfaceItem(sessionID)
        }
        if selectedTaskSessionID == sessionID {
            selectedTaskSessionID = nil
        }
        signalChange()
    }

    func dismissTask(_ sessionID: String) {
        if isMockModeEnabled {
            cancelMockSimulation(for: sessionID)
            mockTaskStates.removeAll { $0.sessionID == sessionID }
            mockPermissionItems.removeAll { $0.sessionID == sessionID }
            if selectedTaskSessionID == sessionID {
                selectedTaskSessionID = nil
            }
            signalChange()
            return
        }

        taskViewModel.dismissSurfaceItem(sessionID)
        if selectedTaskSessionID == sessionID {
            selectedTaskSessionID = nil
        }
        signalChange()
    }

    func clearCompletedTasks() {
        if isMockModeEnabled {
            let completedSessionIDs = Set(
                mockTaskStates
                    .filter { $0.status == .completed }
                    .map(\.sessionID)
            )
            guard !completedSessionIDs.isEmpty else { return }

            for sessionID in completedSessionIDs {
                cancelMockSimulation(for: sessionID)
            }
            mockTaskStates.removeAll { completedSessionIDs.contains($0.sessionID) }
            mockPermissionItems.removeAll { completedSessionIDs.contains($0.sessionID) }
            if let selectedTaskSessionID, completedSessionIDs.contains(selectedTaskSessionID) {
                self.selectedTaskSessionID = nil
            }
            signalChange()
            return
        }

        let completedSessionIDs = Set(
            taskItems
                .filter { $0.status == .completed }
                .map(\.sessionID)
        )
        guard !completedSessionIDs.isEmpty else { return }

        taskViewModel.dismissCompletedSurfaceItems()
        if let selectedTaskSessionID, completedSessionIDs.contains(selectedTaskSessionID) {
            self.selectedTaskSessionID = nil
        }
        signalChange()
    }

    func cancelTask(_ sessionID: String) {
        if isMockModeEnabled {
            cancelMockTask(sessionID)
            return
        }

        guard let session = session(for: sessionID) else { return }

        session.requestStop()
    }

    func acceptTaskFiles(_ item: TaskViewModel.SurfaceItem) async throws {
        guard !isMockModeEnabled else { return }
        guard let session = session(for: item.sessionID),
              let environmentID = item.environmentID,
              !item.workspaceFiles.isEmpty
        else {
            return
        }

        try await session.acceptFiles(item.workspaceFiles, environmentID: environmentID)
    }

    func approvePermission(_ item: PermissionItem, mode: String? = nil) {
        if isMockModeEnabled {
            resolveMockPermission(item, approved: true)
            return
        }

        _ = AgentSessionManager.shared.resolveConnectorConfirmation(
            id: item.confirmationId,
            approved: true,
            mode: mode
        )
        signalChange()
    }

    func rejectPermission(_ item: PermissionItem) {
        if isMockModeEnabled {
            resolveMockPermission(item, approved: false)
            return
        }

        _ = AgentSessionManager.shared.resolveConnectorConfirmation(
            id: item.confirmationId,
            approved: false
        )
        signalChange()
    }

    func presentNotification(
        id: String = UUID().uuidString,
        symbolName: String = "bell.badge.fill",
        tint: Color = .orange,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        if isMockModeEnabled {
            mockNotifications.removeAll { $0.id == id }
            mockNotifications.insert(
                NotificationItem(
                    id: id,
                    symbolName: symbolName,
                    tint: tint,
                    title: title,
                    message: message,
                    actionTitle: actionTitle,
                    timestamp: Date().timeIntervalSince1970,
                    action: action,
                    onDismiss: onDismiss
                ),
                at: 0
            )
            signalChange()
            return
        }

        notifications.removeAll { $0.id == id }
        notifications.insert(
            NotificationItem(
                id: id,
                symbolName: symbolName,
                tint: tint,
                title: title,
                message: message,
                actionTitle: actionTitle,
                timestamp: Date().timeIntervalSince1970,
                action: action,
                onDismiss: onDismiss
            ),
            at: 0
        )
        signalChange()
    }

    func performNotificationAction(id: String) {
        if isMockModeEnabled {
            guard let index = mockNotifications.firstIndex(where: { $0.id == id }) else { return }
            let item = mockNotifications.remove(at: index)
            item.action?()
            signalChange()
            return
        }

        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        let item = notifications.remove(at: index)
        item.action?()
        signalChange()
    }

    func dismissNotification(id: String) {
        if isMockModeEnabled {
            guard let index = mockNotifications.firstIndex(where: { $0.id == id }) else { return }
            let item = mockNotifications.remove(at: index)
            item.onDismiss?()
            signalChange()
            return
        }

        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        let item = notifications.remove(at: index)
        item.onDismiss?()
        signalChange()
    }

    func addMockTask() {
        enterMockModeIfNeeded()

        let sessionID = "mock-task-\(UUID().uuidString)"
        let todos = makeMockTodos()
        let permissionTriggerIndex = Int.random(in: 1 ... (todos.count - 2))
        let timestamp = Date().timeIntervalSince1970
        let task = MockTaskState(
            id: sessionID,
            sessionID: sessionID,
            title: mockTaskTitle(),
            subtitle: todos.first?.content ?? String(localized: "Planning next moves..."),
            status: .running,
            timestamp: timestamp,
            todos: todos,
            permissionTriggerIndex: permissionTriggerIndex
        )
        mockTaskStates.insert(task, at: 0)
        selectedTaskSessionID = nil
        signalChange()

        startMockSimulation(for: sessionID)
    }

    func addMockNotification() {
        enterMockModeIfNeeded()
        mockNotifications.insert(makeMockNotification(), at: 0)
        signalChange()
    }

    func exitMockMode() {
        isMockModeEnabled = false
        selectedTaskSessionID = nil
        mockTaskStates.removeAll()
        mockPermissionItems.removeAll()
        mockNotifications.removeAll()
        cancelAllMockSimulations()
        signalChange()
    }

    func updateMeasuredEventListContentHeight(_ height: CGFloat, width: CGFloat) {
        let resolvedHeight = max(
            NotchExpandedSurfaceMetrics.minimumMeasuredListContentHeight,
            height.rounded(.toNearestOrEven)
        )
        let widthDidChange = abs((measuredEventListWidth ?? 0) - width) > 0.5
        guard widthDidChange || abs((measuredEventListContentHeight ?? 0) - resolvedHeight) > 0.5 else {
            return
        }

        measuredEventListContentHeight = resolvedHeight
        measuredEventListWidth = width
        signalChange(syncDerivedSurfaceHeights: false)
    }

    private func syncWithLoadedSessions() {
        let loadedSessions = AgentSessionManager.shared.loadedSessions
        let loadedIDs = Set(loadedSessions.map(\.sessionID))

        for sessionID in Array(historyCleanups.keys) where !loadedIDs.contains(sessionID) {
            historyCleanups.removeValue(forKey: sessionID)?()
        }

        for session in loadedSessions where historyCleanups[session.sessionID] == nil {
            historyCleanups[session.sessionID] = session.addHistoryEventListener { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleStateChange()
                }
            }
        }

        handleStateChange()
    }

    private func handleStateChange() {
        if let selectedTaskSessionID,
           !taskItems.contains(where: { $0.sessionID == selectedTaskSessionID })
        {
            self.selectedTaskSessionID = nil
        }

        signalChange()
    }

    private func navigateTask(offset: Int) {
        guard let selectedTaskItem,
              let currentIndex = taskItems.firstIndex(where: { $0.sessionID == selectedTaskItem.sessionID })
        else {
            return
        }

        let targetIndex = currentIndex + offset
        guard taskItems.indices.contains(targetIndex) else { return }

        selectedTaskSessionID = taskItems[targetIndex].sessionID
        signalChange()
    }

    private func session(for sessionID: String) -> LocalAgentSession? {
        AgentSessionManager.shared.loadedSessions.first(where: { $0.sessionID == sessionID })
    }

    private var activeNotifications: [NotificationItem] {
        isMockModeEnabled ? mockNotifications : notifications
    }

    private func syncDerivedSurfaceHeights() {
        let signature = rawEventMeasurementSignature(for: eventItems)
        guard signature != lastEventMeasurementSignature else { return }

        lastEventMeasurementSignature = signature
        measuredEventListContentHeight = nil
        measuredEventListWidth = nil
    }

    private func rawEventMeasurementSignature(for items: [EventItem]) -> String {
        guard !items.isEmpty else { return "empty" }

        return items.map { item in
            switch item {
            case let .permission(permission):
                [
                    "permission",
                    permission.id,
                    permission.confirmationId,
                    permission.sessionTitle,
                    permission.environmentLabel,
                    permission.description,
                ].joined(separator: "::")
            case let .notification(notification):
                [
                    "notification",
                    notification.id,
                    notification.symbolName,
                    notification.title,
                    notification.message,
                    notification.actionTitle ?? "",
                ].joined(separator: "::")
            }
        }
        .joined(separator: "||")
    }

    func eventListContentHeight(for eventListWidth: CGFloat) -> CGFloat {
        let estimatedHeight = NotchExpandedSurfaceMetrics.eventListContentHeight(
            for: eventItems,
            eventListWidth: eventListWidth
        )

        guard let measuredEventListContentHeight,
              let measuredEventListWidth,
              abs(measuredEventListWidth - eventListWidth) <= 0.5
        else {
            return estimatedHeight
        }

        return measuredEventListContentHeight
    }

    private func unresolvedPermissionItems(
        in session: LocalAgentSession,
        fallbackTitle: String
    ) -> [PermissionItem] {
        let resolvedConfirmationIDs = Set<String>(
            session.messages.compactMap { message in
                guard message.permissionReply != nil else { return nil }
                return message.confirmationId
            }
        )

        return session.messages.compactMap { message -> PermissionItem? in
            guard let permissionRequest = message.permissionRequest else { return nil }

            let confirmationId = message.confirmationId ?? message.id
            guard !resolvedConfirmationIDs.contains(confirmationId) else { return nil }

            let environmentLabel = permissionRequest.environmentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedEnvironment = environmentLabel?.isEmpty == false
                ? environmentLabel!
                : String(localized: "This Mac")

            return PermissionItem(
                id: confirmationId,
                confirmationId: confirmationId,
                sessionID: session.sessionID,
                sessionTitle: fallbackTitle,
                environmentLabel: resolvedEnvironment,
                kind: permissionRequest.kind,
                description: permissionRequest.description,
                computerUseStart: permissionRequest.computerUseStart,
                timestamp: message.timestamp
            )
        }
    }

    private func displayTitle(for session: LocalAgentSession) -> String {
        session.taskDisplayTitle
    }

    private func enterMockModeIfNeeded() {
        if !isMockModeEnabled {
            selectedTaskSessionID = nil
        }
        isMockModeEnabled = true
    }

    private func cancelMockTask(_ sessionID: String) {
        cancelMockSimulation(for: sessionID)
        guard let index = mockTaskStates.firstIndex(where: { $0.sessionID == sessionID }) else { return }
        mockTaskStates[index].status = .cancelled
        mockTaskStates[index].subtitle = String(localized: "Task cancelled")
        mockTaskStates[index].todos = mockTaskStates[index].todos.map { todo in
            guard todo.status == "in_progress" else { return todo }
            return .init(content: todo.content, status: "not_started")
        }
        mockPermissionItems.removeAll { $0.sessionID == sessionID }
        signalChange()
    }

    private func resolveMockPermission(_ item: PermissionItem, approved: Bool) {
        mockPermissionItems.removeAll { $0.id == item.id }

        guard let taskIndex = mockTaskStates.firstIndex(where: { $0.sessionID == item.sessionID }) else {
            signalChange()
            return
        }

        mockTaskStates[taskIndex].timestamp = Date().timeIntervalSince1970
        if approved {
            if let nextIndex = mockTaskStates[taskIndex].todos.firstIndex(where: { $0.status == "not_started" }) {
                let nextTodo = mockTaskStates[taskIndex].todos[nextIndex]
                mockTaskStates[taskIndex].todos[nextIndex] = .init(
                    content: nextTodo.content,
                    status: "in_progress"
                )
                mockTaskStates[taskIndex].status = .running
                mockTaskStates[taskIndex].subtitle = nextTodo.content
                mockTaskStates[taskIndex].errorText = nil
                signalChange()
                startMockSimulation(for: item.sessionID)
                return
            }

            completeMockTask(sessionID: item.sessionID)
            return
        } else {
            cancelMockSimulation(for: item.sessionID)
            mockTaskStates[taskIndex].status = .failed
            mockTaskStates[taskIndex].subtitle = String(localized: "Task failed")
            mockTaskStates[taskIndex].errorText = String(localized: "The mock permission request was rejected.")
        }

        signalChange()
    }

    private func runMockTaskLifecycle(sessionID: String) async {
        while let taskIndex = mockTaskStates.firstIndex(where: { $0.sessionID == sessionID }) {
            if mockPermissionItems.contains(where: { $0.sessionID == sessionID }) {
                return
            }

            guard let activeIndex = mockTaskStates[taskIndex].todos.firstIndex(where: { $0.status == "in_progress" }) else {
                completeMockTask(sessionID: sessionID)
                return
            }

            let delay = UInt64.random(in: 3 ... 8)
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            if Task.isCancelled { return }

            guard let currentTaskIndex = mockTaskStates.firstIndex(where: { $0.sessionID == sessionID }) else {
                return
            }

            var taskState = mockTaskStates[currentTaskIndex]
            guard activeIndex < taskState.todos.count else { return }

            taskState.todos[activeIndex] = .init(
                content: taskState.todos[activeIndex].content,
                status: "completed"
            )
            taskState.timestamp = Date().timeIntervalSince1970

            let nextIndex = activeIndex + 1
            if taskState.todos.indices.contains(nextIndex) {
                if !taskState.hasTriggeredPermission, nextIndex == taskState.permissionTriggerIndex {
                    taskState.status = .waiting
                    taskState.subtitle = String(localized: "Awaiting approval")
                    taskState.hasTriggeredPermission = true
                    mockTaskStates[currentTaskIndex] = taskState
                    presentMockPermission(for: taskState)
                    signalChange()
                    return
                }

                let nextTodo = taskState.todos[nextIndex]
                taskState.todos[nextIndex] = .init(content: nextTodo.content, status: "in_progress")
                taskState.status = .running
                taskState.subtitle = nextTodo.content
                mockTaskStates[currentTaskIndex] = taskState
                signalChange()
                continue
            }

            mockTaskStates[currentTaskIndex] = taskState
            completeMockTask(sessionID: sessionID)
            return
        }
    }

    private func presentMockPermission(for taskState: MockTaskState) {
        guard !mockPermissionItems.contains(where: { $0.sessionID == taskState.sessionID }) else { return }

        mockPermissionItems.insert(
            PermissionItem(
                id: "mock-permission-\(taskState.sessionID)",
                confirmationId: "mock-permission-\(taskState.sessionID)",
                sessionID: taskState.sessionID,
                sessionTitle: taskState.title,
                environmentLabel: String(localized: "This Mac"),
                description: String(localized: "Write the final mock artifact into ~/artifacts/notch-debug/mock-output.txt."),
                timestamp: Date().timeIntervalSince1970
            ),
            at: 0
        )
    }

    private func completeMockTask(sessionID: String) {
        cancelMockSimulation(for: sessionID)
        guard let taskIndex = mockTaskStates.firstIndex(where: { $0.sessionID == sessionID }) else { return }

        mockTaskStates[taskIndex].status = .completed
        mockTaskStates[taskIndex].subtitle = String(localized: "Task has been completed")
        mockTaskStates[taskIndex].timestamp = Date().timeIntervalSince1970
        mockTaskStates[taskIndex].workspaceFiles = [
            "~/workspace/openbridge/macos/OpenBridge/Interface/Notch/TasksView.swift",
        ]
        mockTaskStates[taskIndex].environmentID = "mock-environment"
        signalChange()
    }

    private func startMockSimulation(for sessionID: String) {
        let simulation = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await runMockTaskLifecycle(sessionID: sessionID)
        }
        cancelMockSimulation(for: sessionID)
        mockSimulationTasks[sessionID] = simulation
    }

    private func cancelMockSimulation(for sessionID: String) {
        mockSimulationTasks.removeValue(forKey: sessionID)?.cancel()
    }

    private func cancelAllMockSimulations() {
        let tasks = mockSimulationTasks.values
        mockSimulationTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
    }

    private func makeMockTodos() -> [SessionHistoryMessage.TodoItem] {
        let steps = mockTodoPool.shuffled().prefix(Int.random(in: 3 ... 10))
        return Array(steps.enumerated()).map { index, content in
            SessionHistoryMessage.TodoItem(
                content: content,
                status: index == 0 ? "in_progress" : "not_started"
            )
        }
    }

    private func mockTaskTitle() -> String {
        mockTaskTitlePool.randomElement() ?? String(localized: "Mock notch task")
    }

    private func makeMockNotification() -> NotificationItem {
        let template = Self.mockNotificationTemplates.randomElement() ?? .init(
            symbolName: "bell.badge.fill",
            tint: .orange,
            title: String(localized: "Mock notification"),
            message: String(localized: "The notch debug runtime inserted a mock notification.")
        )
        return NotificationItem(
            id: "mock-notification-\(UUID().uuidString)",
            symbolName: template.symbolName,
            tint: template.tint,
            title: template.title,
            message: template.message,
            actionTitle: Bool.random() ? String(localized: "Open") : nil,
            timestamp: Date().timeIntervalSince1970,
            action: nil,
            onDismiss: nil
        )
    }

    private func signalChange(syncDerivedSurfaceHeights: Bool = true) {
        if syncDerivedSurfaceHeights {
            self.syncDerivedSurfaceHeights()
        }
        revision += 1
        didChange.send()
    }

    private static let mockNotificationTemplates: [MockNotificationTemplate] = [
        .init(
            symbolName: "checkmark.circle.fill",
            tint: .green,
            title: String(localized: "Task has been completed"),
            message: String(localized: "The mock task finished successfully and the notch is ready for inspection.")
        ),
        .init(
            symbolName: "text.bubble.fill",
            tint: .orange,
            title: String(localized: "Permission request appeared in chat"),
            message: String(localized: "A mock approval request was mirrored into the notch event list.")
        ),
        .init(
            symbolName: "clock.badge.checkmark.fill",
            tint: .blue,
            title: String(localized: "Scheduled run updated"),
            message: String(localized: "The mock runtime nudged a recurring task and refreshed the notch feed.")
        ),
    ]
}

private let mockTaskTitlePool = [
    String(localized: "Polish the notch transition choreography"),
    String(localized: "Tune the permission request layout"),
    String(localized: "Verify the todo detail interaction flow"),
    String(localized: "Audit the task activity panel spacing"),
    String(localized: "Refine the scroll edge blur presentation"),
]

private let mockTodoPool = [
    String(localized: "Inspect the current notch compact state"),
    String(localized: "Prepare the expanded task list transition"),
    String(localized: "Update the running todo highlight animation"),
    String(localized: "Measure the permission card height"),
    String(localized: "Validate the notification stack spacing"),
    String(localized: "Check the todo detail header alignment"),
    String(localized: "Verify list and detail transition timing"),
    String(localized: "Reconcile the notch content sizing rules"),
    String(localized: "Compare mock and live rendering output"),
    String(localized: "Rebuild and relaunch the debug app"),
]
