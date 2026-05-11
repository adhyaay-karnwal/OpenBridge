import SwiftUI

public struct WindowNotificationStack<Item: Identifiable, Card: View>: View where Item.ID: Hashable {
    public let items: [Item]
    public let configuration: WindowNotificationStackConfiguration

    private let maximumExpandedHeight: CGFloat?
    private let onDismiss: ((Item.ID) -> Void)?
    private let card: (Item, WindowNotificationCardContext) -> Card

    @State private var measuredSizes: [MeasurementKey: CGSize] = [:]
    @State private var isPointerHovering = false
    @State private var isHoverExpansionActive = false
    @State private var isAutomaticExpansionSuspended = false
    @State private var hoverExpansionTask: Task<Void, Never>?

    public init(
        items: [Item],
        configuration: WindowNotificationStackConfiguration = .sonner,
        onDismiss: ((Item.ID) -> Void)? = nil,
        maximumExpandedHeight: CGFloat? = nil,
        @ViewBuilder card: @escaping (Item, WindowNotificationCardContext) -> Card
    ) {
        self.items = items
        self.configuration = configuration
        self.onDismiss = onDismiss
        self.maximumExpandedHeight = maximumExpandedHeight
        self.card = card
    }

    public var body: some View {
        if renderedItems.isEmpty {
            EmptyView()
        } else {
            let layout = makeLayoutSnapshot()

            ZStack(alignment: .top) {
                presentedBody(layout: layout)
            }
            .onPreferenceChange(WindowNotificationMeasuredSizePreferenceKey.self, perform: mergeMeasurements)
            .onHover(perform: handleHoverChange)
            .onChange(of: isAutomaticExpansionSuspended, initial: false) { _, suspended in
                handleAutomaticExpansionSuspensionChange(suspended)
            }
            .onDisappear {
                hoverExpansionTask?.cancel()
            }
            .animation(configuration.animation, value: animationSignature)
        }
    }

    private var renderedItems: [Item] {
        if isExpanded {
            expandedItems
        } else {
            collapsedItems
        }
    }

    private var collapsedItems: [Item] {
        Array(items.prefix(normalizedMaximumCollapsedCards))
    }

    private var expandedItems: [Item] {
        Array(items.prefix(normalizedMaximumExpandedCards ?? items.count))
    }

    private var normalizedMaximumExpandedCards: Int? {
        guard let maximumExpandedCards = configuration.maximumExpandedCards else {
            return nil
        }

        return max(maximumExpandedCards, normalizedMaximumCollapsedCards)
    }

    private var normalizedMaximumExpandedHeight: CGFloat? {
        guard let maximumExpandedHeight else {
            return nil
        }

        return max(maximumExpandedHeight, 1)
    }

    private var normalizedMaximumCollapsedCards: Int {
        max(1, configuration.maximumCollapsedCards)
    }

    private var normalizedMaximumWidth: CGFloat {
        max(configuration.maximumWidth, 1)
    }

    private var isExpanded: Bool {
        switch configuration.expansionBehavior {
        case .hover:
            configuration.expandsOnHover && isHoverExpansionActive && expandedItems.count > 1
        case .collapsed:
            false
        case .expanded:
            true
        }
    }

    private var displayMode: WindowNotificationDisplayMode {
        isExpanded ? .expanded : .collapsed
    }

    private var animationSignature: [Double] {
        var signature = [isExpanded ? 1.0 : 0.0, Double(renderedItems.count)]

        for item in renderedItems {
            let key = MeasurementKey(item.id)
            let size = measuredSizes[key] ?? .zero
            signature.append(Double(size.width.rounded(.toNearestOrAwayFromZero)))
            signature.append(Double(size.height.rounded(.toNearestOrAwayFromZero)))
        }

        return signature
    }

