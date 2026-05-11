import SwiftUI

let notchExpandedSurfaceSize = CGSize(width: 600, height: 160)
let notchCompactSideWidth: CGFloat = 32
let notchRunningCompactSideWidth: CGFloat = 156

enum NotchDebugMockKind: String, CaseIterable, Identifiable {
    case taskList
    case todoDetail
    case permissions
    case computerUsePermissions
    case permissionSingleLong
    case permissionStackedLong
    case mixedAttention
    case notifications

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .taskList:
            String(localized: "Task List")
        case .todoDetail:
            String(localized: "Todo Detail")
        case .permissions:
            String(localized: "Permissions")
        case .computerUsePermissions:
            String(localized: "Computer Use Permissions")
        case .permissionSingleLong:
            String(localized: "Single Long Permission")
        case .permissionStackedLong:
            String(localized: "Stacked Long Permissions")
        case .mixedAttention:
            String(localized: "Mixed Attention")
        case .notifications:
            String(localized: "Notifications")
        }
    }

    var compactState: NotchViewModel.CompactState {
        switch self {
        case .taskList:
            .running(text: String(localized: "Implement the notch debug mock controls"), count: debugTaskItems.count)
        case .todoDetail:
            .running(
                text: debugDetailItem.currentTodo ?? String(localized: "Review the mock todo list"),
                count: 1
            )
        case .permissions,
             .computerUsePermissions,
             .permissionSingleLong,
             .permissionStackedLong,
             .mixedAttention,
             .notifications:
            .alert(count: eventItems.count)
        }
    }

    func expandedContentHeight(eventListWidth: CGFloat) -> CGFloat {
        switch self {
        case .taskList:
            NotchExpandedSurfaceMetrics.taskListContentHeight(taskCount: debugTaskItems.count)
        case .todoDetail:
            NotchExpandedSurfaceMetrics.detailContentHeight(todoCount: debugDetailItem.todos.count)
        case .permissions,
             .computerUsePermissions,
             .permissionSingleLong,
             .permissionStackedLong,
             .mixedAttention,
             .notifications:
            NotchExpandedSurfaceMetrics.eventListContentHeight(
                for: eventItems,
                eventListWidth: eventListWidth
            )
        }
    }

    var taskDetailItem: TaskViewModel.SurfaceItem? {
        switch self {
        case .todoDetail:
            debugDetailItem
        case .taskList,
             .permissions,
             .computerUsePermissions,
             .permissionSingleLong,
             .permissionStackedLong,
             .mixedAttention,
             .notifications:
            nil
        }
    }

    var eventItems: [NotchViewModel.EventItem] {
        switch self {
        case .permissions:
            debugPermissionItems.map(NotchViewModel.EventItem.permission)
        case .computerUsePermissions:
            debugComputerUsePermissionItems.map(NotchViewModel.EventItem.permission)
        case .permissionSingleLong:
            debugSingleLongPermissionItems.map(NotchViewModel.EventItem.permission)
        case .permissionStackedLong:
            debugStackedLongPermissionItems.map(NotchViewModel.EventItem.permission)
        case .mixedAttention:
            debugMixedAttentionItems
        case .notifications:
            debugNotificationItems.map(NotchViewModel.EventItem.notification)
        case .taskList, .todoDetail:
            []
        }
    }

    var eventListTitle: String {
        switch self {
        case .permissions, .computerUsePermissions, .permissionSingleLong, .permissionStackedLong, .mixedAttention:
            String(localized: "Needs attention")
        case .notifications:
            String(localized: "Recent updates")
        case .taskList:
            String(localized: "Task activity")
        case .todoDetail:
            String(localized: "Todo detail")
        }
    }

    var eventListSubtitle: String {
        switch self {
        case .permissions:
            String(localized: "Baseline permission requests for comparing short and medium descriptions.")
        case .computerUsePermissions:
            String(localized: "Computer use permission states for validating stacked icon alignment, chip treatments, and button enablement.")
        case .permissionSingleLong:
            String(localized: "One intentionally long permission card for validating single-card clipping and shell height.")
        case .permissionStackedLong:
            String(localized: "Multiple long permission cards for validating stacked layout, scrolling, and bottom blur.")
        case .mixedAttention:
            String(localized: "A long permission card plus notifications for validating mixed event stacks.")
        case .notifications:
            String(localized: "Mock notifications for tuning stacked event cards and scrolling.")
        case .taskList:
            String(localized: "Mock task cards for tuning expanded spacing and transitions.")
        case .todoDetail:
            String(localized: "Step through the mock todo list transitions.")
        }
    }
}

