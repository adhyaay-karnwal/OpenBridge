//
//  ChatWindowHeaderView.swift
//  OpenBridgeInterface
//

import AppKit
import SwiftUI

private enum ChatWindowHeaderMetrics {
    static let overlayHeight: CGFloat = 48
}

struct ChatWindowHeader: View {
    @Environment(SettingsManager.self) private var settingsManager

    private let searchModel: ChatConversationSearchModel
    private let onNewChat: (() -> Void)?
    private let onClose: () -> Void
    private let onOpenLargeWindow: (() -> Void)?
    private let onSelectConversation: ((String) -> Void)?
    private let currentConversationId: String?
    private let conversationTitle: String
    private let isConversationTitleLoaded: Bool
    private let hasConversationMessages: Bool
    private let onRenameConversation: ((String, NSWindow?) -> Void)?
    private let onShareLink: ((SessionListInfo) -> Void)?

    init(
        searchModel: ChatConversationSearchModel,
        onNewChat: (() -> Void)? = nil,
        onSelectConversation: ((String) -> Void)? = nil,
        onOpenLargeWindow: (() -> Void)? = nil,
        onClose: @escaping () -> Void = {},
        currentConversationId: String? = nil,
        conversationTitle: String = "",
        isConversationTitleLoaded: Bool = false,
        hasConversationMessages: Bool = false,
        onRenameConversation: ((String, NSWindow?) -> Void)? = nil,
        onShareLink: ((SessionListInfo) -> Void)? = nil
    ) {
        self.searchModel = searchModel
        self.onClose = onClose
        self.onNewChat = onNewChat
        self.onSelectConversation = onSelectConversation
        self.onOpenLargeWindow = onOpenLargeWindow
        self.currentConversationId = currentConversationId
        self.conversationTitle = conversationTitle
        self.isConversationTitleLoaded = isConversationTitleLoaded
        self.hasConversationMessages = hasConversationMessages
        self.onRenameConversation = onRenameConversation
        self.onShareLink = onShareLink
    }

    var body: some View {
        headerContent
            .modifier(HeaderPaddingModifier())
            .modifier(LegacyHeaderHeightModifier())
            .zIndex(1)
    }

    private var headerContent: some View {
        HStack {
            leadingControls

            Spacer()

            ChatWindowHeaderActions(
                searchModel: searchModel,
                currentConversationId: currentConversationId,
                onSelectConversation: onSelectConversation,
                onNewChat: onNewChat,
                onShareLink: onShareLink,
                onOpenLargeWindow: onOpenLargeWindow,
                onAuxiliaryInteraction: dismissSearchIfNeeded,
                searchActivationToken: searchModel.activationToken
            )
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .center) {
            conversationTitleView
        }
        .zIndex(1)
    }

    @ViewBuilder
    private var conversationTitleView: some View {
        if currentConversationId != nil, hasConversationMessages, isConversationTitleLoaded {
            ConversationTitleView(
                title: conversationTitle,
                onRename: onRenameConversation
            )
        }
    }

    private func dismissSearchIfNeeded() {
        searchModel.dismiss()
    }

    @ViewBuilder
    private var leadingControls: some View {
        if settingsManager.shouldUseMacOS26UI {
            if #available(macOS 26.0, *) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .padding(8)
                        .background {
                            Circle()
                                .fill(.clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .chatHeaderLiquidGlass(in: Circle())
                .accessibilityIdentifier(AccessibilityID.Chat.closeButton)
            } else {
                legacyLeadingControls
            }
        } else {
            legacyLeadingControls
        }
    }

    private var legacyLeadingControls: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(AccessibilityID.Chat.closeButton)
        .padding(.leading, 8)
    }
}

private struct HeaderPaddingModifier: ViewModifier {
    @Environment(SettingsManager.self) private var settingsManager

    func body(content: Content) -> some View {
        if settingsManager.shouldUseMacOS26UI {
            content
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
        } else {
            content
                .padding(.top, 16)
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
        }
    }
}

private struct LegacyHeaderHeightModifier: ViewModifier {
    @Environment(SettingsManager.self) private var settingsManager

    func body(content: Content) -> some View {
        if settingsManager.shouldUseMacOS26UI {
            content
        } else {
            content.frame(height: ChatWindowHeaderMetrics.overlayHeight, alignment: .top)
        }
    }
}

private enum ChatWindowHeaderBackdropStyle {
    static let mask = BackdropBlurMaskStyle(
        heightMultiplier: 1.7,
        topOffsetMultiplier: -0.5,
        layers: [
            .init(transitionPoint: 0.70, blurRadius: 1),
            .init(transitionPoint: 0.60, blurRadius: 2),
            .init(transitionPoint: 0.50, blurRadius: 4),
            .init(transitionPoint: 0.30, blurRadius: 10),
            .init(transitionPoint: 0.00, blurRadius: 32),
        ]
    )
}

