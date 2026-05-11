import AppKit
import SwiftUI

private func splitRequestedEnvironment(from description: String) -> (body: String, requestedEnvironment: String?) {
    let marker = "\nRequested environment:"
    guard let range = description.range(of: marker) else {
        return (description.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    let body = description[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedEnvironment = description[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    return (body, requestedEnvironment.isEmpty ? nil : requestedEnvironment)
}

private enum NotchCardStyle {
    enum ActionButtonStyle {
        case emphasized
        case outlined
    }

    static let cornerRadius: CGFloat = 18
    static let cardPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let actionButtonCornerRadius: CGFloat = 7
    static let actionButtonBorderColor = Color.white.opacity(0.1)
    static let actionButtonFillColor = Color.white.opacity(0.2)

    static func background(for status: TaskViewModel.SurfaceItem.Status) -> Color {
        switch status {
        case .running:
            Color(hex: "1F1F1F")
        case .waiting:
            Color(hex: "222222")
        case .completed:
            Color(hex: "25D083").opacity(0.2)
        case .failed:
            Color(hex: "421515")
        case .cancelled:
            Color(hex: "463619")
        }
    }

    static func stroke(for status: TaskViewModel.SurfaceItem.Status) -> Color {
        switch status {
        case .running:
            .white.opacity(0.08)
        case .waiting:
            .white.opacity(0.08)
        case .completed:
            Color.green.opacity(0.24)
        case .failed:
            Color.red.opacity(0.22)
        case .cancelled:
            Color.yellow.opacity(0.22)
        }
    }

    static func accent(for status: TaskViewModel.SurfaceItem.Status) -> Color {
        switch status {
        case .running:
            .white.opacity(0.95)
        case .waiting:
            .white.opacity(0.9)
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .yellow
        }
    }

    static func actionButtonFill(for style: ActionButtonStyle) -> Color {
        switch style {
        case .emphasized:
            actionButtonFillColor
        case .outlined:
            .clear
        }
    }
}

struct NotchTaskCardView: View {
    let item: TaskViewModel.SurfaceItem
    let onOpenDetail: () -> Void
    let onOpenChat: () -> Void
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onAcceptFiles: () async throws -> Void

    @State private var isAccepting = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onOpenDetail) {
                HStack(alignment: .center, spacing: 10) {
                    icon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        subtitle
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                actionBar

                if item.isDismissible {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Notch.taskCardCloseButton)
                }
            }
            .fixedSize()
        }
        .padding(NotchCardStyle.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .fill(NotchCardStyle.background(for: item.status))
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchCardStyle.stroke(for: item.status))
                .allowsHitTesting(false)
        }
        .frame(minHeight: NotchExpandedSurfaceMetrics.taskCardHeight, alignment: .center)
        .accessibilityIdentifier(AccessibilityID.Notch.taskCard)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch item.status {
        case .running:
            ThinkingHighlightText(
                text: item.currentTodo ?? item.subtitle,
                font: .system(size: 11, weight: .regular),
                baseColor: .white.opacity(0.46),
                highlightColor: .white.opacity(0.94)
            )
            .lineLimit(1)
        default:
            Text(item.subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.status {
        case .running:
            AnimatedLogo(config: runningLogoConfig)
                .frame(width: 24, height: 24)
        case .waiting:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchCardStyle.accent(for: item.status))
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchCardStyle.accent(for: item.status))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchCardStyle.accent(for: item.status))
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchCardStyle.accent(for: item.status))
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        switch item.status {
        case .running, .waiting:
            actionButton(
                title: String(localized: "Open chat"),
                style: .emphasized,
                accessibilityID: AccessibilityID.Notch.taskCardOpenInChatButton,
                action: onOpenChat
            )
            actionButton(
                title: String(localized: "Cancel"),
                style: .outlined,
                accessibilityID: AccessibilityID.Notch.taskCardCancelButton,
                action: onCancel
            )
        case .completed:
            if !item.workspaceFiles.isEmpty {
                acceptButton
            }
            actionButton(
                title: String(localized: "Open chat"),
                style: .emphasized,
                accessibilityID: AccessibilityID.Notch.taskCardOpenInChatButton,
                action: onOpenChat
            )
        case .failed, .cancelled:
            actionButton(
                title: String(localized: "Open chat"),
                style: .emphasized,
                accessibilityID: AccessibilityID.Notch.taskCardOpenInChatButton,
                action: onOpenChat
            )
        }
    }

    private var acceptButton: some View {
        Button {
            guard !isAccepting else { return }

            isAccepting = true
            Task {
                defer { isAccepting = false }
                try? await onAcceptFiles()
            }
        } label: {
            HStack(spacing: 6) {
                if isAccepting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.92))
                }

                Text(String(localized: "Accept"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(
                    cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(NotchCardStyle.actionButtonFill(for: .emphasized))
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                    style: .continuous
                )
                .strokeBorder(NotchCardStyle.actionButtonBorderColor, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAccepting)
        .accessibilityIdentifier(AccessibilityID.Notch.taskCardAcceptButton)
    }

    private func actionButton(
        title: String,
        style: NotchCardStyle.ActionButtonStyle,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(
                        cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                        style: .continuous
                    )
                    .fill(NotchCardStyle.actionButtonFill(for: style))
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(NotchCardStyle.actionButtonBorderColor, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    private var runningLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .white
        config.strokeWidth = 1.5
        config.enterDrawDuration = 1.2
        config.enterMoveDuration = 1.2
        config.waitDuration = 0.3
        config.exitDrawDuration = 0.75
        config.exitMoveDuration = 0.75
        config.loopInterval = 0.15
        return config
    }
}

struct NotchPermissionCardView: View {
    let item: NotchViewModel.PermissionItem
    let onApprove: (String?) -> Void
    let onReject: () -> Void

    @State private var liveComputerUsePermissions: [SessionHistoryMessage.ComputerUsePermissionPane]?
    @State private var isOpeningComputerUsePermissions = false

    init(
        item: NotchViewModel.PermissionItem,
        onApprove: @escaping (String?) -> Void,
        onReject: @escaping () -> Void
    ) {
        self.item = item
        self.onApprove = onApprove
        self.onReject = onReject
        _liveComputerUsePermissions = State(initialValue: item.computerUseStart?.permissions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                permissionIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(cardTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(item.environmentLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(descriptionBody)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(3)

            if let computerUseStart = item.computerUseStart {
                computerUseFooter(computerUseStart)
            } else {
                genericPermissionFooter
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .fill(cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(cardStroke)
                .allowsHitTesting(false)
        }
        .task(id: item.id) {
            guard shouldUseLiveComputerUsePermissions else { return }
            await refreshComputerUsePermissions()
            while !Task.isCancelled, needsComputerUseAuthorization {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refreshComputerUsePermissions()
            }
        }
    }

    private var cardTitle: String {
        if item.computerUseStart != nil {
            return String(localized: "Agent wants to start ComputerUse")
        }
        return item.sessionTitle
    }

    private var descriptionBody: String {
        splitRequestedEnvironment(from: item.description).body
    }

    private var accentColor: Color {
        item.computerUseStart == nil ? Color(hex: "F2A23D") : .white.opacity(0.58)
    }

    private var cardBackground: Color {
        item.computerUseStart == nil ? Color(hex: "2B2620") : Color(hex: "1D1F22")
    }

    private var cardStroke: Color {
        item.computerUseStart == nil ? Color(hex: "F2A23D").opacity(0.2) : .white.opacity(0.08)
    }

    @ViewBuilder
    private var permissionIcon: some View {
        if item.computerUseStart != nil {
            Image(systemName: "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "F2A23D"))
                .frame(width: 22, alignment: .center)
        }
    }

    private var effectiveComputerUsePermissions: [SessionHistoryMessage.ComputerUsePermissionPane]? {
        liveComputerUsePermissions ?? item.computerUseStart?.permissions
    }

    private var missingComputerUsePermissions: [SessionHistoryMessage.ComputerUsePermissionPane] {
        (effectiveComputerUsePermissions ?? []).filter { !$0.granted }
    }

    private var shouldUseLiveComputerUsePermissions: Bool {
        item.computerUseStart != nil && item.confirmationId.hasPrefix("connector-")
    }

    private var needsComputerUseAuthorization: Bool {
        item.computerUseStart != nil && (effectiveComputerUsePermissions == nil || !missingComputerUsePermissions.isEmpty)
    }

    private var genericPermissionFooter: some View {
        HStack(spacing: 8) {
            panelActionButton(
                title: String(localized: "Approve"),
                style: .emphasized,
                action: { onApprove(nil) }
            )

            panelActionButton(
                title: String(localized: "Deny"),
                style: .outlined,
                action: onReject
            )
        }
    }

    private func computerUseFooter(_ computerUseStart: SessionHistoryMessage.ComputerUseStartInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let apps = computerUseStart.apps, !apps.isEmpty {
                Text(String(localized: "Apps in focus: \(apps.joined(separator: ", "))"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            if !missingComputerUsePermissions.isEmpty {
                Text(String(localized: "ComputerUse needs \(missingComputerUsePermissions.map { paneDisplayName($0.pane) }.joined(separator: " and "))."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "F2A23D"))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if needsComputerUseAuthorization {
                    ForEach(missingComputerUsePermissions, id: \.pane) { permission in
                        panelActionButton(
                            title: isOpeningComputerUsePermissions
                                ? String(localized: "Opening authorization…")
                                : String(localized: "Enable \(paneDisplayName(permission.pane))"),
                            style: .emphasized,
                            disabled: isOpeningComputerUsePermissions,
                            action: {
                                Task { await requestComputerUsePermission(permission.pane) }
                            }
                        )
                    }
                } else {
                    ForEach(computerUseStart.availableModes, id: \.self) { mode in
                        panelActionButton(
                            title: modeDisplayName(mode),
                            style: .emphasized,
                            action: { onApprove(mode) }
                        )
                    }
                }

                panelActionButton(
                    title: String(localized: "Deny"),
                    style: .outlined,
                    action: onReject
                )
            }
        }
    }

    private func refreshComputerUsePermissions() async {
        guard shouldUseLiveComputerUsePermissions else { return }
        liveComputerUsePermissions = ComputerUsePermissionService.status()
    }

    private func requestComputerUsePermission(_ pane: String) async {
        guard shouldUseLiveComputerUsePermissions, !isOpeningComputerUsePermissions else { return }
        isOpeningComputerUsePermissions = true
        defer { isOpeningComputerUsePermissions = false }

        do {
            liveComputerUsePermissions = try ComputerUsePermissionService.request(pane)
        } catch {
            await refreshComputerUsePermissions()
        }
    }

    private func paneDisplayName(_ pane: String) -> String {
        switch pane {
        case "accessibility":
            String(localized: "Accessibility")
        case "screen_recording", "screen-recording":
            String(localized: "Screen Recording")
        case "input_monitoring", "input-monitoring":
            String(localized: "Input Monitoring")
        default:
            pane
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private func modeDisplayName(_ mode: String) -> String {
        switch mode {
        case "allow":
            String(localized: "Allow")
        case "foreground":
            String(localized: "Foreground")
        case "background":
            String(localized: "Background")
        default:
            mode.prefix(1).uppercased() + String(mode.dropFirst())
        }
    }
}

struct NotchNotificationCardView: View {
    let item: NotchViewModel.NotificationItem
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.tint.opacity(0.18))
                    .frame(width: 28, height: 28)

                Image(systemName: item.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                Text(item.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let actionTitle = item.actionTitle {
                    compactActionButton(
                        title: actionTitle,
                        tint: .white.opacity(0.14),
                        foreground: .white.opacity(0.92),
                        action: onAction
                    )
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .fixedSize()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .fill(Color(hex: "1D1D1F"))
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotchCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
                .allowsHitTesting(false)
        }
    }
}

struct NotchTaskDetailView: View {
    let item: TaskViewModel.SurfaceItem
    let leadingInset: CGFloat
    let panelOffset: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotchExpandedSurfaceMetrics.detailRowSpacing) {
                if item.todos.isEmpty {
                    Text(String(localized: "No todo steps were recorded for this task yet."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchExpandedSurfaceMetrics.detailEmptyStateHeight, alignment: .topLeading)
                } else {
                    ForEach(Array(item.todos.enumerated()), id: \.offset) { entry in
                        todoRow(
                            entry.element,
                            index: entry.offset,
                            count: item.todos.count
                        )
                    }
                }
            }
            .padding(.leading, leadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func todoRow(
        _ todo: SessionHistoryMessage.TodoItem,
        index: Int,
        count: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusBullet(for: todo.status)
                .frame(width: 18, height: 18, alignment: .center)

            if todo.status == "in_progress" {
                ThinkingHighlightText(
                    text: todo.content,
                    font: .system(size: 13, weight: .medium),
                    baseColor: .white.opacity(0.46),
                    highlightColor: .white.opacity(0.96)
                )
            } else {
                Text(todo.content)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor(for: todo.status))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .offset(x: rowParallaxOffset(index: index, count: count))
        .animation(
            .smooth(duration: 0.38, extraBounce: 0)
                .delay(rowParallaxDelay(index: index, count: count)),
            value: panelOffset
        )
    }

    @ViewBuilder
    private func statusBullet(for status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        case "in_progress":
            AnimatedLogo(config: detailRunningLogoConfig)
                .frame(width: 20, height: 20)
        default:
            Circle()
                .strokeBorder(.white.opacity(0.38), lineWidth: 1.6)
                .frame(width: 14, height: 14)
        }
    }

    private func textColor(for status: String) -> Color {
        switch status {
        case "completed":
            .white.opacity(0.72)
        case "in_progress":
            .white.opacity(0.96)
        default:
            .white.opacity(0.38)
        }
    }

    private var detailRunningLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .white
        config.strokeWidth = 1.3
        config.enterDrawDuration = 1.15
        config.enterMoveDuration = 1.15
        config.waitDuration = 0.25
        config.exitDrawDuration = 0.7
        config.exitMoveDuration = 0.7
        config.loopInterval = 0.12
        return config
    }

    private func rowParallaxOffset(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let progress = CGFloat(index) / CGFloat(max(count - 1, 1))
        let extraTravel = 0.06 + progress * 0.18
        return panelOffset * extraTravel
    }

    private func rowParallaxDelay(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let progress = Double(index) / Double(max(count - 1, 1))
        return 0.018 + progress * 0.085
    }
}

private func panelActionButton(
    title: String,
    style: NotchCardStyle.ActionButtonStyle,
    disabled: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(disabled ? 0.42 : 0.92))
            .padding(.horizontal, 8)
            .frame(height: NotchExpandedSurfaceMetrics.permissionActionButtonHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                    style: .continuous
                )
                .fill(
                    disabled
                        ? Color.white.opacity(0.06)
                        : NotchCardStyle.actionButtonFill(for: style)
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: NotchCardStyle.actionButtonCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    disabled
                        ? Color.white.opacity(0.05)
                        : NotchCardStyle.actionButtonBorderColor,
                    lineWidth: 0.5
                )
            }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
}

private func compactActionButton(
    title: String,
    tint: Color,
    foreground: Color,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(tint, in: Capsule())
    }
    .buttonStyle(.plain)
}