private let notchDebugTimestamp = Date().timeIntervalSince1970

private let debugTaskItems: [TaskViewModel.SurfaceItem] = [
    makeDebugTaskItem(
        sessionID: "debug-running-task",
        title: String(localized: "Ship the notch mock controls"),
        subtitle: String(localized: "Implement the preview actions and polish the controls."),
        status: .running,
        timestamp: notchDebugTimestamp,
        todos: [
            .init(content: String(localized: "Audit the current notch debug entry points"), status: "completed"),
            .init(content: String(localized: "Wire mock controls into the settings panel"), status: "in_progress"),
            .init(content: String(localized: "Build and verify the live notch scene"), status: "not_started"),
        ],
        currentTodo: String(localized: "Wire mock controls into the settings panel")
    ),
    makeDebugTaskItem(
        sessionID: "debug-waiting-task",
        title: String(localized: "Review permission card spacing"),
        subtitle: String(localized: "Waiting for a teammate to approve the latest copy changes."),
        status: .waiting,
        timestamp: notchDebugTimestamp - 120,
        todos: [
            .init(content: String(localized: "Compare the padding against the task cards"), status: "completed"),
            .init(content: String(localized: "Wait for the new copy review"), status: "not_started"),
        ]
    ),
    makeDebugTaskItem(
        sessionID: "debug-completed-task",
        title: String(localized: "Tune the task completion state"),
        subtitle: String(localized: "Task has been completed"),
        status: .completed,
        timestamp: notchDebugTimestamp - 240,
        todos: [
            .init(content: String(localized: "Run through the completion visuals"), status: "completed"),
            .init(content: String(localized: "Confirm the final card colors"), status: "completed"),
        ],
        workspaceFiles: [
            "~/workspace/openbridge/macos/OpenBridge/Interface/Notch/TasksView.swift",
        ],
        environmentID: "local-debug"
    ),
    makeDebugTaskItem(
        sessionID: "debug-failed-task",
        title: String(localized: "Inspect a failed agent run"),
        subtitle: String(localized: "Task failed"),
        status: .failed,
        timestamp: notchDebugTimestamp - 360,
        todos: [
            .init(content: String(localized: "Replay the failed history event"), status: "completed"),
            .init(content: String(localized: "Compare the failed icon treatment"), status: "completed"),
            .init(content: String(localized: "Retry the final build"), status: "not_started"),
        ],
        errorText: String(localized: "Missing mock permission payload")
    ),
]

private let debugDetailItem = makeDebugTaskItem(
    sessionID: "debug-detail-task",
    title: String(localized: "Implement the notch debug panel mocks"),
    subtitle: String(localized: "Step through the todo detail transitions"),
    status: .running,
    timestamp: notchDebugTimestamp,
    todos: [
        .init(content: String(localized: "Inspect the current debug settings structure"), status: "completed"),
        .init(content: String(localized: "Add mock task, todo, permission, and notification entry points"), status: "completed"),
        .init(content: String(localized: "Verify the expanded transitions against the mock todo list"), status: "in_progress"),
        .init(content: String(localized: "Rebuild and relaunch the app"), status: "not_started"),
    ],
    currentTodo: String(localized: "Verify the expanded transitions against the mock todo list")
)

private let debugPermissionItems: [NotchViewModel.PermissionItem] = [
    .init(
        id: "debug-permission-1",
        confirmationId: "debug-permission-1",
        sessionID: "debug-permission-session-1",
        sessionTitle: String(localized: "This Mac"),
        environmentLabel: String(localized: "This Mac"),
        description: String(localized: "Use ffmpeg to render a polished preview movie into ~/artifacts/notch-debug/notch-preview.mov."),
        timestamp: notchDebugTimestamp
    ),
    .init(
        id: "debug-permission-2",
        confirmationId: "debug-permission-2",
        sessionID: "debug-permission-session-2",
        sessionTitle: String(localized: "Remote Workspace"),
        environmentLabel: String(localized: "openbridge-dev"),
        description: String(localized: "Write the generated debug export into /workspace/out/notch-debug-export.json so the diff can be inspected."),
        timestamp: notchDebugTimestamp - 30
    ),
]

