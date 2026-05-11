import AppKit
import Combine
import NotchKit
import OSLog
import SwiftUI

@MainActor
final class NotchCenter {
    private struct DebugPreview {
        enum Content {
            case status(type: TaskViewModel.LiveInfoType, count: Int)
            case mock(NotchDebugMockKind)
        }

        let content: Content
    }

    static let shared = NotchCenter()

    private let notchViewModel = NotchViewModel()
    private let debugConfigurationStore = NotchDebugConfigurationStore.shared
    private let controller = NotchController(
        configuration: NotchDebugConfigurationStore.shared.configuration
    )

    private var hasBootstrapped = false
    private var cancellables: Set<AnyCancellable> = []
    private var historyEventCleanups: [String: @Sendable () -> Void] = [:]
    private var lastTaskCount = 0
    private var lastEventCount = 0
    private var pendingCompletedTaskSessionIDs: Set<String> = []
    private var pendingPermissionAutoExpand = false
    private var lastMockTaskStatuses: [String: TaskViewModel.SurfaceItem.Status] = [:]
    private var lastMockPermissionIDs: Set<String> = []
    private var notificationSequence = 0
    private var debugPreview: DebugPreview?

    var hasActivities: Bool {
        controller.hasActivity
    }

    private init() {}

    func boot(openOnLaunch: Bool = false) {
        guard !hasBootstrapped else {
            if openOnLaunch {
                open()
            }
            return
        }
        hasBootstrapped = true

        Logger.ui.debug("Bootstrapping NotchCenter")

        bindStateUpdates()
        pushScene(notifyOnIncrease: false)
        controller.start()

        if openOnLaunch {
            controller.open()
        }
    }

    func open() {
        controller.open()
    }

    func close() {
        controller.close()
    }

    func toggle() {
        controller.toggle()
    }

    func applyDebugConfiguration() {
        controller.update(configuration: debugConfigurationStore.configuration)
        pushScene(notifyOnIncrease: false)
    }

    func showDebugPreview(type: TaskViewModel.LiveInfoType, count: Int, expanded: Bool) {
        let preview = DebugPreview(content: .status(type: type, count: max(1, count)))
        debugPreview = preview
        controller.update(scene: makeDebugScene(preview))

        if expanded {
            controller.open()
        } else {
            controller.close()
        }
    }

    func triggerDebugNotification(type: TaskViewModel.LiveInfoType, count: Int) {
        let preview = DebugPreview(content: .status(type: type, count: max(1, count)))
        debugPreview = preview
        controller.close()
        controller.update(
            scene: makeDebugScene(
                preview,
                notificationToken: AnyHashable(UUID())
            )
        )
    }

    func showDebugMock(_ kind: NotchDebugMockKind) {
        let preview = DebugPreview(content: .mock(kind))
        debugPreview = preview
        controller.update(scene: makeDebugScene(preview))
        controller.open()
    }

    func clearDebugPreview() {
        debugPreview = nil
        pushScene(notifyOnIncrease: false)
        controller.close()
    }

    func addDebugMockTask() {
        debugPreview = nil
        notchViewModel.addMockTask()
        controller.open()
    }

    func addDebugMockNotification() {
        debugPreview = nil
        notchViewModel.addMockNotification()
        controller.open()
    }

    func exitDebugMockMode() {
        debugPreview = nil
        notchViewModel.exitMockMode()
        pushScene(notifyOnIncrease: false)
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
        notchViewModel.presentNotification(
            id: id,
            symbolName: symbolName,
            tint: tint,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action,
            onDismiss: onDismiss
        )
    }

    func dismissNotification(id: String) {
        notchViewModel.dismissNotification(id: id)
    }

    func triggerNotificationBounce() {
        guard debugPreview == nil else { return }
        guard controller.hasActivity else { return }

        notificationSequence += 1
        controller.update(scene: makeScene())
    }

    private func bindStateUpdates() {
        notchViewModel.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.pushScene()
            }
            .store(in: &cancellables)