    @ViewBuilder
    private func presentedBody(layout: LayoutSnapshot) -> some View {
        let shouldScroll = shouldScrollExpandedContent(layout: layout)

        ScrollView(.vertical) {
            stackBody(layout: layout)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, bottomPadding(for: shouldScroll))
        }
        .scrollDisabled(!shouldScroll)
        .scrollIndicators(shouldScroll ? .visible : .hidden)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: !shouldScroll)
        .frame(
            width: normalizedMaximumWidth,
            height: shouldScroll ? expandedViewportHeight(for: layout) : nil,
            alignment: .top
        )
    }

    private func bottomPadding(for shouldScroll: Bool) -> CGFloat {
        if isExpanded {
            return configuration.contentBottomInset
        }

        if shouldScroll {
            return configuration.contentBottomInset
        }

        return max(configuration.collapsedMaskOverflowInsets.bottom, configuration.contentBottomInset, 0)
    }

    @ViewBuilder
    private func stackBody(layout: LayoutSnapshot) -> some View {
        if let containerSize = layout.containerSize {
            stackContent(layout: layout)
                .frame(
                    width: normalizedMaximumWidth,
                    height: max(containerSize.height, 1),
                    alignment: .topLeading
                )
        } else {
            stackContent(layout: layout)
                .frame(width: normalizedMaximumWidth, alignment: .topLeading)
        }
    }

    private func expandedViewportHeight(for layout: LayoutSnapshot) -> CGFloat? {
        guard isExpanded else { return nil }
        guard let maximumExpandedHeight = normalizedMaximumExpandedHeight else {
            return nil
        }

        if let contentHeight = layout.containerSize?.height {
            return min(contentHeight, maximumExpandedHeight)
        }

        return maximumExpandedHeight
    }

    private func stackContent(layout: LayoutSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(renderedItems.enumerated()), id: \.element.id) { index, item in
                let key = MeasurementKey(item.id)
                let placement = layout.placements[key] ?? .zero
                let collapsedMaskHeight = collapsedMaskHeight(for: placement, layout: layout, index: index)

                card(item, cardContext(for: item, index: index))
                    .frame(width: normalizedMaximumWidth, alignment: .topLeading)
                    .background(WindowNotificationSizeReader(id: item.id))
                    .scaleEffect(placement.scale, anchor: .top)
                    .modifier(
                        WindowNotificationCollapsedMaskModifier(
                            width: normalizedMaximumWidth,
                            height: collapsedMaskHeight,
                            overflowInsets: configuration.collapsedMaskOverflowInsets
                        )
                    )
                    .offset(x: placement.origin.x, y: placement.origin.y)
                    .zIndex(placement.zIndex)
                    .allowsHitTesting(isExpanded || index == 0)
                    .transition(cardTransition(for: index))
            }
        }
    }

    private func collapsedMaskHeight(for placement: Placement, layout: LayoutSnapshot, index: Int) -> CGFloat? {
        guard !isExpanded else { return nil }
        guard index > 0 else { return nil }
        guard let containerHeight = layout.containerSize?.height else { return nil }

        return max(containerHeight - placement.origin.y, 0)
    }

    private func shouldScrollExpandedContent(layout: LayoutSnapshot) -> Bool {
        guard isExpanded else { return false }
        guard configuration.allowsExpandedScrolling else { return false }
        guard let contentHeight = layout.containerSize?.height else { return false }
        guard let maximumExpandedHeight = normalizedMaximumExpandedHeight else {
            return false
        }

        return contentHeight > maximumExpandedHeight
    }

    private func cardTransition(for index: Int) -> AnyTransition {
        if index == 0 {
            return .asymmetric(
                insertion: .offset(y: -24)
                    .combined(with: .scale(scale: 0.94, anchor: .top))
                    .combined(with: .opacity),
                removal: .offset(y: -28)
                    .combined(with: .scale(scale: 0.92, anchor: .top))
                    .combined(with: .opacity)
            )
        }

        return .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    private func cardContext(for item: Item, index: Int) -> WindowNotificationCardContext {
        WindowNotificationCardContext(
            index: index,
            displayMode: displayMode,
            canDismiss: onDismiss != nil,
            dismissAction: {
                onDismiss?(item.id)
            },
            automaticExpansionSuspensionAction: { suspended in
                guard configuration.expansionBehavior == .hover else { return }
                isAutomaticExpansionSuspended = suspended
            }
        )
    }

    private func handleHoverChange(_ hovering: Bool) {
        guard configuration.expansionBehavior == .hover else { return }
        guard configuration.expandsOnHover else { return }

        isPointerHovering = hovering

        if hovering {
            scheduleHoverExpansionActivationIfNeeded()
            return
        }

        hoverExpansionTask?.cancel()
        withAnimation(configuration.animation) {
            isHoverExpansionActive = false
        }
    }

    private func handleAutomaticExpansionSuspensionChange(_ suspended: Bool) {
        guard configuration.expansionBehavior == .hover else { return }
        guard configuration.expandsOnHover else { return }

        if suspended {
            hoverExpansionTask?.cancel()
            return
        }

        scheduleHoverExpansionActivationIfNeeded()
    }

    private func scheduleHoverExpansionActivationIfNeeded() {
        hoverExpansionTask?.cancel()

        guard configuration.expansionBehavior == .hover else { return }
        guard configuration.expandsOnHover else { return }
        guard isPointerHovering else { return }
        guard !isAutomaticExpansionSuspended else { return }
        guard expandedItems.count > 1 else { return }

        hoverExpansionTask = Task { @MainActor in
            try? await Task.sleep(for: configuration.hoverExpansionDelay)
            guard !Task.isCancelled else { return }
            guard isPointerHovering else { return }
            guard !isAutomaticExpansionSuspended else { return }

            withAnimation(configuration.animation) {
                isHoverExpansionActive = true
            }
        }
    }

    private func makeLayoutSnapshot() -> LayoutSnapshot {
        let ids = renderedItems.map { MeasurementKey($0.id) }
        let sizes = ids.map { measuredSizes[$0] ?? .zero }

        var placements: [MeasurementKey: Placement] = [:]

        if isExpanded {
            var yOffset: CGFloat = 0

            for (index, id) in ids.enumerated() {
                placements[id] = Placement(
                    origin: CGPoint(x: 0, y: yOffset),
                    scale: 1,
                    zIndex: Double(ids.count - index)
                )
                yOffset += sizes[index].height

                if index < ids.count - 1 {
                    yOffset += configuration.expandedSpacing
                }
            }

            guard ids.allSatisfy({ measuredSizes[$0]?.height ?? 0 > 0 }) else {
                return LayoutSnapshot(containerSize: nil, placements: placements)
            }

            return LayoutSnapshot(
                containerSize: CGSize(width: normalizedMaximumWidth, height: max(yOffset, 0)),
                placements: placements
            )
        }

        let topInset = CGFloat(max(ids.count - 1, 0)) * configuration.collapsedPeek
        let frontHeight = sizes.first?.height ?? 0

        for (index, id) in ids.enumerated() {
            let depth = CGFloat(index)
            let scale = max(
                configuration.minimumCollapsedScale,
                1 - depth * configuration.collapsedScaleStep
            )

            placements[id] = Placement(
                origin: CGPoint(
                    x: 0,
                    y: topInset - depth * configuration.collapsedPeek
                ),
                scale: scale,
                zIndex: Double(ids.count - index)
            )
        }

        guard frontHeight > 0 else {
            return LayoutSnapshot(containerSize: nil, placements: placements)
        }

        return LayoutSnapshot(
            containerSize: CGSize(width: normalizedMaximumWidth, height: frontHeight + topInset),
            placements: placements
        )
    }

    private func mergeMeasurements(_ updates: [MeasurementKey: CGSize]) {
        var next = measuredSizes
        var didChange = false

        for (key, size) in updates where size.isMeaningful {
            if let existing = next[key], existing.isApproximatelyEqual(to: size) {
                continue
            }

            next[key] = size
            didChange = true
        }

        guard didChange else { return }
        measuredSizes = next
    }
}

