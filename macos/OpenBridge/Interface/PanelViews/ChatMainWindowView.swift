import AppKit
import SwiftUI

struct ChatMainWindowView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var surfaceModel: ChatSurfaceModel
    @State private var messagesBridge: MessagesBridge
    @State private var sidebarSearchModel: ChatConversationSearchModel
    @State private var voiceShortcutMonitor: LocalEventMonitor?
    @State private var listController: ConversationListViewController
    @State private var hostID: UUID

    init() {
        let surfaceModel = ChatSurfaceModel.shared
        let messagesBridge = MessagesBridge(chatEditorViewModel: surfaceModel.editorViewModel)

        _surfaceModel = State(initialValue: surfaceModel)
        _messagesBridge = State(initialValue: messagesBridge)
        _sidebarSearchModel = State(
            initialValue: ChatConversationSearchModel(
                messagesBridge: messagesBridge,
                requiresPresentation: false,
                dismissesAfterOpen: false
            )
        )
        _listController = State(initialValue: ConversationListViewController.shared)
        _hostID = State(initialValue: UUID())
    }

    private var currentConversationID: String? {
        surfaceModel.editorViewModel.chat?.conversationId
    }

    private var conversationSections: [ConversationListSection] {
        ConversationListSectionBuilder.buildSections(from: listController.sessions)
    }

    private var isSidebarSearchActive: Bool {
        sidebarSearchModel.showsResultsPanel
    }

    private var detailTitle: String {
        ChatMainWindowViewHelpers.detailTitle(
            from: surfaceModel.editorViewModel.conversationTitle
        )
    }

    private var toolbarTitle: String {
        ChatMainWindowViewHelpers.toolbarTitle(from: detailTitle)
    }

    private var currentConversationSession: SessionListInfo? {
        ChatMainWindowViewHelpers.currentConversationSession(
            conversationId: currentConversationID,
            sessions: listController.sessions,
            conversationTitle: surfaceModel.editorViewModel.conversationTitle
        )
    }

    private var mainWindowBackgroundColor: Color {
        ChatMainWindowViewHelpers.backgroundColor(for: colorScheme)
    }

    var body: some View {
        mainContent
            .frame(minWidth: 900, minHeight: 640)
            .accessibilityIdentifier(AccessibilityID.Chat.window)
            .onAppear {
                surfaceModel.hostDidAppear(id: hostID)
            }
            .onDisappear {
                surfaceModel.hostDidDisappear(id: hostID)
                stopVoiceShortcutMonitor()
            }
    }

    private var mainContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(mainWindowBackgroundColor)
        .onAppear {
            startVoiceShortcutMonitor()
        }
        .onDisappear {
            stopVoiceShortcutMonitor()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            sidebarBody
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        .accessibilityIdentifier(AccessibilityID.Chat.sidebar)
    }

    private var sidebarHeader: some View {
        VStack(spacing: 2) {
            ChatSidebarActionRowButton(
                title: String(localized: "New Chat"),
                systemImage: "square.and.pencil",
                trailingHint: "⌘N",
                isLoading: surfaceModel.editorViewModel.isCreatingNewChat,
                showsTrailingHintOnHover: true,
                action: {
                    surfaceModel.openNewChat()
                }
            )
            .help("New Chat (⌘N)")

            ChatMainWindowSidebarSearchField(model: sidebarSearchModel)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var sidebarBody: some View {
        ZStack {
            sidebarHistoryLayer
                .opacity(isSidebarSearchActive ? 0 : 1)
                .allowsHitTesting(!isSidebarSearchActive)
                .accessibilityHidden(isSidebarSearchActive)

            if isSidebarSearchActive {
                ChatMainWindowSidebarSearchResultsView(model: sidebarSearchModel)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSidebarSearchActive)
    }

    @ViewBuilder
    private var sidebarHistoryLayer: some View {
        switch listController.state {
        case .idle where listController.sessions.isEmpty, .loading where listController.sessions.isEmpty:
            ChatSidebarLoadingView(title: String(localized: "Loading conversations…"))
        case .failed where listController.sessions.isEmpty:
            ChatSidebarErrorView(
                message: listController.errorMessage ?? String(localized: "Failed to load conversations")
            ) {
                listController.refresh(force: true, silent: false)
            }
        default:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(conversationSections) { section in
                        Text(sectionDisplayTitle(section.title))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .opacity(0.7)
                            .padding(.leading, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(section.items) { session in
                            ChatSidebarConversationRow(
                                session: session,
                                isStreaming: ChatViewModel.shared.streamingConversationIds.contains(session.id),
                                isSelected: session.id == currentConversationID,
                                onSelect: {
                                    guard currentConversationID != session.id else { return }
                                    surfaceModel.editorViewModel.openConversation(session.id)
                                }
                            )
                            .contextMenu {
                                Button(String(localized: "Rename")) {
                                    ConversationListActionController.shared.renameConversation(session)
                                }
                                Divider()
                                Button(String(localized: "Delete"), role: .destructive) {
                                    ConversationListActionController.shared.deleteConversation(
                                        session,
                                        currentConversationId: surfaceModel.editorViewModel.chat?.conversationId,
                                        onDeletedCurrentConversation: {
                                            surfaceModel.openNewChat()
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }

                    if listController.hasMore || listController.isLoadingMore {
                        ChatSidebarLoadMoreRow(isLoading: listController.isLoadingMore)
                            .padding(.top, 8)
                            .onAppear {
                                listController.loadMoreIfNeeded()
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .modifier(ChatSidebarScrollEdgeEffectModifier(isEnabled: settingsManager.shouldUseMacOS26UI))
        }
    }

    private var detail: some View {
        NavigationStack {
            ChatMainWindowDetailContent(
                surfaceModel: surfaceModel,
                messagesBridge: messagesBridge,
                onFileDrop: { pasteboard in
                    surfaceModel.editorViewModel.handleFileDrop(pasteboard)
                },
                shouldUseMacOS26UI: settingsManager.shouldUseMacOS26UI,
                backgroundColor: mainWindowBackgroundColor,
                currentConversationSession: currentConversationSession,
                onNewChat: {
                    surfaceModel.openNewChat()
                },
                onSwitchToPanel: {
                    Windows.shared.switchChatPresentationMode(to: .panel)
                },
                onOpenSettings: {
                    SettingsNavigation.shared.navigate(to: .general)
                    Windows.shared.open(.settings)
                },
                onRenameConversation: {
                    guard surfaceModel.editorViewModel.chat?.conversationId != nil else { return }
                    ConversationListActionController.shared.promptForConversationRename(
                        initialTitle: surfaceModel.editorViewModel.conversationTitle,
                        window: NSApp.keyWindow
                    ) { newTitle, window in
                        surfaceModel.editorViewModel.renameCurrentConversation(
                            title: newTitle,
                            window: window
                        )
                    }
                }
            )
        }
        .navigationTitle(toolbarTitle)
        .background(mainWindowBackgroundColor)
    }

    private func sectionDisplayTitle(_ title: String) -> String {
        ChatMainWindowViewHelpers.sectionDisplayTitle(title)
    }

    private func startVoiceShortcutMonitor() {
        VoiceInputShortcutHelper.ensureShortcutRegistered()
        let editorViewModel = surfaceModel.editorViewModel
        voiceShortcutMonitor = LocalEventMonitor(event: .keyDown) { event in
            VoiceInputShortcutHelper.handleEvent(
                event,
                in: .main,
                editorViewModel: editorViewModel
            )
        }
        voiceShortcutMonitor?.start()
    }

    private func stopVoiceShortcutMonitor() {
        voiceShortcutMonitor?.stop()
        voiceShortcutMonitor = nil
    }
}

private struct ChatMainWindowScrollEdgeEffectModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled, #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.automatic, for: .top)
        } else {
            content
        }
    }
}

private struct ChatMainWindowDetailContent: View {
    let surfaceModel: ChatSurfaceModel
    let messagesBridge: MessagesBridge
    let onFileDrop: (NSPasteboard) -> Bool
    let shouldUseMacOS26UI: Bool
    let backgroundColor: Color
    let currentConversationSession: SessionListInfo?
    let onNewChat: () -> Void
    let onSwitchToPanel: () -> Void
    let onOpenSettings: () -> Void
    let onRenameConversation: () -> Void
    private let headerActionInset = ChatMainWindowHeaderMetrics.actionInset

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                chatSurface(messagePaddingTop: proxy.safeAreaInsets.top)
                    .modifier(ChatMainWindowScrollEdgeEffectModifier(isEnabled: shouldUseMacOS26UI))
                    .background(backgroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ChatMainWindowTopBackdrop(
                    height: proxy.safeAreaInsets.top,
                    showsMask: shouldUseMacOS26UI
                )

                ChatMainWindowHeaderActionGroup(
                    hasConversationSession: currentConversationSession != nil,
                    onNewChat: onNewChat,
                    onSwitchToPanel: onSwitchToPanel,
                    onOpenSettings: onOpenSettings,
                    onRenameConversation: onRenameConversation
                )
                .padding(.trailing, headerActionInset)
                .offset(y: -proxy.safeAreaInsets.top + headerActionInset)
                .zIndex(3)
            }
        }
    }

    private func chatSurface(messagePaddingTop: CGFloat) -> some View {
        ChatConversationSurfaceView(
            surfaceModel: surfaceModel,
            messagesBridge: messagesBridge,
            chatPresentationMode: .window,
            messagePaddingTop: messagePaddingTop,
            onFileDrop: onFileDrop,
            showsFileDropOverlay: true
        )
        .ignoresSafeArea(.container, edges: .top)
    }
}

@MainActor
private struct ChatMainWindowHeaderActionGroup: View {
    @State private var popupMonitor = ChatMainWindowHeaderPopupMonitor()
    @State private var isNewChatHovered = false
    @State private var isMoreHovered = false
    @State private var isSwitchHovered = false
    @State private var isMoreMenuPresented = false

    let hasConversationSession: Bool
    let onNewChat: () -> Void
    let onSwitchToPanel: () -> Void
    let onOpenSettings: () -> Void
    let onRenameConversation: () -> Void

    private let morphAnimation = Animation.spring(duration: 0.32, bounce: 0.22)
    private let iconSize: CGFloat = 20
    private let buttonWidth: CGFloat = 36
    private let buttonHeight = ChatMainWindowHeaderMetrics.buttonHeight
    private let controlSpacing: CGFloat = 8
    private let hoverCircleDiameter: CGFloat = 30
    private let capsulePadding: CGFloat = 0
    private let menuCornerRadius: CGFloat = 18
    private let style = ConversationListPresentationStyle.liquidPopup
    private let glassMaterial = SafeGlassMaterial.regular
    private let iconWeight: Font.Weight = .medium

    private var capsuleWidth: CGFloat {
        buttonWidth * 2 + capsulePadding * 2
    }

    private var capsuleHeight: CGFloat {
        buttonHeight + capsulePadding * 2
    }

    private var capsuleCornerRadius: CGFloat {
        capsuleHeight / 2
    }

    private var currentShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isMoreMenuPresented ? menuCornerRadius : capsuleCornerRadius,
            style: .continuous
        )
    }

    private var popupPresentedBinding: Binding<Bool> {
        Binding(
            get: { isMoreMenuPresented },
            set: { isPresented in
                if !isPresented {
                    isMoreMenuPresented = false
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: controlSpacing) {
            standaloneNewChatButton
                .opacity(isMoreMenuPresented ? 0 : 1)
                .allowsHitTesting(!isMoreMenuPresented)

            capsuleContainer
        }
        .fixedSize()
        .onChange(of: isMoreMenuPresented) { _, isPresented in
            if isPresented {
                popupMonitor.start(isPresented: popupPresentedBinding, animation: morphAnimation)
            } else {
                popupMonitor.stop()
            }
        }
        .onDisappear {
            popupMonitor.stop()
        }
    }

    private var standaloneNewChatButton: some View {
        Button(action: onNewChat) {
            Image(systemName: "square.and.pencil")
                .fontWeight(iconWeight)
                .frame(width: iconSize, height: iconSize)
                .frame(width: buttonHeight, height: buttonHeight)
                .background { hoverBackground(isHovered: isNewChatHovered) }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("New Chat (⌘N)")
        .accessibilityIdentifier(AccessibilityID.Chat.newChatButton)
        .onHover { isNewChatHovered = $0 }
        .safeGlassEffect(glassMaterial, in: Circle())
        .shadow(
            color: .black.opacity(0.08),
            radius: 8,
            y: 4
        )
    }

    private var capsuleContainer: some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                if isMoreMenuPresented {
                    ChatMainWindowMoreMenuContent(
                        style: style,
                        hasConversationSession: hasConversationSession,
                        onOpenSettings: {
                            dismissPopup()
                            onOpenSettings()
                        },
                        onRenameConversation: {
                            dismissPopup()
                            onRenameConversation()
                        }
                    )
                    .transition(.chatMainWindowHeaderMenuContent)
                }

                capsuleButtons
                    .opacity(isMoreMenuPresented ? 0 : 1)
                    .allowsHitTesting(!isMoreMenuPresented)
            }
            .padding(capsulePadding)
            .clipShape(currentShape)
            .safeGlassEffect(glassMaterial, in: currentShape)
        }
        .fixedSize()
        .shadow(
            color: .black.opacity(isMoreMenuPresented ? 0.18 : 0.08),
            radius: isMoreMenuPresented ? 22 : 8,
            y: isMoreMenuPresented ? 10 : 4
        )
        .background {
            ChatMainWindowAnchorView { popupMonitor.popupView = $0 }
        }
        .animation(morphAnimation, value: isMoreMenuPresented)
        .frame(width: capsuleWidth, height: capsuleHeight, alignment: .topTrailing)
        .zIndex(isMoreMenuPresented ? 10 : 0)
    }

    private var capsuleButtons: some View {
        HStack(spacing: 0) {
            Button(action: onSwitchToPanel) {
                Image(systemName: "macwindow.on.rectangle")
                    .fontWeight(iconWeight)
                    .frame(width: iconSize, height: iconSize)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background { hoverBackground(isHovered: isSwitchHovered) }
            }
            .buttonStyle(.plain)
            .help(String(localized: "Use Floating Window"))
            .accessibilityLabel(String(localized: "Use Floating Window"))
            .accessibilityIdentifier(AccessibilityID.Chat.switchPresentationButton)
            .onHover { isSwitchHovered = $0 }

            Button(action: openMoreMenu) {
                Image(systemName: "ellipsis")
                    .fontWeight(iconWeight)
                    .frame(width: iconSize, height: iconSize)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background { hoverBackground(isHovered: isMoreHovered) }
            }
            .buttonStyle(.plain)
            .help(String(localized: "More…"))
            .accessibilityLabel(String(localized: "More…"))
            .accessibilityIdentifier(AccessibilityID.Chat.moreButton)
            .onHover { isMoreHovered = $0 }
        }
    }

    @ViewBuilder
    private func hoverBackground(isHovered: Bool) -> some View {
        if isHovered {
            Circle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: hoverCircleDiameter, height: hoverCircleDiameter)
        }
    }

    private func openMoreMenu() {
        withAnimation(morphAnimation) {
            isMoreMenuPresented.toggle()
        }
    }

    private func dismissPopup() {
        withAnimation(morphAnimation) {
            isMoreMenuPresented = false
        }
    }
}

@MainActor
private struct ChatMainWindowMoreMenuContent: View {
    let style: ConversationListPresentationStyle
    let hasConversationSession: Bool
    let onOpenSettings: () -> Void
    let onRenameConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            ChatMainWindowMoreMenuRow(
                title: String(localized: "Settings"),
                iconName: "gear",
                shortcut: "⌘,",
                style: style,
                action: onOpenSettings
            )
            ChatMainWindowMoreMenuRow(
                title: String(localized: "Rename"),
                iconName: "pencil",
                shortcut: nil,
                style: style,
                isDisabled: !hasConversationSession,
                action: onRenameConversation
            )
        }
        .padding(.horizontal, style.rowOuterHorizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .frame(width: style.headerMoreMenuWidth)
    }
}

@MainActor
private struct ChatMainWindowMoreMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let iconName: String?
    let shortcut: String?
    let style: ConversationListPresentationStyle
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

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
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowHoverBackground)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
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
                    isHovered: isHovered && !isDisabled,
                    presentationStyle: style,
                    colorScheme: colorScheme
                )
            )
    }
}