private let debugComputerUsePermissionDescription = String(
    localized: "Use Arc browser on your Mac to check Claude's recent updates.\nRequested environment: This Mac"
)

private let debugComputerUsePermissionItems: [NotchViewModel.PermissionItem] = [
    .init(
        id: "debug-computer-use-permission-none",
        confirmationId: "debug-computer-use-permission-none",
        sessionID: "debug-computer-use-permission-none-session",
        sessionTitle: String(localized: "Computer Use"),
        environmentLabel: String(localized: "This Mac"),
        kind: "computer_use_start",
        description: debugComputerUsePermissionDescription,
        computerUseStart: .init(
            availableModes: ["background", "foreground"],
            apps: ["Arc"],
            permissions: [
                .init(pane: "accessibility", granted: false),
                .init(pane: "screen_recording", granted: false),
            ]
        ),
        timestamp: notchDebugTimestamp - 6
    ),
    .init(
        id: "debug-computer-use-permission-mixed",
        confirmationId: "debug-computer-use-permission-mixed",
        sessionID: "debug-computer-use-permission-mixed-session",
        sessionTitle: String(localized: "Computer Use"),
        environmentLabel: String(localized: "This Mac"),
        kind: "computer_use_start",
        description: debugComputerUsePermissionDescription,
        computerUseStart: .init(
            availableModes: ["background", "foreground"],
            apps: ["Arc"],
            permissions: [
                .init(pane: "accessibility", granted: true),
                .init(pane: "screen_recording", granted: false),
            ]
        ),
        timestamp: notchDebugTimestamp - 12
    ),
    .init(
        id: "debug-computer-use-permission-granted",
        confirmationId: "debug-computer-use-permission-granted",
        sessionID: "debug-computer-use-permission-granted-session",
        sessionTitle: String(localized: "Computer Use"),
        environmentLabel: String(localized: "This Mac"),
        kind: "computer_use_start",
        description: debugComputerUsePermissionDescription,
        computerUseStart: .init(
            availableModes: ["background", "foreground"],
            apps: ["Arc"],
            permissions: [
                .init(pane: "accessibility", granted: true),
                .init(pane: "screen_recording", granted: true),
            ]
        ),
        timestamp: notchDebugTimestamp - 18
    ),
]

private let debugSingleLongPermissionItems: [NotchViewModel.PermissionItem] = [
    .init(
        id: "debug-permission-single-long",
        confirmationId: "debug-permission-single-long",
        sessionID: "debug-permission-single-long-session",
        sessionTitle: String(localized: "Preview Rendering"),
        environmentLabel: String(localized: "This Mac"),
        description: String(localized: "Run `/bin/zsh -lc 'ffmpeg -y -framerate 60 -pattern_type glob -i ~/Pictures/Notch Validation/*.png -vf scale=2560:-2 ~/Library/Application Support/OpenBridge/Debug Artifacts/Notch Validation/notch-regression-preview.mov'` and write both the preview movie and a JSON manifest into `~/Library/Application Support/OpenBridge/Debug Artifacts/Notch Validation/April Build 17/` so the visual diff can be reviewed after the run finishes."),
        timestamp: notchDebugTimestamp - 8
    ),
]

private let debugStackedLongPermissionItems: [NotchViewModel.PermissionItem] = [
    .init(
        id: "debug-permission-stacked-long-1",
        confirmationId: "debug-permission-stacked-long-1",
        sessionID: "debug-permission-stacked-long-session-1",
        sessionTitle: String(localized: "Artifact Packaging"),
        environmentLabel: String(localized: "openbridge-dev"),
        description: String(localized: "Create `/workspace/out/notch-debug/release/validation/report-with-inline-snapshots-and-shell-metrics.json`, include every expanded height sample collected during the pass, and keep the full nested directory structure intact so the resulting artifact can be attached to the issue without any manual cleanup."),
        timestamp: notchDebugTimestamp - 12
    ),
    .init(
        id: "debug-permission-stacked-long-2",
        confirmationId: "debug-permission-stacked-long-2",
        sessionID: "debug-permission-stacked-long-session-2",
        sessionTitle: String(localized: "Permission Preview"),
        environmentLabel: String(localized: "Local macOS Runner"),
        description: String(localized: "Capture a fresh permission preview sequence for the Notch approval flow, write the resized comparison set to `/tmp/bridge/notch/permission-height-validation/`, and preserve the timestamped filenames so the run can be correlated with the local trace."),
        timestamp: notchDebugTimestamp - 26
    ),
]

