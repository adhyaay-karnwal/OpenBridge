import AppKit
import SwiftUI

private enum ConversationHistoryPopupMetrics {
    static let sectionSpacing: CGFloat = 8
    static let fieldHeight: CGFloat = 34
    static let fieldCornerRadius: CGFloat = 10
    static let searchRowHeight: CGFloat = 46
    static let searchRowSpacing: CGFloat = 4
    static let searchListVerticalPadding: CGFloat = 4
    static let searchRowHorizontalPadding: CGFloat = 10
    static let searchRowVerticalPadding: CGFloat = 7
    static let inlineErrorHeight: CGFloat = 42
    static let loadingHeight: CGFloat = 108
    static let emptyStateHeight: CGFloat = 116
    static let errorStateHeight: CGFloat = 122

    static func topPadding(for style: ConversationListPresentationStyle) -> CGFloat {
        horizontalPadding(for: style) + 4
    }

    static func horizontalPadding(for style: ConversationListPresentationStyle) -> CGFloat {
        style.rowOuterHorizontalPadding + 6
    }

    static func searchHeaderHeight(for style: ConversationListPresentationStyle) -> CGFloat {
        topPadding(for: style) + fieldHeight + sectionSpacing
    }
}

@MainActor
struct ConversationHistoryPopupContent: View {
    let searchModel: ChatConversationSearchModel
    let controller: ConversationListViewController
    let currentConversationId: String?
    let streamingConversationIds: Set<String>
    let sections: [ConversationListSection]?
    let liquidLayout: ConversationListLiquidVirtualization.Layout?
    let scrollState: ConversationListScrollState
    let style: ConversationListPresentationStyle
    let searchFocusToken: Int
    let onSelect: (SessionListInfo) -> Void
    let onRename: ((SessionListInfo) -> Void)?
    let onDelete: ((SessionListInfo) -> Void)?
    let onShareLink: ((SessionListInfo) -> Void)?
    let onDismiss: () -> Void
    let onKeyDownHandlerChange: (((NSEvent) -> Bool)?) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var keyboardFocusedSessionID: String?
    @State private var keyboardFocusedResultID: String?

    private var isSearching: Bool {
        !searchModel.trimmedQuery.isEmpty
    }

    private var bodyMaxHeight: CGFloat {
        max(0, style.maxHeight - ConversationHistoryPopupMetrics.searchHeaderHeight(for: style))
    }

    private var historyContent: some View {
        ConversationListMenuContent(
            controller: controller,
            currentConversationId: currentConversationId,
            streamingConversationIds: streamingConversationIds,
            sections: sections,
            liquidLayout: liquidLayout,
            onSelect: onSelect,
            onRename: onRename,
            onDelete: onDelete,
            onShareLink: onShareLink,
            scrollState: scrollState,
            style: style,
            keyboardFocusedSessionID: keyboardFocusedSessionID,
            maxHeight: bodyMaxHeight
        )
    }