struct ChatMainWindowDragArea: View {
    let height: CGFloat

    var body: some View {
        if height > 0 {
            ChatMainWindowDragAreaRepresentable()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }
}

private struct ChatMainWindowDragAreaRepresentable: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        ChatMainWindowDragNSView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class ChatMainWindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct ChatSidebarScrollEdgeEffectModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled, #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.automatic, for: .top)
        } else {
            content
        }
    }
}

private enum ChatSidebarRowOverlayStyle {
    static func fillColor(isHovered: Bool, isSelected: Bool, colorScheme: ColorScheme) -> Color {
        if isSelected {
            let opacity = switch colorScheme {
            case .dark: isHovered ? 0.15 : 0.11
            default: isHovered ? 0.10 : 0.07
            }
            let baseColor: Color = colorScheme == .dark ? .white : .black
            return baseColor.opacity(opacity)
        }

        return ConversationListRowOverlayStyle.fillColor(
            isHovered: isHovered,
            presentationStyle: .menu,
            colorScheme: colorScheme
        )
    }
}

private struct ChatSidebarRowButton<Leading: View, LabelContent: View, Trailing: View>: View {
    let isSelected: Bool
    let foregroundStyle: AnyShapeStyle
    let horizontalPadding: CGFloat
    let leadingWidth: CGFloat
    let leadingHeight: CGFloat
    let contentSpacing: CGFloat
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let labelContent: () -> LabelContent
    @ViewBuilder let trailing: () -> Trailing