private struct LayoutSnapshot {
    let containerSize: CGSize?
    let placements: [MeasurementKey: Placement]
}

private struct MeasurementKey: Hashable, @unchecked Sendable {
    let rawValue: AnyHashable

    init(_ rawValue: some Hashable) {
        self.rawValue = AnyHashable(rawValue)
    }
}

private struct Placement {
    let origin: CGPoint
    let scale: CGFloat
    let zIndex: Double

    static let zero = Placement(
        origin: .zero,
        scale: 1,
        zIndex: 0
    )
}

private struct WindowNotificationCollapsedMaskModifier: ViewModifier {
    let width: CGFloat
    let height: CGFloat?
    let overflowInsets: EdgeInsets

    func body(content: Content) -> some View {
        if let height, height > 0 {
            content
                .compositingGroup()
                .mask(alignment: .topLeading) {
                    WindowNotificationCollapsedMaskShape(
                        width: width + overflowInsets.leading + overflowInsets.trailing,
                        visibleHeight: height + overflowInsets.top,
                        fadeHeight: overflowInsets.bottom
                    )
                    .offset(x: -overflowInsets.leading, y: -overflowInsets.top)
                }
        } else {
            content
        }
    }
}

private struct WindowNotificationCollapsedMaskShape: View {
    let width: CGFloat
    let visibleHeight: CGFloat
    let fadeHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .frame(width: width, height: visibleHeight)

