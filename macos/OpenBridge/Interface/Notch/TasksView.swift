import AppKit
import SwiftUI

enum NotchExpandedSurfaceMetrics {
    static let contentHorizontalPadding: CGFloat = 16
    static let detailBottomPadding: CGFloat = 16
    static let listBottomInset: CGFloat = 16
    static let listBottomEdgeBlurHeight: CGFloat = 28
    static let maximumListSurfaceHeight: CGFloat = 280
    static let listHeaderHeight: CGFloat = 34
    static let listSectionSpacing: CGFloat = 10
    static let listItemSpacing: CGFloat = 10
    static let minimumMeasuredListContentHeight: CGFloat = 60
    static let taskCardHeight: CGFloat = 48
    static let taskEmptyStateHeight: CGFloat = 92
    static let eventEmptyStateHeight: CGFloat = 108
    static let notificationCardEstimatedHeight: CGFloat = 84
    static let permissionCardPadding: CGFloat = 14
    static let permissionCardIconWidth: CGFloat = 22
    static let permissionCardRowSpacing: CGFloat = 10
    static let permissionCardHeaderSpacing: CGFloat = 4
    static let permissionActionButtonHeight: CGFloat = 22
    static let permissionFallbackDescriptionWidth: CGFloat = 280
    // Keep the SwiftUI and AppKit fonts aligned so the first-pass height estimate
    // matches the rendered permission card as closely as possible.
    static let permissionTitleFont = Font.system(size: 13, weight: .semibold)
    static let permissionTitleMeasureFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let permissionEnvironmentFont = Font.system(size: 11, weight: .semibold)
    static let permissionEnvironmentMeasureFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let permissionDescriptionFont = Font.system(size: 12, weight: .medium)
    static let permissionDescriptionMeasureFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let emptyStateCornerRadius: CGFloat = 18
    static let detailHeaderHeight: CGFloat = 28
    static let detailHeaderBottomSpacing: CGFloat = 12
    static let detailRowHeight: CGFloat = 28
    static let detailRowSpacing: CGFloat = 4
    static let detailEmptyStateHeight: CGFloat = 44
    static let detailRowLeadingInset: CGFloat = 5
    static let detailMaxHeight: CGFloat = 252

    static func minimumListContentHeight(emptyStateHeight: CGFloat) -> CGFloat {
        listHeaderHeight + listSectionSpacing + emptyStateHeight
    }

    static func taskListContentHeight(taskCount: Int) -> CGFloat {
        let bodyHeight: CGFloat
        if taskCount == 0 {
            bodyHeight = taskEmptyStateHeight
        } else {
            let cardsHeight = CGFloat(taskCount) * taskCardHeight
            let spacingHeight = CGFloat(max(0, taskCount - 1)) * listItemSpacing
            bodyHeight = cardsHeight + spacingHeight + listBottomInset
        }

        return listHeaderHeight + listSectionSpacing + bodyHeight
    }

    static func detailContentHeight(todoCount: Int) -> CGFloat {
        let bodyHeight: CGFloat
        if todoCount == 0 {
            bodyHeight = detailEmptyStateHeight
        } else {
            let rowsHeight = CGFloat(todoCount) * detailRowHeight
            let spacingHeight = CGFloat(max(0, todoCount - 1)) * detailRowSpacing
            bodyHeight = rowsHeight + spacingHeight
        }

        return detailHeaderHeight + detailHeaderBottomSpacing + bodyHeight + detailBottomPadding
    }

    static func eventListWidth(surfaceWidth: CGFloat, expandedPadding: EdgeInsets) -> CGFloat {
        max(
            0,
            surfaceWidth
                - expandedPadding.leading
                - expandedPadding.trailing
                - contentHorizontalPadding * 2
        )
    }

    static func permissionCardDescriptionWidth(eventListWidth: CGFloat) -> CGFloat {
        guard eventListWidth > 0 else { return permissionFallbackDescriptionWidth }
        return max(
            0,
            eventListWidth
                - permissionCardPadding * 2
                - permissionCardIconWidth
                - permissionCardRowSpacing
        )
    }