    init(
        isSelected: Bool = false,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary),
        horizontalPadding: CGFloat = 12,
        leadingWidth: CGFloat = 16,
        leadingHeight: CGFloat = 16,
        contentSpacing: CGFloat = 10,
        action: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder labelContent: @escaping () -> LabelContent,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isSelected = isSelected
        self.foregroundStyle = foregroundStyle
        self.horizontalPadding = horizontalPadding
        self.leadingWidth = leadingWidth
        self.leadingHeight = leadingHeight
        self.contentSpacing = contentSpacing
        self.action = action
        self.leading = leading
        self.labelContent = labelContent
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            ChatSidebarRowContent(
                isSelected: isSelected,
                foregroundStyle: foregroundStyle,
                horizontalPadding: horizontalPadding,
                leadingWidth: leadingWidth,
                leadingHeight: leadingHeight,
                contentSpacing: contentSpacing,
                leading: leading,
                labelContent: labelContent,
                trailing: trailing
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ChatSidebarRowContent<Leading: View, LabelContent: View, Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSelected: Bool
    let foregroundStyle: AnyShapeStyle
    let horizontalPadding: CGFloat
    let leadingWidth: CGFloat
    let leadingHeight: CGFloat
    let contentSpacing: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let labelContent: () -> LabelContent
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovered = false

    init(
        isSelected: Bool = false,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary),
        horizontalPadding: CGFloat = 12,
        leadingWidth: CGFloat = 16,
        leadingHeight: CGFloat = 16,
        contentSpacing: CGFloat = 10,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder labelContent: @escaping () -> LabelContent,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isSelected = isSelected
        self.foregroundStyle = foregroundStyle
        self.horizontalPadding = horizontalPadding
        self.leadingWidth = leadingWidth
        self.leadingHeight = leadingHeight
        self.contentSpacing = contentSpacing
        self.leading = leading
        self.labelContent = labelContent
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: contentSpacing) {
            leading()
                .frame(width: leadingWidth, height: leadingHeight, alignment: .leading)
                .clipped()
                .foregroundStyle(.secondary)

            labelContent()
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .font(.body)
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.22, bounce: 0.08), value: leadingWidth)
        .animation(.spring(duration: 0.22, bounce: 0.08), value: contentSpacing)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                ChatSidebarRowOverlayStyle.fillColor(
                    isHovered: isHovered,
                    isSelected: isSelected,
                    colorScheme: colorScheme
                )
            )
    }
}