        AgentSessionManager.shared.sessionListDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.syncHistoryEventWatchers()
            }
            .store(in: &cancellables)

        syncHistoryEventWatchers()
    }

    private func syncHistoryEventWatchers() {
        let loadedSessions = AgentSessionManager.shared.loadedSessions
        let loadedSessionIDs = Set(loadedSessions.map(\.sessionID))

        for sessionID in Array(historyEventCleanups.keys) where !loadedSessionIDs.contains(sessionID) {
            historyEventCleanups.removeValue(forKey: sessionID)?()
        }
        pendingCompletedTaskSessionIDs.formIntersection(loadedSessionIDs)

        for session in loadedSessions where historyEventCleanups[session.sessionID] == nil {
            historyEventCleanups[session.sessionID] = session.addHistoryEventListener { [weak self] event in
                Task { @MainActor [weak self, weak session] in
                    guard let self, let session else { return }
                    self.handleHistoryEvent(event, sessionID: session.sessionID)
                }
            }
        }
    }

    private func handleHistoryEvent(_ event: SessionHistoryEvent, sessionID: String) {
        guard case let .added(message) = event else { return }

        if message.type == "task", message.action == "end" {
            pendingCompletedTaskSessionIDs.insert(sessionID)
        }
        if message.permissionRequest != nil {
            SoundsService.play(event: .permission)
            pendingPermissionAutoExpand = true
        }

        guard !pendingCompletedTaskSessionIDs.isEmpty || pendingPermissionAutoExpand else { return }
        pushScene()
    }

    private func pushScene(notifyOnIncrease: Bool = true) {
        let taskItems = notchViewModel.taskItems
        let eventItems = notchViewModel.eventItems
        let permissionItems = notchViewModel.permissionItems
        let isMockModeEnabled = notchViewModel.isMockModeEnabled
        let taskCount = taskItems.count
        let eventCount = eventItems.count
        let visibleTaskSessionIDs = Set(taskItems.map(\.sessionID))
        let hasCompletedTaskTransition = taskItems.contains { item in
            pendingCompletedTaskSessionIDs.contains(item.sessionID) && item.status == .completed
        }
        let hasPermissionTransition = pendingPermissionAutoExpand && !permissionItems.isEmpty
        let currentMockTaskStatuses = Dictionary(
            uniqueKeysWithValues: taskItems.map { ($0.sessionID, $0.status) }
        )
        let currentMockPermissionIDs = Set(permissionItems.map(\.id))
        let hasMockCompletedTaskTransition = isMockModeEnabled && taskItems.contains { item in
            item.status == .completed && lastMockTaskStatuses[item.sessionID] != .completed
        }
        let hasMockPermissionTransition = isMockModeEnabled
            && !currentMockPermissionIDs.subtracting(lastMockPermissionIDs).isEmpty
        let shouldAutoExpand = notifyOnIncrease
            && debugPreview == nil
            && (
                hasCompletedTaskTransition
                    || hasPermissionTransition
                    || hasMockCompletedTaskTransition
                    || hasMockPermissionTransition
            )

        if notifyOnIncrease,
           debugPreview == nil,
           taskCount > lastTaskCount || eventCount > lastEventCount
        {
            notificationSequence += 1
        }
        lastTaskCount = taskCount
        lastEventCount = eventCount
        if isMockModeEnabled {
            lastMockTaskStatuses = currentMockTaskStatuses
            lastMockPermissionIDs = currentMockPermissionIDs
        } else {
            lastMockTaskStatuses = [:]
            lastMockPermissionIDs = []
        }
        pendingCompletedTaskSessionIDs.subtract(visibleTaskSessionIDs)
        if hasPermissionTransition || permissionItems.isEmpty {
            pendingPermissionAutoExpand = false
        }

        controller.update(scene: makeScene())
        if shouldAutoExpand {
            controller.open()
        }
    }

    private func makeScene() -> NotchScene {
        if let debugPreview {
            return makeDebugScene(debugPreview)
        }

        guard notchViewModel.hasActivities else {
            return .hidden
        }

        let compactState = notchViewModel.compactState
        let compactSideWidth = compactState.isRunning
            ? max(debugConfigurationStore.resolvedCompactSideWidth, notchRunningCompactSideWidth)
            : debugConfigurationStore.resolvedCompactSideWidth
        let expandedSurfaceSize = debugConfigurationStore.resolvedExpandedSurfaceSize
        let eventListWidth = NotchExpandedSurfaceMetrics.eventListWidth(
            surfaceWidth: expandedSurfaceSize.width,
            expandedPadding: debugConfigurationStore.configuration.expandedPadding
        )
        let notchHeight = resolvedNotchHeight(
            fallback: debugConfigurationStore.configuration.fallbackNotchSize.height
        )
        let expandedSizing: NotchExpandedSizing = switch notchViewModel.expandedMode {
        case .events:
            .fixed(
                adaptiveListSurfaceSize(
                    baseSize: expandedSurfaceSize,
                    notchHeight: notchHeight,
                    contentHeight: notchViewModel.eventListContentHeight(for: eventListWidth)
                )
            )
        case .taskList:
            .fixed(
                adaptiveListSurfaceSize(
                    baseSize: expandedSurfaceSize,
                    notchHeight: notchHeight,
                    contentHeight: notchViewModel.taskListContentHeight
                )
            )
        case .taskDetail:
            .fixed(
                taskDetailSurfaceSize(
                    baseSize: expandedSurfaceSize,
                    notchHeight: notchHeight,
                    item: notchViewModel.selectedTaskItem
                )
            )
        }

        let notificationToken: AnyHashable? = notificationSequence > 0
            ? AnyHashable(notificationSequence)
            : nil

        return NotchScene(
            hasActivity: true,
            notificationToken: notificationToken,
            compactSideWidth: compactSideWidth,
            compactLeadingSlot: NotchScene.erased {
                NotchActivityLeadingSlotView(
                    state: compactState,
                    availableWidth: compactSideWidth
                )
            },
            compactTrailingSlot: NotchScene.erased {
                NotchActivityTrailingSlotView(
                    count: compactState.count,
                    availableWidth: compactSideWidth
                )
            },
            expandedLeadingSlot: NotchScene.erased {
                NotchExpandedLeadingSlotView(viewModel: notchViewModel)
            },
            expandedTrailingSlot: NotchScene.erased {
                NotchExpandedTrailingSlotView(viewModel: notchViewModel)
            },
            expandedContent: NotchScene.erased {
                NotchExpandedContentView(viewModel: notchViewModel)
                    .environment(SettingsManager.shared)
            },
            expandedSizing: expandedSizing
        )
    }

    private func taskDetailSurfaceSize(
        baseSize: CGSize,
        notchHeight: CGFloat,
        item: TaskViewModel.SurfaceItem?
    ) -> CGSize {
        let contentHeight = min(
            NotchExpandedSurfaceMetrics.detailContentHeight(todoCount: item?.todos.count ?? 0),
            NotchExpandedSurfaceMetrics.detailMaxHeight
        )
        let maxHeight = max(baseSize.height, 340)
        let height = min(contentHeight + notchHeight, maxHeight)

        return CGSize(width: baseSize.width, height: height)
    }

    private func adaptiveListSurfaceSize(
        baseSize: CGSize,
        notchHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGSize {
        let maxContentHeight = max(
            baseSize.height,
            NotchExpandedSurfaceMetrics.maximumListSurfaceHeight
        )
        let resolvedContentHeight = min(contentHeight, maxContentHeight)

        return CGSize(
            width: baseSize.width,
            height: notchHeight + resolvedContentHeight
        )
    }

    private func resolvedNotchHeight(fallback: CGFloat) -> CGFloat {
        let screen: NSScreen? = switch debugConfigurationStore.configuration.screenSelectionPolicy {
        case .builtInFirst:
            builtInNotchDisplay() ?? NSScreen.main ?? NSScreen.screens.first
        case .screenUnderPointer:
            screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        case .mainScreen:
            NSScreen.main ?? NSScreen.screens.first
        }

        guard let screen else { return fallback }
        let notchHeight = notchSize(for: screen).height
        return notchHeight > 0 ? notchHeight : fallback
    }

    private func builtInNotchDisplay() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(id.uint32Value) == 1
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main
    }

    private func notchSize(for screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0 else { return .zero }

        let notchHeight = screen.safeAreaInsets.top
        let fullWidth = screen.frame.width
        let leftPadding = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = screen.auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else { return .zero }

        let notchWidth = fullWidth - leftPadding - rightPadding
        return CGSize(width: ceil(notchWidth), height: ceil(notchHeight))
    }

    private func makeDebugScene(
        _ preview: DebugPreview,
        notificationToken: AnyHashable? = nil
    ) -> NotchScene {
        let compactState: NotchViewModel.CompactState
        let expandedContent: AnyView
        let expandedSizing: NotchExpandedSizing
        let trailingCount: Int
        let compactSideWidth: CGFloat
        let expandedSurfaceSize = debugConfigurationStore.resolvedExpandedSurfaceSize
        let eventListWidth = NotchExpandedSurfaceMetrics.eventListWidth(
            surfaceWidth: expandedSurfaceSize.width,
            expandedPadding: debugConfigurationStore.configuration.expandedPadding
        )
        let notchHeight = resolvedNotchHeight(
            fallback: debugConfigurationStore.configuration.fallbackNotchSize.height
        )

        switch preview.content {
        case let .status(type, count):
            let state: NotchViewModel.CompactState = if type == .running {
                .running(
                    text: String(localized: "Drafting the active todo summary"),
                    count: count
                )
            } else {
                .status(type: type, count: count)
            }
            compactState = state
            trailingCount = count
            compactSideWidth = resolvedDebugCompactSideWidth(for: state)
            expandedContent = NotchScene.erased {
                NotchDebugExpandedContentView(type: type, count: count)
            }
            expandedSizing = .fixed(expandedSurfaceSize)
        case let .mock(kind):
            compactState = kind.compactState
            trailingCount = compactState.count
            compactSideWidth = resolvedDebugCompactSideWidth(for: compactState)
            expandedContent = NotchScene.erased {
                NotchDebugMockExpandedContentView(kind: kind)
            }
            expandedSizing = resolvedDebugExpandedSizing(
                for: kind,
                expandedSurfaceSize: expandedSurfaceSize,
                notchHeight: notchHeight,
                eventListWidth: eventListWidth
            )
        }

        return NotchScene(
            hasActivity: true,
            notificationToken: notificationToken,
            compactSideWidth: compactSideWidth,
            compactLeadingSlot: NotchScene.erased {
                NotchActivityLeadingSlotView(
                    state: compactState,
                    availableWidth: compactSideWidth
                )
            },
            compactTrailingSlot: NotchScene.erased {
                NotchActivityTrailingSlotView(
                    count: trailingCount,
                    availableWidth: compactSideWidth
                )
            },
            expandedLeadingSlot: debugExpandedLeadingSlot(),
            expandedTrailingSlot: debugExpandedTrailingSlot(),
            expandedContent: expandedContent,
            expandedSizing: expandedSizing
        )
    }

    private func resolvedDebugCompactSideWidth(for state: NotchViewModel.CompactState) -> CGFloat {
        state.isRunning
            ? max(debugConfigurationStore.resolvedCompactSideWidth, notchRunningCompactSideWidth)
            : debugConfigurationStore.resolvedCompactSideWidth
    }

    private func resolvedDebugExpandedSizing(
        for kind: NotchDebugMockKind,
        expandedSurfaceSize: CGSize,
        notchHeight: CGFloat,
        eventListWidth: CGFloat
    ) -> NotchExpandedSizing {
        switch kind {
        case .taskList,
             .permissions,
             .computerUsePermissions,
             .permissionSingleLong,
             .permissionStackedLong,
             .mixedAttention,
             .notifications:
            .fixed(
                adaptiveListSurfaceSize(
                    baseSize: expandedSurfaceSize,
                    notchHeight: notchHeight,
                    contentHeight: kind.expandedContentHeight(eventListWidth: eventListWidth)
                )
            )
        case .todoDetail:
            .fixed(
                taskDetailSurfaceSize(
                    baseSize: expandedSurfaceSize,
                    notchHeight: notchHeight,
                    item: kind.taskDetailItem
                )
            )
        }
    }

    private func debugExpandedLeadingSlot() -> AnyView {
        NotchScene.erased {
            EmptyView()
        }
    }

    private func debugExpandedTrailingSlot() -> AnyView {
        NotchScene.erased {
            Button {
                Windows.shared.open(.settings)
            } label: {
                Image(systemName: "gear")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
    }
}