struct ChatWindowHeaderBackdrop: View {
    @Environment(SettingsManager.self) private var settingsManager

    let height: CGFloat
    let maskSize: CGFloat

    private var backdropHeight: CGFloat {
        max(height, ChatWindowHeaderBackdropStyle.mask.height(for: maskSize))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if settingsManager.shouldUseMacOS26UI {
                BackdropBlurMaskView(
                    baseSize: maskSize,
                    style: ChatWindowHeaderBackdropStyle.mask
                )
            }

            HeaderDragAreaView()
                .frame(height: height)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: backdropHeight,
            alignment: .top
        )
    }
}

private struct HeaderDragAreaView: NSViewRepresentable {
    func makeNSView(context _: Context) -> HeaderDragNSView {
        HeaderDragNSView()
    }

    func updateNSView(_: HeaderDragNSView, context _: Context) {}
}

private final class HeaderDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct ChatWindowHeaderActions: View {
    @Environment(SettingsManager.self) private var settingsManager

    let searchModel: ChatConversationSearchModel
    let currentConversationId: String?
    let onSelectConversation: ((String) -> Void)?
    let onNewChat: (() -> Void)?
    let onShareLink: ((SessionListInfo) -> Void)?
    let onOpenLargeWindow: (() -> Void)?
    let onAuxiliaryInteraction: (() -> Void)?
    let searchActivationToken: Int

    var body: some View {
        HStack(spacing: 8) {
            switchPresentationButton

            if settingsManager.shouldUseMacOS26UI,
               #available(macOS 26, *),
               let onSelectConversation,
               let onNewChat
            {
                ConversationHistoryLiquidActionGroup(
                    searchModel: searchModel,
                    currentConversationId: currentConversationId,
                    onSelect: onSelectConversation,
                    onNewChat: onNewChat,
                    onShareLink: onShareLink,
                    onAuxiliaryInteraction: onAuxiliaryInteraction,
                    searchActivationToken: searchActivationToken
                )
            } else {
                newChatButton
                conversationHistoryButton
                moreMenuButton
            }
        }
    }

    @ViewBuilder
    private var conversationHistoryButton: some View {
        if let onSelectConversation, let onNewChat {
            ConversationHistoryMenuButton(
                searchModel: searchModel,
                currentConversationId: currentConversationId,
                onSelect: onSelectConversation,
                onNewChat: onNewChat,
                onShareLink: onShareLink,
                onBeforePresentMenu: onAuxiliaryInteraction,
                searchActivationToken: searchActivationToken
            )
            .accessibilityIdentifier(AccessibilityID.Chat.historyButton)
        } else {
            Button(action: {}) {
                Image(systemName: "clock")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AccessibilityID.Chat.historyButton)
        }
    }

    @ViewBuilder
    private var switchPresentationButton: some View {
        if let onOpenLargeWindow {
            if settingsManager.shouldUseMacOS26UI, #available(macOS 26, *) {
                Button(action: {
                    onAuxiliaryInteraction?()
                    onOpenLargeWindow()
                }) {
                    Image(systemName: "macwindow.on.rectangle")
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .chatHeaderLiquidGlass(in: Circle())
                .help(String(localized: "Open in Large Window"))
                .accessibilityIdentifier(AccessibilityID.Chat.switchPresentationButton)
            } else {
                Button(action: {
                    onAuxiliaryInteraction?()
                    onOpenLargeWindow()
                }) {
                    Image(systemName: "macwindow.on.rectangle")
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Open in Large Window"))
                .accessibilityIdentifier(AccessibilityID.Chat.switchPresentationButton)
            }
        }
    }

    @ViewBuilder
    private var newChatButton: some View {
        if let onNewChat {
            Button(action: {
                onAuxiliaryInteraction?()
                onNewChat()
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)
            .help("New Chat (⌘N)")
            .accessibilityIdentifier(AccessibilityID.Chat.newChatButton)
        }
    }

    private var moreMenuButton: some View {
        LegacyHeaderMoreMenuButton(onAuxiliaryInteraction: onAuxiliaryInteraction)
            .accessibilityIdentifier(AccessibilityID.Chat.moreButton)
    }
}

private struct LegacyHeaderMoreMenuButton: View {
    let onAuxiliaryInteraction: (() -> Void)?

    @State private var anchorView: NSView?

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: "ellipsis")
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help(String(localized: "More…"))
        .accessibilityLabel(String(localized: "More…"))
        .background {
            HeaderMenuAnchorView { anchorView = $0 }
        }
    }