private struct ChatSidebarActionRowButton: View {
    let title: String
    let systemImage: String
    var trailingHint: String?
    var isLoading = false
    var showsTrailingHintOnHover = false
    var foregroundStyle: AnyShapeStyle = .init(.primary)
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        ChatSidebarRowButton(
            foregroundStyle: foregroundStyle,
            action: action
        ) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
            }
        } labelContent: {
            Text(title)
                .lineLimit(1)
        } trailing: {
            if let trailingHint, shouldShowTrailingHint {
                Text(verbatim: trailingHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLoading)
        .onHover { isHovered = $0 }
    }

    private var shouldShowTrailingHint: Bool {
        guard !isLoading else { return false }
        return !showsTrailingHintOnHover || isHovered
    }
}

private struct ChatSidebarConversationRow: View {
    let session: SessionListInfo
    let isStreaming: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    private var title: String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
    }

    private var timestampLabel: String {
        Self.compactRelativeTimestamp(for: session.updatedAt)
    }

    private var showsStatusIndicator: Bool {
        isStreaming
    }

    var body: some View {
        ChatSidebarRowButton(
            isSelected: isSelected,
            leadingWidth: showsStatusIndicator ? 16 : 0,
            leadingHeight: 16,
            contentSpacing: showsStatusIndicator ? 10 : 0,
            action: onSelect
        ) {
            ChatSidebarConversationStatusView(isVisible: showsStatusIndicator)
        } labelContent: {
            Text(title)
                .lineLimit(1)
        } trailing: {
            if !timestampLabel.isEmpty {
                Text(timestampLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private static func compactRelativeTimestamp(
        for rawTimestamp: Int64,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard rawTimestamp > 0 else { return "" }

        let date = Date(timeIntervalSince1970: TimeInterval(rawTimestamp))
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(date)))

        if elapsedSeconds < 60 {
            return "now"
        }

        let minutes = elapsedSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = max(
            1,
            calendar.dateComponents([.day], from: date, to: now).day ?? (hours / 24)
        )
        if days < 7 {
            return "\(days)d"
        }

        if days < 30 {
            return "\(max(1, days / 7))w"
        }

        let months = max(
            1,
            calendar.dateComponents([.month], from: date, to: now).month ?? (days / 30)
        )
        if months < 12 {
            return "\(months)mo"
        }

        let years = max(
            1,
            calendar.dateComponents([.year], from: date, to: now).year ?? (months / 12)
        )
        return "\(years)y"
    }
}

private struct ChatSidebarConversationStatusView: View {
    let isVisible: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isVisible {
                ProgressView()
                    .controlSize(.mini)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.82)),
                            removal: .opacity.combined(with: .scale(scale: 0.82))
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.22, bounce: 0.08), value: isVisible)
    }
}