            if fadeHeight > 0 {
                LinearGradient(
                    colors: [.white, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: fadeHeight)
            }
        }
    }
}

private struct WindowNotificationMeasuredSizePreferenceKey: PreferenceKey {
    static let defaultValue: [MeasurementKey: CGSize] = [:]

    static func reduce(value: inout [MeasurementKey: CGSize], nextValue: () -> [MeasurementKey: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct WindowNotificationSizeReader<ID: Hashable>: View {
    let id: ID

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: WindowNotificationMeasuredSizePreferenceKey.self,
                    value: [MeasurementKey(id): proxy.size]
                )
        }
    }
}

private extension CGSize {
    var isMeaningful: Bool {
        width > 0 && height > 0
    }

    func isApproximatelyEqual(to other: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

#if DEBUG
    private struct WindowNotificationPreviewPalette {
        let surfaceBackground: Color
        let primaryText: Color
        let secondaryText: Color
        let tertiaryText: Color
        let panelBackground: Color
        let panelBorder: Color
        let cardBackground: Color
        let cardBorder: Color
        let closeButtonForeground: Color
        let closeButtonBackground: Color
        let shadow: Color

        static func make(for colorScheme: ColorScheme) -> Self {
            if colorScheme == .dark {
                return Self(
                    surfaceBackground: Color(red: 0.07, green: 0.08, blue: 0.10),
                    primaryText: .white,
                    secondaryText: .white.opacity(0.82),
                    tertiaryText: .white.opacity(0.56),
                    panelBackground: .white.opacity(0.04),
                    panelBorder: .white.opacity(0.08),
                    cardBackground: Color(red: 0.12, green: 0.13, blue: 0.15),
                    cardBorder: .white.opacity(0.08),
                    closeButtonForeground: .white.opacity(0.62),
                    closeButtonBackground: .white.opacity(0.08),
                    shadow: .black.opacity(0.22)
                )
            }

            return Self(
                surfaceBackground: Color(red: 0.95, green: 0.96, blue: 0.98),
                primaryText: Color(red: 0.13, green: 0.14, blue: 0.17),
                secondaryText: Color(red: 0.23, green: 0.25, blue: 0.30),
                tertiaryText: Color(red: 0.36, green: 0.39, blue: 0.45),
                panelBackground: .white.opacity(0.88),
                panelBorder: .black.opacity(0.08),
                cardBackground: .white,
                cardBorder: .black.opacity(0.08),
                closeButtonForeground: .black.opacity(0.55),
                closeButtonBackground: .black.opacity(0.05),
                shadow: .black.opacity(0.10)
            )
        }
    }

    private struct PreviewNotification: Identifiable {
        enum Tone: String, CaseIterable {
            case success
            case info
            case warning
            case error

            var accent: Color {
                switch self {
                case .success:
                    Color(red: 0.33, green: 0.88, blue: 0.62)
                case .info:
                    Color(red: 0.39, green: 0.72, blue: 1.0)
                case .warning:
                    Color(red: 1.0, green: 0.74, blue: 0.34)
                case .error:
                    Color(red: 1.0, green: 0.48, blue: 0.45)
                }
            }

            var symbol: String {
                switch self {
                case .success:
                    "checkmark.circle.fill"
                case .info:
                    "bolt.horizontal.circle.fill"
                case .warning:
                    "exclamationmark.triangle.fill"
                case .error:
                    "xmark.octagon.fill"
                }
            }
        }

        let id = UUID()
        let tone: Tone
        let title: String
        let message: String
        let meta: String

        static let sample: [PreviewNotification] = [
            PreviewNotification(
                tone: .success,
                title: "Build Ready",
                message: "Unsigned Debug finished and the latest bundle is available in DerivedData.",
                meta: "just now"
            ),
            PreviewNotification(
                tone: .warning,
                title: "Workspace Needs Attention",
                message: "Embedded chat assets changed and should be rebuilt before the next launch.",
                meta: "2m ago"
            ),
            PreviewNotification(
                tone: .info,
                title: "Shortcut Updated",
                message: "Capture flow now listens for a new hotkey across all active spaces.",
                meta: "5m ago"
            ),
            PreviewNotification(
                tone: .error,
                title: "Upload Failed",
                message: "The screenshot sync job timed out while waiting for the remote agent response.",
                meta: "7m ago"
            ),
            PreviewNotification(
                tone: .info,
                title: "Workspace Indexed",
                message: "Search metadata finished updating and recent files are now available to the quick switcher.",
                meta: "12m ago"
            ),
            PreviewNotification(
                tone: .success,
                title: "Sync Complete",
                message: "Cloud preferences were pulled successfully and applied to the current window session.",
                meta: "18m ago"
            ),
            PreviewNotification(
                tone: .warning,
                title: "Action Deferred",
                message: "One long-running task was postponed because the current workspace is still preparing its resources.",
                meta: "24m ago"
            ),
            PreviewNotification(
                tone: .error,
                title: "Upload Retrying",
                message: "The agent queue reported a transient network issue and scheduled another attempt in the background.",
                meta: "31m ago"
            ),
        ]
    }

    private struct PreviewNotificationCard: View {
        @Environment(\.colorScheme) private var colorScheme

        let notification: PreviewNotification
        let context: WindowNotificationCardContext

        private var palette: WindowNotificationPreviewPalette {
            .make(for: colorScheme)
        }

        private var cardShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        }

        private var cardMaterial: Material {
            colorScheme == .dark ? .ultraThinMaterial : .thinMaterial
        }

        private var cardTintOpacity: Double {
            colorScheme == .dark ? 0.14 : 0.06
        }

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(notification.tone.accent.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    Image(systemName: notification.tone.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(notification.tone.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(notification.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(notification.meta)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.tertiaryText)
                    }

                    Text(notification.message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                        .lineSpacing(1.5)

                    if context.isExpanded || context.isFrontmost {
                        Text(context.isExpanded ? "OpenBridge • Expanded" : "OpenBridge • Front")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.tertiaryText)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if context.canDismiss {
                    Button {
                        context.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.closeButtonForeground)
                            .frame(width: 22, height: 22)
                            .background(palette.closeButtonBackground, in: Circle())
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardMaterial, in: cardShape)
            .overlay {
                cardShape
                    .fill(notification.tone.accent.opacity(cardTintOpacity))
                    .allowsHitTesting(false)
            }
            .overlay {
                cardShape
                    .strokeBorder(palette.cardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: palette.shadow, radius: 22, y: 18)
        }
    }

    private struct WindowNotificationPreviewSurface<Controls: View>: View {
        @Environment(\.colorScheme) private var colorScheme

        let controls: Controls

        private var palette: WindowNotificationPreviewPalette {
            .make(for: colorScheme)
        }

        init(@ViewBuilder controls: () -> Controls) {
            self.controls = controls()
        }

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                palette.surfaceBackground

                VStack(alignment: .leading, spacing: 12) {
                    Text("Window Notification Kit")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.primaryText)

                    Text("A top-of-window stack that keeps variable-height cards legible when collapsed, then expands into a full list on hover.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)

                controls
                    .padding(28)
            }
        }
    }

    private struct WindowNotificationPreviewHarness: View {
        @Environment(\.colorScheme) private var colorScheme

        @State private var center = WindowNotificationCenter()
        @State private var behavior = WindowNotificationStackConfiguration.ExpansionBehavior.hover
        @State private var expandsOnHover = true
        @State private var maximumWidth = 420.0
        @State private var maximumCollapsedCards = 3
        @State private var preferredMaximumExpandedCards = 4
        @State private var seed = 0

        private var palette: WindowNotificationPreviewPalette {
            .make(for: colorScheme)
        }

        private var effectiveMaximumExpandedCards: Int {
            max(preferredMaximumExpandedCards, maximumCollapsedCards)
        }

        private var configuration: WindowNotificationStackConfiguration {
            var config = WindowNotificationStackConfiguration.sonner
            config.expansionBehavior = behavior
            config.expandsOnHover = expandsOnHover
            config.maximumWidth = maximumWidth
            config.maximumExpandedCards = effectiveMaximumExpandedCards
            config.maximumCollapsedCards = maximumCollapsedCards
            config.collapsedPeek = 16
            config.expandedSpacing = 14
            return config
        }

        var body: some View {
            WindowNotificationPreviewSurface {
                controls
            }
            .windowNotificationHost(center: center, configuration: configuration)
            .task {
                if center.isEmpty {
                    resetNotifications()
                }
            }
        }

        private var controls: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hover the stack to test expansion. This preview lets us tune width, the collapsed cap, and the expanded cap with the same semantics used by the runtime API.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: 460, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $behavior) {
                        Text("Hover").tag(WindowNotificationStackConfiguration.ExpansionBehavior.hover)
                        Text("Collapsed").tag(WindowNotificationStackConfiguration.ExpansionBehavior.collapsed)
                        Text("Expanded").tag(WindowNotificationStackConfiguration.ExpansionBehavior.expanded)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)

                    Toggle("Expand on Hover", isOn: $expandsOnHover)
                        .toggleStyle(.switch)
                        .frame(width: 220, alignment: .leading)

                    Stepper("Maximum Width: \(Int(maximumWidth))", value: $maximumWidth, in: 280 ... 560, step: 20)
                    Stepper("Maximum Cards: \(maximumCollapsedCards)", value: $maximumCollapsedCards, in: 1 ... 8)
                    Stepper(expandedCardsLabel, value: $preferredMaximumExpandedCards, in: 1 ... 8)
                }
                .padding(16)
                .frame(width: 360, alignment: .leading)
                .background(palette.panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.panelBorder, lineWidth: 1)
                }