private let debugNotificationItems: [NotchViewModel.NotificationItem] = [
    .init(
        id: "debug-notification-1",
        symbolName: "checkmark.circle.fill",
        tint: .green,
        title: String(localized: "Task has been completed"),
        message: String(localized: "The debug notch build finished successfully and is ready to inspect."),
        actionTitle: String(localized: "Open chat"),
        timestamp: notchDebugTimestamp,
        action: nil,
        onDismiss: nil
    ),
    .init(
        id: "debug-notification-2",
        symbolName: "text.bubble.fill",
        tint: .orange,
        title: String(localized: "Permission request appeared in chat"),
        message: String(localized: "The conversation asked for approval to write a local preview artifact."),
        actionTitle: String(localized: "Review"),
        timestamp: notchDebugTimestamp - 24,
        action: nil,
        onDismiss: nil
    ),
    .init(
        id: "debug-notification-3",
        symbolName: "clock.badge.checkmark.fill",
        tint: .blue,
        title: String(localized: "Scheduled run updated"),
        message: String(localized: "The recurring mock task was rescheduled for the next debug cycle."),
        actionTitle: nil,
        timestamp: notchDebugTimestamp - 48,
        action: nil,
        onDismiss: nil
    ),
]

private let debugMixedAttentionItems: [NotchViewModel.EventItem] = [
    .permission(debugSingleLongPermissionItems[0]),
    .notification(debugNotificationItems[0]),
    .notification(debugNotificationItems[1]),
]

private func makeDebugTaskItem(
    sessionID: String,
    title: String,
    subtitle: String,
    status: TaskViewModel.SurfaceItem.Status,
    timestamp: Double,
    todos: [SessionHistoryMessage.TodoItem],
    currentTodo: String? = nil,
    workspaceFiles: [String] = [],
    environmentID: String? = nil,
    errorText: String? = nil
) -> TaskViewModel.SurfaceItem {
    .init(
        id: sessionID,
        sessionID: sessionID,
        title: title,
        subtitle: subtitle,
        status: status,
        timestamp: timestamp,
        todos: todos,
        currentTodo: currentTodo,
        workspaceFiles: workspaceFiles,
        environmentID: environmentID,
        errorText: errorText
    )
}

struct NotchExpandedLeadingSlotView: View {
    let viewModel: NotchViewModel

    var body: some View {
        Color.clear
    }
}

struct NotchExpandedTrailingSlotView: View {
    let viewModel: NotchViewModel

    var body: some View {
        Button {
            Windows.shared.open(.settings)
        } label: {
            Image(systemName: "gear")
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .padding(.trailing, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
    }
}

struct NotchExpandedContentView: View {
    let viewModel: NotchViewModel

    var body: some View {
        NotchExpandedSurfaceView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct NotchDebugExpandedContentView: View {
    let type: TaskViewModel.LiveInfoType
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statusSymbol
                    .frame(width: 14, height: 14)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardColor)
                .overlay(alignment: .leading) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(iconColor)
                            .frame(width: 24, height: 24)
                            .overlay {
                                cardSymbol
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(cardTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(cardSubtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 92)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch type {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.yellow)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)
        case .others:
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)
        }
    }

    @ViewBuilder
    private var cardSymbol: some View {
        switch type {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.black.opacity(0.85))
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        case .others:
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        }
    }

    private var title: String {
        switch type {
        case .running:
            "Running Preview"
        case .completed:
            "Completed Preview"
        case .others:
            "Queued Preview"
        case .failed:
            "Failed Preview"
        }
    }

    private var cardTitle: String {
        switch type {
        case .running:
            "Drafting release notes"
        case .completed:
            "Task finished successfully"
        case .others:
            "Waiting for next action"
        case .failed:
            "Task needs attention"
        }
    }

    private var cardSubtitle: String {
        switch type {
        case .running:
            "This card is only for notch tuning."
        case .completed:
            "Use this to tune closing and shadow behavior."
        case .others:
            "Useful for spacing and typography checks."
        case .failed:
            "Useful for color and alert state checks."
        }
    }

    private var iconColor: Color {
        switch type {
        case .running:
            .yellow
        case .completed:
            .green
        case .others:
            .white.opacity(0.85)
        case .failed:
            .red
        }
    }