    private var searchContent: some View {
        ConversationHistorySearchResultsView(
            model: searchModel,
            style: style,
            keyboardFocusedResultID: keyboardFocusedResultID,
            maxHeight: bodyMaxHeight,
            onOpenResult: { result in
                searchModel.open(result, onSuccess: onDismiss)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationHistoryPopupMetrics.sectionSpacing) {
            ConversationHistorySearchField(
                text: Binding(
                    get: { searchModel.query },
                    set: { searchModel.updateQuery($0) }
                ),
                style: style,
                isFocused: $isSearchFocused,
                onSubmit: searchModel.performSearchNow
            )
            .padding(.horizontal, ConversationHistoryPopupMetrics.horizontalPadding(for: style))

            Group {
                if isSearching {
                    searchContent
                } else {
                    historyContent
                }
            }
            .transition(.conversationHistoryMenuContent)
        }
        .padding(.top, ConversationHistoryPopupMetrics.topPadding(for: style))
        .frame(width: style.menuWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(duration: 0.3, bounce: 0.16), value: isSearching)
        .animation(.spring(duration: 0.28, bounce: 0.14), value: searchModel.status)
        .animation(.spring(duration: 0.28, bounce: 0.14), value: searchModel.results.count)
        .onAppear {
            syncKeyboardSelection()
            updateKeyDownHandler()
        }
        .onDisappear {
            onKeyDownHandlerChange(nil)
        }
        .onChange(of: historySessionIDs) { _, _ in
            syncKeyboardSelection()
            updateKeyDownHandler()
        }
        .onChange(of: searchResultIDs) { _, _ in
            syncKeyboardSelection()
            updateKeyDownHandler()
        }
        .onChange(of: isSearchFocused) { _, _ in
            updateKeyDownHandler()
        }
        .onChange(of: searchModel.trimmedQuery) { _, _ in
            syncKeyboardSelection()
            updateKeyDownHandler()
        }
        .task(id: searchFocusToken) {
            guard searchFocusToken > 0 else { return }
            isSearchFocused = false
            isSearchFocused = true
        }
    }

    private var historySessionIDs: [String] {
        historySessions.map(\.id)
    }

    private var searchResultIDs: [String] {
        searchModel.results.map(\.id)
    }

    private var historySessions: [SessionListInfo] {
        let availableSections = sections ?? ConversationListSectionBuilder.buildSections(from: controller.sessions)
        return availableSections.flatMap(\.items)
    }

    private var canHandleHistoryKeys: Bool {
        style == .menu && searchModel.trimmedQuery.isEmpty && !isSearchFocused
    }

    private func updateKeyDownHandler() {
        onKeyDownHandlerChange { event in
            handlePopupKeyDown(event)
        }
    }

    private func syncKeyboardSelection() {
        if searchModel.trimmedQuery.isEmpty {
            syncHistoryKeyboardSelection()
            keyboardFocusedResultID = nil
        } else {
            keyboardFocusedSessionID = nil
            syncSearchKeyboardSelection()
        }
    }

    private func syncHistoryKeyboardSelection() {
        guard style == .menu else {
            keyboardFocusedSessionID = nil
            return
        }

        if let keyboardFocusedSessionID,
           historySessions.contains(where: { $0.id == keyboardFocusedSessionID })
        {
            return
        }

        if let currentConversationId,
           historySessions.contains(where: { $0.id == currentConversationId })
        {
            keyboardFocusedSessionID = currentConversationId
            return
        }

        keyboardFocusedSessionID = historySessions.first?.id
    }

    private func syncSearchKeyboardSelection() {
        if let keyboardFocusedResultID,
           searchModel.results.contains(where: { $0.id == keyboardFocusedResultID })
        {
            return
        }

        keyboardFocusedResultID = searchModel.results.first?.id
    }

    private func handlePopupKeyDown(_ event: NSEvent) -> Bool {
        if !searchModel.trimmedQuery.isEmpty {
            return handleSearchKeyDown(event)
        }

        return handleHistoryKeyDown(event)
    }

    private func handleHistoryKeyDown(_ event: NSEvent) -> Bool {
        guard canHandleHistoryKeys else { return false }

        switch event.keyCode {
        case 125:
            moveKeyboardSelection(step: 1)
            return true
        case 126:
            moveKeyboardSelection(step: -1)
            return true
        case 36, 76:
            guard let selectedSession = selectedHistorySession else { return false }
            onSelect(selectedSession)
            return true
        default:
            return false
        }
    }

    private var selectedHistorySession: SessionListInfo? {
        guard let keyboardFocusedSessionID else { return nil }
        return historySessions.first(where: { $0.id == keyboardFocusedSessionID })
    }

    private func moveKeyboardSelection(step: Int) {
        guard !historySessions.isEmpty else {
            keyboardFocusedSessionID = nil
            return
        }

        guard let currentIndex = historySessions.firstIndex(where: { $0.id == keyboardFocusedSessionID }) else {
            let fallbackIndex = step >= 0 ? 0 : historySessions.count - 1
            keyboardFocusedSessionID = historySessions[fallbackIndex].id
            return
        }

        let nextIndex = min(max(currentIndex + step, 0), historySessions.count - 1)
        keyboardFocusedSessionID = historySessions[nextIndex].id
    }

    private func handleSearchKeyDown(_ event: NSEvent) -> Bool {
        guard !searchModel.trimmedQuery.isEmpty else { return false }

        switch event.keyCode {
        case 125:
            moveSearchResultSelection(step: 1)
            return true
        case 126:
            moveSearchResultSelection(step: -1)
            return true
        case 36, 76:
            guard let selectedSearchResult else { return false }
            searchModel.open(selectedSearchResult, onSuccess: onDismiss)
            return true
        default:
            return false
        }
    }

    private var selectedSearchResult: ConversationSearchResult? {
        guard let keyboardFocusedResultID else { return nil }
        return searchModel.results.first(where: { $0.id == keyboardFocusedResultID })
    }

    private func moveSearchResultSelection(step: Int) {
        guard !searchModel.results.isEmpty else {
            keyboardFocusedResultID = nil
            return
        }

        guard let currentIndex = searchModel.results.firstIndex(where: { $0.id == keyboardFocusedResultID }) else {
            let fallbackIndex = step >= 0 ? 0 : searchModel.results.count - 1
            keyboardFocusedResultID = searchModel.results[fallbackIndex].id
            return
        }

        let nextIndex = min(max(currentIndex + step, 0), searchModel.results.count - 1)
        keyboardFocusedResultID = searchModel.results[nextIndex].id
    }
}

private struct ConversationHistorySearchField: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    let style: ConversationListPresentationStyle
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(String(localized: "Search conversations"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .focusEffectDisabled()
                .onSubmit {
                    onSubmit()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ConversationHistoryPopupMetrics.fieldHeight)
        .background(
            RoundedRectangle(
                cornerRadius: ConversationHistoryPopupMetrics.fieldCornerRadius,
                style: .continuous
            )
            .fill(fieldBackgroundColor)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ConversationHistoryPopupMetrics.fieldCornerRadius,
                style: .continuous
            )
            .strokeBorder(fieldBorderColor, lineWidth: 0.5)
        )
        .accessibilityIdentifier("chat.history.searchField")
    }