                HStack(spacing: 10) {
                    Button("Push") {
                        pushNotification()
                    }

                    Button("Pop Front") {
                        guard let firstID = center.items.first?.id else { return }
                        center.dismiss(firstID)
                    }

                    Button("Reset") {
                        resetNotifications()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }

        private var expandedCardsLabel: String {
            adjustedLabel(
                title: "Expanded Cards",
                effectiveValue: effectiveMaximumExpandedCards,
                preferredValue: preferredMaximumExpandedCards
            )
        }

        private func adjustedLabel(title: String, effectiveValue: Int, preferredValue: Int) -> String {
            guard effectiveValue != preferredValue else {
                return "\(title): \(effectiveValue)"
            }

            return "\(title): \(effectiveValue) (adjusted)"
        }

        private func pushNotification() {
            seed += 1

            let tone = PreviewNotification.Tone.allCases[seed % PreviewNotification.Tone.allCases.count]
            let notification = PreviewNotification(
                tone: tone,
                title: seed.isMultiple(of: 2) ? "Shortcut Synced" : "Task Finished",
                message: seed.isMultiple(of: 2)
                    ? "Your latest workspace shortcut preset is now active across the floating panel."
                    : "The queue drained successfully and the newest card animated into place. The fixed-width stack keeps coverage stable while card height remains content-driven.",
                meta: "now"
            )

            center.present { context in
                PreviewNotificationCard(notification: notification, context: context)
            }
        }

        private func resetNotifications() {
            center.dismissAll()

            for notification in PreviewNotification.sample.reversed() {
                center.present { context in
                    PreviewNotificationCard(notification: notification, context: context)
                }
            }
        }
    }