    private var cardColor: Color {
        switch type {
        case .running:
            Color(red: 0.24, green: 0.21, blue: 0.08)
        case .completed:
            Color(red: 0.07, green: 0.24, blue: 0.12)
        case .others:
            Color.white.opacity(0.08)
        case .failed:
            Color(red: 0.26, green: 0.08, blue: 0.08)
        }
    }
}

struct NotchDebugMockExpandedContentView: View {
    let kind: NotchDebugMockKind

    var body: some View {
        Group {
            switch kind {
            case .taskList:
                debugTaskList
            case .todoDetail:
                debugTodoDetail
            case .permissions,
                 .computerUsePermissions,
                 .permissionSingleLong,
                 .permissionStackedLong,
                 .mixedAttention,
                 .notifications:
                debugEventItems
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var debugTaskList: some View {
        VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listSectionSpacing) {
            debugSectionHeader(
                title: String(localized: "Task activity"),
                subtitle: String(localized: "Mock task cards for tuning expanded spacing and transitions.")
            )
            .frame(height: NotchExpandedSurfaceMetrics.listHeaderHeight, alignment: .topLeading)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listItemSpacing) {
                    ForEach(debugTaskItems) { item in
                        NotchTaskCardView(
                            item: item,
                            onOpenDetail: {},
                            onOpenChat: {},
                            onCancel: {},
                            onDismiss: {},
                            onAcceptFiles: noopAcceptFiles
                        )
                    }
                }
                .padding(.bottom, NotchExpandedSurfaceMetrics.listBottomInset)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) {
                debugBottomEdgeBlur()
                    .padding(.horizontal, -NotchExpandedSurfaceMetrics.contentHorizontalPadding)
            }
        }
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
    }

    private var debugTodoDetail: some View {
        VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.detailHeaderBottomSpacing) {
            HStack(spacing: 10) {
                debugCircleButton(systemName: "arrow.left")

                Text(debugDetailItem.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    debugCircleButton(systemName: "arrow.up")
                    debugCircleButton(systemName: "arrow.down")
                }
            }
            .frame(height: NotchExpandedSurfaceMetrics.detailHeaderHeight)

            NotchTaskDetailView(
                item: debugDetailItem,
                leadingInset: NotchExpandedSurfaceMetrics.detailRowLeadingInset,
                panelOffset: 0
            )
        }
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
        .padding(.bottom, NotchExpandedSurfaceMetrics.detailBottomPadding)
    }

    private var debugEventItems: some View {
        debugEventList(
            title: kind.eventListTitle,
            subtitle: kind.eventListSubtitle
        ) {
            ForEach(kind.eventItems) { item in
                switch item {
                case let .permission(permission):
                    NotchPermissionCardView(
                        item: permission,
                        onApprove: { _ in },
                        onReject: {}
                    )
                case let .notification(notification):
                    NotchNotificationCardView(
                        item: notification,
                        onAction: {},
                        onDismiss: {}
                    )
                }
            }
        }
    }

    private func debugEventList(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listSectionSpacing) {
            debugSectionHeader(title: title, subtitle: subtitle)
                .frame(height: NotchExpandedSurfaceMetrics.listHeaderHeight, alignment: .topLeading)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listItemSpacing) {
                    content()
                }
                .padding(.bottom, NotchExpandedSurfaceMetrics.listBottomInset)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) {
                debugBottomEdgeBlur()
                    .padding(.horizontal, -NotchExpandedSurfaceMetrics.contentHorizontalPadding)
            }
        }
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
    }

    private func debugSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private func debugCircleButton(systemName: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func debugBottomEdgeBlur() -> some View {
        Rectangle()
            .fill(.clear)
            .background(.ultraThinMaterial)
            .mask(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.38),
                        .init(color: .black.opacity(0.7), location: 0.72),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: NotchExpandedSurfaceMetrics.listBottomEdgeBlurHeight)
            .allowsHitTesting(false)
    }

    private func noopAcceptFiles() async throws {}
}

#Preview("Running") {
    ZStack {
        Color.black
        NotchDebugExpandedContentView(type: .running, count: 3)
            .padding(16)
    }
    .frame(width: 600, height: 160)
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    ZStack {
        Color.black
        NotchDebugExpandedContentView(type: .failed, count: 1)
            .padding(16)
    }
    .frame(width: 600, height: 160)
    .preferredColorScheme(.dark)
}