    private var fieldBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(isFocused ? 0.1 : 0.06)
        default:
            Color.black.opacity(isFocused ? 0.055 : 0.035)
        }
    }

    private var fieldBorderColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(style == .liquidPopup ? 0.1 : 0.08)
        default:
            Color.black.opacity(style == .liquidPopup ? 0.1 : 0.08)
        }
    }
}

private struct ConversationHistorySearchResultsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: ChatConversationSearchModel
    let style: ConversationListPresentationStyle
    let keyboardFocusedResultID: String?
    let maxHeight: CGFloat
    let onOpenResult: (ConversationSearchResult) -> Void

    @State private var hoveredResultID: String?

    private var visibleHeight: CGFloat {
        min(contentHeight, maxHeight)
    }

    private var contentHeight: CGFloat {
        let inlineErrorHeight = model.openErrorMessage == nil ? 0 : ConversationHistoryPopupMetrics.inlineErrorHeight

        switch model.status {
        case .idle:
            return 0
        case .loading:
            return ConversationHistoryPopupMetrics.loadingHeight
        case .error:
            return ConversationHistoryPopupMetrics.errorStateHeight
        case .ready where model.results.isEmpty:
            return ConversationHistoryPopupMetrics.emptyStateHeight
        case .ready:
            return CGFloat(model.results.count) * ConversationHistoryPopupMetrics.searchRowHeight +
                CGFloat(max(0, model.results.count - 1)) * ConversationHistoryPopupMetrics.searchRowSpacing +
                ConversationHistoryPopupMetrics.searchListVerticalPadding * 2 +
                inlineErrorHeight
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ConversationHistoryPopupMetrics.searchRowSpacing) {
                if let openErrorMessage = model.openErrorMessage {
                    Text(openErrorMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.red.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }

                switch model.status {
                case .loading:
                    stateView(
                        title: String(localized: "Searching..."),
                        subtitle: nil,
                        showSpinner: true
                    )
                case .error:
                    stateView(
                        title: model.searchErrorMessage ?? String(localized: "Search failed. Please try again."),
                        subtitle: nil,
                        retryAction: model.retry
                    )
                case .ready where model.results.isEmpty:
                    stateView(
                        title: String(localized: "No matches found"),
                        subtitle: String(localized: "Try a shorter phrase or a different keyword.")
                    )
                case .ready:
                    ForEach(model.results) { result in
                        resultRow(result)
                    }
                case .idle:
                    EmptyView()
                }
            }
            .padding(.horizontal, ConversationHistoryPopupMetrics.horizontalPadding(for: style))
            .padding(.vertical, ConversationHistoryPopupMetrics.searchListVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .clipped()
        .frame(height: visibleHeight, alignment: .top)
        .animation(.spring(duration: 0.28, bounce: 0.14), value: visibleHeight)
    }

    private func resultRow(_ result: ConversationSearchResult) -> some View {
        let isSelected = model.selectedResultID == result.id
        let highlightedResultID = hoveredResultID ?? keyboardFocusedResultID
        let isHighlighted = highlightedResultID == result.id

        return Button {
            onOpenResult(result)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ChatConversationSearchResultFormatter.displayTitle(for: result))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ChatConversationSearchResultFormatter.formattedTimestamp(result.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ChatConversationSearchResultFormatter.highlightedSnippet(
                    ChatConversationSearchResultFormatter.displaySnippet(for: result)
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, ConversationHistoryPopupMetrics.searchRowHorizontalPadding)
            .padding(.vertical, ConversationHistoryPopupMetrics.searchRowVerticalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: ConversationHistoryPopupMetrics.searchRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(
                    cornerRadius: style == .liquidPopup ? 14 : 12,
                    style: .continuous
                )
                .fill(rowFillColor(isHovered: isHighlighted, isSelected: isSelected))
            )
            .opacity(isSelected ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
        .onHover { isHovering in
            guard !isSelected else {
                if hoveredResultID == result.id {
                    hoveredResultID = nil
                }
                return
            }

            if isHovering {
                hoveredResultID = result.id
            } else if hoveredResultID == result.id {
                hoveredResultID = nil
            }
        }
        .accessibilityLabel(ChatConversationSearchResultFormatter.searchResultAccessibilityLabel(for: result))
    }

    private func stateView(
        title: String,
        subtitle: String?,
        showSpinner: Bool = false,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            if showSpinner {
                AnimatedLogo(config: loadingLogoConfig)
                    .frame(width: 27, height: 24)
            }

            if showSpinner {
                ThinkingHighlightText(
                    text: title,
                    font: .system(size: 12.5, weight: .regular),
                    baseColor: loadingTextBaseColor,
                    highlightColor: loadingTextHighlightColor,
                    alignment: .center
                )
                .multilineTextAlignment(.center)
            } else {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction {
                Button(String(localized: "Try again")) {
                    retryAction()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(retryBackgroundColor, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: visibleHeight, alignment: .center)
    }

    private func rowFillColor(isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            switch colorScheme {
            case .dark:
                return Color.white.opacity(isHovered ? 0.12 : 0.09)
            default:
                return Color.black.opacity(isHovered ? 0.09 : 0.065)
            }
        }

        return ConversationListRowOverlayStyle.fillColor(
            isHovered: isHovered,
            presentationStyle: style,
            colorScheme: colorScheme
        )
    }

    private var retryBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.06)
        }
    }

    private var loadingTextBaseColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.42)
        default:
            Color.black.opacity(0.38)
        }
    }

    private var loadingTextHighlightColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.92)
        default:
            Color.black.opacity(0.82)
        }
    }

    private var loadingLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .secondary
        config.strokeWidth = 1.8
        config.enterDrawDuration = 1.1
        return config
    }
}