    static func estimatedPermissionCardHeight(description: String, eventListWidth: CGFloat) -> CGFloat {
        let descriptionHeight = measuredTextHeight(
            description,
            width: permissionCardDescriptionWidth(eventListWidth: eventListWidth),
            font: permissionDescriptionMeasureFont
        )
        let fixedHeight = (
            permissionCardPadding * 2
                + fontLineHeight(permissionTitleMeasureFont)
                + permissionCardHeaderSpacing
                + fontLineHeight(permissionEnvironmentMeasureFont)
                + permissionCardRowSpacing
                + permissionCardRowSpacing
                + permissionActionButtonHeight
        )
        return ceil(fixedHeight + descriptionHeight)
    }

    static func eventListContentHeight(
        for items: [NotchViewModel.EventItem],
        eventListWidth: CGFloat
    ) -> CGFloat {
        guard !items.isEmpty else {
            return minimumListContentHeight(emptyStateHeight: eventEmptyStateHeight)
        }

        let itemsHeight = items.reduce(CGFloat.zero) { partialResult, item in
            partialResult + estimatedEventItemHeight(item, eventListWidth: eventListWidth)
        }
        let spacingHeight = CGFloat(max(0, items.count - 1)) * listItemSpacing
        let bodyHeight = itemsHeight + spacingHeight + listBottomInset

        return listHeaderHeight + listSectionSpacing + bodyHeight
    }

    static func estimatedEventItemHeight(
        _ item: NotchViewModel.EventItem,
        eventListWidth: CGFloat
    ) -> CGFloat {
        switch item {
        case let .permission(permission):
            estimatedPermissionCardHeight(
                description: permission.description,
                eventListWidth: eventListWidth
            )
        case .notification:
            notificationCardEstimatedHeight
        }
    }

    private static func measuredTextHeight(
        _ text: String,
        width: CGFloat,
        font: NSFont
    ) -> CGFloat {
        // This file belongs to the macOS notch surface, so AppKit text measurement is
        // an acceptable source of truth for the pre-render height estimate here.
        guard width > 0, !text.isEmpty else { return 0 }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let boundingRect = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        return ceil(boundingRect.height)
    }

    private static func fontLineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}

struct NotchExpandedSurfaceView: View {
    let viewModel: NotchViewModel
    @State private var renderedDetailItem: TaskViewModel.SurfaceItem?
    @State private var detailPanelVisible = false
    @State private var eventMeasurementSignature = ""
    @State private var measuredEventListBodyHeight: CGFloat?
    @State private var measuredEventListWidth: CGFloat?