private struct ChatSidebarLoadMoreRow: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isLoading {
                    AnimatedLogo(config: loadingLogoConfig)
                        .frame(width: 16, height: 14)
                }
            }
            .frame(width: 16, height: 16)
            .foregroundStyle(.secondary)

            Text(
                isLoading
                    ? String(localized: "Loading older conversations…")
                    : String(localized: "Scroll to load older conversations")
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loadingLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .secondary.opacity(0.68)
        config.strokeWidth = 1.2
        config.enterDrawDuration = 1.1
        config.enterMoveDuration = 1.1
        config.waitDuration = 0.25
        config.exitDrawDuration = 0.7
        config.exitMoveDuration = 0.7
        config.loopInterval = 0.12
        return config
    }
}

private struct ChatSidebarStatusView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ChatSidebarLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            AnimatedLogo(config: loadingLogoConfig)
                .frame(width: 28, height: 24)

            Text(title)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var loadingLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .secondary.opacity(0.68)
        config.strokeWidth = 2
        config.enterDrawDuration = 1.15
        config.enterMoveDuration = 1.15
        config.waitDuration = 0.25
        config.exitDrawDuration = 0.75
        config.exitMoveDuration = 0.75
        config.loopInterval = 0.15
        return config
    }
}

private struct ChatSidebarErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(String(localized: "Retry"), action: retry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

@MainActor
private struct ChatMainWindowAnchorView: NSViewRepresentable {
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
private final class ChatMainWindowHeaderPopupMonitor {
    weak var popupView: NSView?

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
    }

    private func handle(
        _ event: NSEvent,
        isPresented: Binding<Bool>,
        animation: Animation
    ) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            withAnimation(animation) {
                isPresented.wrappedValue = false
            }
            return nil
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

private struct ChatMainWindowHeaderMenuContentTransitionModifier: ViewModifier {
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

private extension AnyTransition {
    static var chatMainWindowHeaderMenuContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ChatMainWindowHeaderMenuContentTransitionModifier(opacity: 0, blur: 18, scale: 0.96),
                identity: ChatMainWindowHeaderMenuContentTransitionModifier(opacity: 1, blur: 0, scale: 1)
            ),
            removal: .modifier(
                active: ChatMainWindowHeaderMenuContentTransitionModifier(opacity: 0, blur: 14, scale: 0.98),
                identity: ChatMainWindowHeaderMenuContentTransitionModifier(opacity: 1, blur: 0, scale: 1)
            )
        )
    }
}