    private func showMenu() {
        guard let anchorView, let window = anchorView.window else { return }

        onAuxiliaryInteraction?()

        let menu = NSMenu()
        menu.autoenablesItems = true
        menu.appearance = window.effectiveAppearance

        menu.addItem(makeMenuItem(title: String(localized: "Settings")) {
            Windows.shared.open(.settings)
        })
        menu.addItem(makeMenuItem(
            title: String(localized: "Open Skill Settings"),
            identifier: AccessibilityID.Chat.moreMenuOpenSkillSettings
        ) {
            SettingsNavigation.shared.navigate(to: .mySkills)
            Windows.shared.open(.settings)
        })
        menu.addItem(makeMenuItem(title: String(localized: "Explore More Skills")) {
            NSWorkspace.shared.open(Constant.skillsURL)
        })

        menu.popUp(positioning: nil, at: menuPopUpLocation(for: menu, anchorView: anchorView, window: window), in: nil)
    }

    private func makeMenuItem(
        title: String,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let target = ClosureSleeve(action: action)
        item.representedObject = target
        item.target = target
        item.action = #selector(ClosureSleeve.invoke)
        if let identifier {
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        return item
    }

    private func menuPopUpLocation(for menu: NSMenu, anchorView: NSView, window: NSWindow) -> CGPoint {
        let buttonBoundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonBoundsInWindow)
        let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(buttonFrameOnScreen.origin) })
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.screen?.frame ?? .zero
        let menuSize = menu.size
        let inset: CGFloat = 8

        var popUpLocation = CGPoint(
            x: buttonFrameOnScreen.maxX - menuSize.width,
            y: buttonFrameOnScreen.minY - 4
        )
        popUpLocation.x = min(
            max(popUpLocation.x, visibleFrame.minX + inset),
            max(visibleFrame.minX + inset, visibleFrame.maxX - menuSize.width - inset)
        )
        popUpLocation.y = min(
            max(popUpLocation.y, visibleFrame.minY + menuSize.height + inset),
            visibleFrame.maxY - inset
        )
        return popUpLocation
    }
}

private struct HeaderMenuAnchorView: NSViewRepresentable {
    let onUpdate: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
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

private final class ClosureSleeve: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

// MARK: - Conversation Title View

private struct ConversationTitleView: View {
    let title: String
    let onRename: ((String, NSWindow?) -> Void)?

    @State private var isHovered = false

    private var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled") : title
    }

    var body: some View {
        Text(displayTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .id(title)
            .transition(.titleMaterialize)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            )
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .animation(.spring(duration: 0.5, bounce: 0.12), value: title)
            .onHover { isHovered = $0 }
            .onTapGesture { handleRename() }
            .frame(maxWidth: 200)
    }

    private func handleRename() {
        ConversationListActionController.shared.promptForConversationRename(
            initialTitle: title,
            window: NSApp.keyWindow
        ) { newTitle, window in
            onRename?(newTitle, window)
        }
    }
}

// MARK: - Title Materialize Transition

private struct TitleMaterializeModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
            .scaleEffect(scale)
    }
}

private extension AnyTransition {
    static var titleMaterialize: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TitleMaterializeModifier(opacity: 0, blur: 8, scale: 0.94),
                identity: TitleMaterializeModifier(opacity: 1, blur: 0, scale: 1)
            ),
            removal: .modifier(
                active: TitleMaterializeModifier(opacity: 0, blur: 6, scale: 1.06),
                identity: TitleMaterializeModifier(opacity: 1, blur: 0, scale: 1)
            )
        )
    }
}

#Preview("ChatWindowHeader") {
    @Previewable @State var currentConversationId: String? = "preview-conversation"
    @Previewable @State var editorViewModel = ChatEditorViewModel()

    ZStack(alignment: .topLeading) {
        VStack {
            ChatWindowHeader(
                searchModel: ChatConversationSearchModel(
                    messagesBridge: MessagesBridge(chatEditorViewModel: editorViewModel)
                ),
                onNewChat: {
                    currentConversationId = nil
                },
                onSelectConversation: { conversationId in
                    currentConversationId = conversationId
                },
                currentConversationId: currentConversationId,
                conversationTitle: "Preview Conversation",
                isConversationTitleLoaded: true,
                hasConversationMessages: true
            )
            Spacer()
        }
        .padding(0)
    }
    .frame(width: 480, height: 600)
    .frame(alignment: .topLeading)
    .background(.black.opacity(0.2))
    .clipShape(RoundedRectangle(cornerRadius: 16.0))
    .padding()
}