    var body: some View {
        Group {
            switch viewModel.expandedMode {
            case .events:
                eventList
            case .taskList, .taskDetail:
                taskPanels
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            syncRenderedDetailItem()
        }
        .onChange(of: viewModel.selectedTaskItem) { _, _ in
            syncRenderedDetailItem()
        }
    }

    private var eventList: some View {
        GeometryReader { geometry in
            let eventListWidth = geometry.size.width
            let sectionHeaderHeight = NotchExpandedSurfaceMetrics.listHeaderHeight
            let headerBlockHeight = sectionHeaderHeight + NotchExpandedSurfaceMetrics.listSectionSpacing
            let bodyViewportHeight = max(0, geometry.size.height - headerBlockHeight)
            let resolvedBodyHeight = eventListBodyHeight(for: eventListWidth)

            VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listSectionSpacing) {
                sectionHeader(
                    title: String(localized: "Needs attention"),
                    subtitle: String(localized: "Permission requests stay pinned above notifications.")
                )
                .frame(height: sectionHeaderHeight, alignment: .topLeading)

                if viewModel.eventItems.isEmpty {
                    emptyStateCard(
                        systemName: "checkmark.circle",
                        title: String(localized: "Nothing needs attention"),
                        subtitle: String(localized: "Permission requests and notifications will appear here."),
                        height: NotchExpandedSurfaceMetrics.eventEmptyStateHeight
                    )
                } else {
                    ScrollView(.vertical) {
                        eventListBody
                    }
                    .frame(height: bodyViewportHeight, alignment: .top)
                    .scrollIndicators(.hidden)
                    .background(alignment: .topLeading) {
                        measuredEventListBody(width: eventListWidth)
                    }
                    .overlay(alignment: .bottom) {
                        if resolvedBodyHeight > bodyViewportHeight + 1 {
                            taskListBottomEdgeBlur()
                                .padding(.horizontal, -NotchExpandedSurfaceMetrics.contentHorizontalPadding)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                syncEventMeasurementState(for: eventListWidth)
            }
            .onChange(of: viewModel.eventMeasurementSignature) { _, _ in
                syncEventMeasurementState(for: eventListWidth)
            }
            .onChange(of: eventListWidth) { _, newValue in
                syncEventMeasurementState(for: newValue)
            }
        }
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var taskPanels: some View {
        GeometryReader { geometry in
            let detailVisible = detailPanelVisible
            let panelWidth = geometry.size.width
            let listPanelOffset = detailVisible ? -panelWidth : 0
            let detailPanelOffset = detailVisible ? 0 : panelWidth

            ZStack(alignment: .topLeading) {
                taskList(panelOffset: listPanelOffset)
                    .frame(width: panelWidth, height: geometry.size.height, alignment: .topLeading)
                    .offset(x: listPanelOffset)
                    .allowsHitTesting(!detailVisible)

                if let item = viewModel.selectedTaskItem ?? renderedDetailItem {
                    taskDetail(item: item, panelOffset: detailPanelOffset)
                        .frame(width: panelWidth, height: geometry.size.height, alignment: .topLeading)
                        .offset(x: detailPanelOffset)
                        .allowsHitTesting(detailVisible)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .animation(.smooth(duration: 0.32, extraBounce: 0), value: detailVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func taskList(panelOffset: CGFloat) -> some View {
        let taskItems = viewModel.taskItems
        let taskIDs = taskItems.map(\.id)

        return VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listSectionSpacing) {
            taskListHeader
                .frame(height: NotchExpandedSurfaceMetrics.listHeaderHeight, alignment: .topLeading)

            if taskItems.isEmpty {
                emptyStateCard(
                    systemName: "sparkles",
                    title: String(localized: "No active tasks right now"),
                    subtitle: String(localized: "New task activity will appear here automatically."),
                    height: NotchExpandedSurfaceMetrics.taskEmptyStateHeight
                )
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listItemSpacing) {
                        ForEach(Array(taskItems.enumerated()), id: \.element.id) { entry in
                            NotchTaskCardView(
                                item: entry.element,
                                onOpenDetail: { viewModel.showTaskDetail(entry.element.sessionID) },
                                onOpenChat: { viewModel.openChat(for: entry.element.sessionID) },
                                onCancel: { viewModel.cancelTask(entry.element.sessionID) },
                                onDismiss: { viewModel.dismissTask(entry.element.sessionID) },
                                onAcceptFiles: { try await viewModel.acceptTaskFiles(entry.element) }
                            )
                            .transition(taskCardMutationTransition)
                            .offset(
                                x: parallaxOffset(
                                    panelOffset: panelOffset,
                                    index: entry.offset,
                                    count: taskItems.count
                                )
                            )
                            .animation(
                                .smooth(duration: 0.38, extraBounce: 0)
                                    .delay(parallaxDelay(index: entry.offset, count: taskItems.count)),
                                value: panelOffset
                            )
                        }
                    }
                    .padding(.bottom, NotchExpandedSurfaceMetrics.listBottomInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(taskCardMutationAnimation, value: taskIDs)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .bottom) {
                    if taskItems.count > 3 {
                        taskListBottomEdgeBlur()
                            .padding(.horizontal, -NotchExpandedSurfaceMetrics.contentHorizontalPadding)
                    }
                }
            }
        }
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var taskListHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            sectionHeader(
                title: String(localized: "Task activity"),
                subtitle: String(localized: "Open a card to inspect the full todo list.")
            )

            Spacer(minLength: 12)

            if viewModel.hasCompletedTaskItems {
                clearCompletedTasksButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .animation(.smooth(duration: 0.18, extraBounce: 0), value: viewModel.hasCompletedTaskItems)
    }

    private var clearCompletedTasksButton: some View {
        Button(action: viewModel.clearCompletedTasks) {
            Text(String(localized: "Clear Completed Tasks"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Notch.clearCompletedTasksButton)
    }

    private var eventListBody: some View {
        VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.listItemSpacing) {
            ForEach(viewModel.eventItems) { item in
                eventCard(for: item)
            }
        }
        .padding(.bottom, NotchExpandedSurfaceMetrics.listBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventListBodyHeight(for width: CGFloat) -> CGFloat {
        guard !viewModel.eventItems.isEmpty else {
            return NotchExpandedSurfaceMetrics.eventEmptyStateHeight
        }
        if let measuredEventListBodyHeight,
           let measuredEventListWidth,
           abs(measuredEventListWidth - width) <= 0.5
        {
            return measuredEventListBodyHeight
        }
        return estimatedEventListBodyHeight(for: width)
    }

    private func taskDetail(item: TaskViewModel.SurfaceItem, panelOffset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.detailHeaderBottomSpacing) {
            detailHeader(item: item)
                .transaction { transaction in
                    transaction.animation = nil
                }

            ZStack(alignment: .topLeading) {
                NotchTaskDetailView(
                    item: item,
                    leadingInset: NotchExpandedSurfaceMetrics.detailRowLeadingInset,
                    panelOffset: panelOffset
                )
                .id(item.sessionID)
                .transition(taskDetailContentTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(
                .smooth(duration: 0.24, extraBounce: 0),
                value: viewModel.selectedTaskItem?.sessionID
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(.horizontal, NotchExpandedSurfaceMetrics.contentHorizontalPadding)
        .padding(.bottom, NotchExpandedSurfaceMetrics.detailBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var taskDetailContentTransition: AnyTransition {
        guard viewModel.expandedTransitionKind == .detailNavigation else {
            return .identity
        }

        return .asymmetric(
            insertion: .modifier(
                active: BlurReplaceTransitionModifier(radius: 18, opacity: 0, scale: 0.992),
                identity: BlurReplaceTransitionModifier(radius: 0, opacity: 1, scale: 1)
            ),
            removal: .modifier(
                active: BlurReplaceTransitionModifier(radius: 18, opacity: 0, scale: 1.008),
                identity: BlurReplaceTransitionModifier(radius: 0, opacity: 1, scale: 1)
            )
        )
    }

    private func syncRenderedDetailItem() {
        if let selectedTaskItem = viewModel.selectedTaskItem {
            renderedDetailItem = selectedTaskItem
            detailPanelVisible = true
            return
        }

        detailPanelVisible = false
    }

    private func syncEventListContentHeight(for width: CGFloat) {
        viewModel.updateMeasuredEventListContentHeight(
            NotchExpandedSurfaceMetrics.listHeaderHeight
                + NotchExpandedSurfaceMetrics.listSectionSpacing
                + eventListBodyHeight(for: width),
            width: width
        )
    }

    private func syncEventMeasurementState(for width: CGFloat) {
        let signature = viewModel.eventMeasurementSignature
        let widthDidChange = abs((measuredEventListWidth ?? 0) - width) > 0.5
        if eventMeasurementSignature != signature || widthDidChange {
            eventMeasurementSignature = signature
            measuredEventListBodyHeight = nil
            measuredEventListWidth = nil
        }
        syncEventListContentHeight(for: width)
    }

    private func updateMeasuredEventListBodyHeight(_ height: CGFloat, width: CGFloat) {
        let resolvedHeight = max(
            NotchExpandedSurfaceMetrics.eventEmptyStateHeight,
            height.rounded(.toNearestOrEven)
        )
        let widthDidChange = abs((measuredEventListWidth ?? 0) - width) > 0.5
        guard widthDidChange || abs((measuredEventListBodyHeight ?? 0) - resolvedHeight) > 0.5 else { return }
        measuredEventListBodyHeight = resolvedHeight
        measuredEventListWidth = width
        syncEventListContentHeight(for: width)
    }

    private func estimatedEventListBodyHeight(for width: CGFloat) -> CGFloat {
        let itemsHeight = viewModel.eventItems.reduce(CGFloat.zero) { partialResult, item in
            partialResult + estimatedHeight(for: item, width: width)
        }
        let spacingHeight = CGFloat(max(0, viewModel.eventItems.count - 1)) * NotchExpandedSurfaceMetrics.listItemSpacing
        return itemsHeight + spacingHeight + NotchExpandedSurfaceMetrics.listBottomInset
    }

    private func estimatedHeight(for item: NotchViewModel.EventItem, width: CGFloat) -> CGFloat {
        NotchExpandedSurfaceMetrics.estimatedEventItemHeight(item, eventListWidth: width)
    }

    @ViewBuilder
    private func eventCard(for item: NotchViewModel.EventItem) -> some View {
        switch item {
        case let .permission(permission):
            NotchPermissionCardView(
                item: permission,
                onApprove: { mode in viewModel.approvePermission(permission, mode: mode) },
                onReject: { viewModel.rejectPermission(permission) }
            )
        case let .notification(notification):
            NotchNotificationCardView(
                item: notification,
                onAction: { viewModel.performNotificationAction(id: notification.id) },
                onDismiss: { viewModel.dismissNotification(id: notification.id) }
            )
        }
    }

    private func measuredEventListBody(width: CGFloat) -> some View {
        eventListBody
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .onMeasuredHeightChange { updateMeasuredEventListBodyHeight($0, width: width) }
    }

    private func parallaxOffset(panelOffset: CGFloat, index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
        let extraTravel = 0.06 + progress * 0.18
        return panelOffset * extraTravel
    }

    private func parallaxDelay(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let progress = Double(index) / Double(max(count - 1, 1))
        return 0.018 + progress * 0.085
    }

    private func detailHeader(item: TaskViewModel.SurfaceItem) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.showTaskList()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                detailNavigationButton(
                    systemName: "arrow.up",
                    disabled: !viewModel.canNavigateToPreviousTask,
                    action: viewModel.showPreviousTask
                )

                detailNavigationButton(
                    systemName: "arrow.down",
                    disabled: !viewModel.canNavigateToNextTask,
                    action: viewModel.showNextTask
                )
            }
        }
        .frame(height: NotchExpandedSurfaceMetrics.detailHeaderHeight)
    }

    private var taskCardMutationAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.08)
    }

    private var taskCardMutationTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TaskCardMutationTransitionModifier(
                    opacity: 0,
                    scaleX: 0.96,
                    scaleY: 0.94,
                    offsetY: 18
                ),
                identity: TaskCardMutationTransitionModifier(
                    opacity: 1,
                    scaleX: 1,
                    scaleY: 1,
                    offsetY: 0
                )
            ),
            removal: .modifier(
                active: TaskCardMutationTransitionModifier(
                    opacity: 0,
                    scaleX: 0.98,
                    scaleY: 0.72,
                    offsetY: 0
                ),
                identity: TaskCardMutationTransitionModifier(
                    opacity: 1,
                    scaleX: 1,
                    scaleY: 1,
                    offsetY: 0
                )
            )
        )
    }

    private func detailNavigationButton(
        systemName: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .white.opacity(0.3) : .white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(disabled ? 0.08 : 0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
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

    private func emptyStateCard(
        systemName: String,
        title: String,
        subtitle: String,
        height: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 30, height: 30)

                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: NotchExpandedSurfaceMetrics.emptyStateCornerRadius,
                style: .continuous
            )
            .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: NotchExpandedSurfaceMetrics.emptyStateCornerRadius,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.08))
        }
    }
}

private struct BlurReplaceTransitionModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

private struct TaskCardMutationTransitionModifier: ViewModifier {
    let opacity: Double
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
            .offset(y: offsetY)
    }
}

private extension View {
    func onMeasuredHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: NotchMeasuredHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(NotchMeasuredHeightKey.self, perform: action)
    }

    func taskListBottomEdgeBlur() -> some View {
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
}

private struct NotchMeasuredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