    private struct WindowNotificationAPITriggerDemo: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.windowNotificationCenter) private var notifications
        @State private var seed = 0

        private var palette: WindowNotificationPreviewPalette {
            .make(for: colorScheme)
        }

        var body: some View {
            WindowNotificationPreviewSurface {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Any descendant can read an optional notification center from the environment and render a fully custom card.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: 420, alignment: .leading)

                    HStack(spacing: 10) {
                        Button("Present Custom UI") {
                            pushCustomNotification()
                        }

                        Button("Clear") {
                            notifications?.dismissAll()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .windowNotifications()
        }

        private func pushCustomNotification() {
            seed += 1

            let notification = PreviewNotification(
                tone: PreviewNotification.Tone.allCases[seed % PreviewNotification.Tone.allCases.count],
                title: "Environment Triggered",
                message: "This card is rendered by the caller, not by the kit. The only shared contract is the notification center and card context.",
                meta: "now"
            )

            notifications?.present(duration: .seconds(5)) { context in
                PreviewNotificationCard(notification: notification, context: context)
            }
        }
    }

    #Preview("Collapsed Stack") {
        WindowNotificationPreviewSurface {
            EmptyView()
        }
        .windowNotificationOverlay(
            items: PreviewNotification.sample,
            configuration: {
                var config = WindowNotificationStackConfiguration.sonner
                config.maximumWidth = 420
                config.expansionBehavior = .collapsed
                config.maximumCollapsedCards = 4
                config.collapsedPeek = 16
                return config
            }()
        ) { item, context in
            PreviewNotificationCard(notification: item, context: context)
        }
        .frame(width: 780, height: 420)
    }

    #Preview("Expanded List") {
        WindowNotificationPreviewSurface {
            EmptyView()
        }
        .windowNotificationOverlay(
            items: PreviewNotification.sample,
            configuration: {
                var config = WindowNotificationStackConfiguration.sonner
                config.maximumWidth = 420
                config.expansionBehavior = .expanded
                config.expandedSpacing = 14
                return config
            }()
        ) { item, context in
            PreviewNotificationCard(notification: item, context: context)
        }
        .frame(width: 780, height: 520)
    }

    #Preview("Interactive Playground") {
        WindowNotificationPreviewHarness()
            .frame(width: 860, height: 580)
    }

    #Preview("API Trigger Demo") {
        WindowNotificationAPITriggerDemo()
            .frame(width: 860, height: 420)
    }
#endif