@available(macOS 26.0, *)
struct HeaderMoreMenuContent: View {
    let onOpenSettings: () -> Void
    let onOpenSkillSettings: () -> Void
    let onExploreMoreSkills: () -> Void

    private let style = ConversationListPresentationStyle.liquidPopup

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            HeaderMoreMenuRow(
                title: String(localized: "Settings"),
                iconName: "gear",
                shortcut: "⌘,",
                style: style,
                action: onOpenSettings
            )
            HeaderMoreMenuRow(
                title: String(localized: "Open Skill Settings"),
                style: style,
                accessibilityIdentifier: AccessibilityID.Chat.moreMenuOpenSkillSettings,
                action: onOpenSkillSettings
            )
            HeaderMoreMenuRow(
                title: String(localized: "Explore More Skills"),
                style: style,
                action: onExploreMoreSkills
            )
        }
        .padding(.horizontal, style.rowOuterHorizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(width: style.headerMoreMenuWidth)
    }
}

@available(macOS 26.0, *)
private struct HeaderMoreMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var iconName: String?
    var shortcut: String?
    let style: ConversationListPresentationStyle
    let accessibilityIdentifier: String?
    let action: () -> Void

    @State private var isHovered = false

    init(
        title: String,
        iconName: String? = nil,
        shortcut: String? = nil,
        style: ConversationListPresentationStyle,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.shortcut = shortcut
        self.style = style
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leadingSymbol

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if let shortcut {
                    Text(verbatim: shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, style.rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowHoverBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .onHover { isHovered = $0 }
    }

    private var rowVerticalPadding: CGFloat {
        switch style {
        case .menu:
            style.rowVerticalPadding
        case .liquidPopup:
            9
        }
    }

    private var leadingSymbol: some View {
        Group {
            if let iconName {
                Image(systemName: iconName)
            } else {
                Color.clear
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: style.headerMoreMenuLeadingSymbolColumnWidth, alignment: .leading)
    }

    private var rowHoverBackground: some View {
        RoundedRectangle(cornerRadius: style.rowCornerRadius, style: .continuous)
            .fill(
                ConversationListRowOverlayStyle.fillColor(
                    isHovered: isHovered,
                    presentationStyle: style,
                    colorScheme: colorScheme
                )
            )
    }
}

struct MenuAnchorView: NSViewRepresentable {
    let onUpdate: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onUpdate(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            onUpdate(nsView)
        }
    }
}

@MainActor
final class ConversationHistoryPopupMonitor {
    weak var popupView: NSView?
    var onKeyDown: ((NSEvent) -> Bool)?

    private var localMonitor: Any?

    func start(isPresented: Binding<Bool>, animation: Animation) {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            return handle(event, isPresented: isPresented, animation: animation)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onKeyDown = nil
    }

    private func handle(
        _ event: NSEvent,
        isPresented: Binding<Bool>,
        animation: Animation
    ) -> NSEvent? {
        if event.type == .keyDown {
            if event.keyCode == 53 {
                withAnimation(animation) {
                    isPresented.wrappedValue = false
                }
                return nil
            }
            if onKeyDown?(event) == true {
                return nil
            }
            return event
        }

        if let view = popupView, view.window === event.window {
            let location = view.convert(event.locationInWindow, from: nil)
            if view.bounds.contains(location) {
                return event
            }
        }

        withAnimation(animation) {
            isPresented.wrappedValue = false
        }
        return event
    }
}

private struct ConversationHistoryMenuContentTransitionModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .topTrailing)
    }
}

extension AnyTransition {
    static var conversationHistoryMenuContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ConversationHistoryMenuContentTransitionModifier(opacity: 0, blur: 18, scale: 0.96),
                identity: ConversationHistoryMenuContentTransitionModifier(opacity: 1, blur: 0, scale: 1)
            ),
            removal: .modifier(
                active: ConversationHistoryMenuContentTransitionModifier(opacity: 0, blur: 14, scale: 0.98),
                identity: ConversationHistoryMenuContentTransitionModifier(opacity: 1, blur: 0, scale: 1)
            )
        )
    }
}
