//
//  ChatWindowView.swift
//  OpenBridgeInterface
//
//  Created by GitHub Copilot on 20/10/2025.
//

import AppKit
import Combine
import ComposerEditor
import Foundation
import SwiftUI

struct ChatWindowView: View {
    var body: some View {
        ChatWindowViewContent()
            .modifier(ChatWindowBackgroundModifier())
    }
}

struct ChatWindowBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.safeGlassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

struct ChatWindowViewContent: View {
    @State private var surfaceModel = ChatSurfaceModel.shared
    @State private var messagesBridge: MessagesBridge
    @State private var conversationSearchModel: ChatConversationSearchModel
    @State private var voiceShortcutMonitor: LocalEventMonitor?
    @State private var searchShortcutMonitor: LocalEventMonitor?
    @State private var hostID = UUID()
    @Environment(SettingsManager.self) private var settingsManager

    private var messagePaddingTop: CGFloat {
        settingsManager.shouldUseMacOS26UI ? 64 : 48
    }

    private var headerDragHeight: CGFloat {
        settingsManager.shouldUseMacOS26UI ? 56 : 48
    }

    init() {
        let messagesBridge = MessagesBridge(chatEditorViewModel: ChatSurfaceModel.shared.editorViewModel)
        _messagesBridge = State(initialValue: messagesBridge)
        _conversationSearchModel = State(
            initialValue: ChatConversationSearchModel(
                messagesBridge: messagesBridge,
                requiresPresentation: false
            )
        )
    }

    var body: some View {
        windowContent
            .frame(minWidth: 450, minHeight: 600)
            .frame(maxWidth: 1000)
            .accessibilityIdentifier(AccessibilityID.Chat.window)
            .onAppear {
                surfaceModel.hostDidAppear(id: hostID)
                startVoiceShortcutMonitor()
                startSearchShortcutMonitor()
            }
            .onDisappear {
                surfaceModel.hostDidDisappear(id: hostID)
                stopVoiceShortcutMonitor()
                stopSearchShortcutMonitor()
            }
    }

    private var windowContent: some View {
        ZStack(alignment: .top) {
            ChatConversationSurfaceView(
                surfaceModel: surfaceModel,
                messagesBridge: messagesBridge,
                chatPresentationMode: .panel,
                messagePaddingTop: messagePaddingTop,
                onFileDrop: handleWindowFileDrop
            )

            ChatWindowHeaderBackdrop(
                height: headerDragHeight,
                maskSize: messagePaddingTop
            )
            headerContent
                .zIndex(2)
        }
    }

    private var headerContent: some View {
        ChatWindowHeader(
            searchModel: conversationSearchModel,
            onNewChat: {
                surfaceModel.openNewChat()
            },
            onSelectConversation: { conversationId in
                surfaceModel.editorViewModel.openConversation(conversationId)
            },
            onOpenLargeWindow: {
                Windows.shared.switchChatPresentationMode(to: .window)
            },
            onClose: handleCloseTapped,
            currentConversationId: surfaceModel.editorViewModel.chat?.conversationId,
            conversationTitle: surfaceModel.editorViewModel.conversationTitle,
            isConversationTitleLoaded: surfaceModel.editorViewModel.isConversationTitleLoaded,
            hasConversationMessages: surfaceModel.editorViewModel.hasConversationMessages,
            onRenameConversation: { newTitle, window in
                surfaceModel.editorViewModel.renameCurrentConversation(title: newTitle, window: window)
            }
        )
    }

    // MARK: - Voice Input Shortcut

    private func startVoiceShortcutMonitor() {
        VoiceInputShortcutHelper.ensureShortcutRegistered()
        let vm = surfaceModel.editorViewModel
        voiceShortcutMonitor = LocalEventMonitor(event: .keyDown) { event in
            VoiceInputShortcutHelper.handleEvent(
                event,
                in: .panel,
                editorViewModel: vm
            )
        }
        voiceShortcutMonitor?.start()
    }

    private func stopVoiceShortcutMonitor() {
        voiceShortcutMonitor?.stop()
        voiceShortcutMonitor = nil
    }

    private func startSearchShortcutMonitor() {
        let searchModel = conversationSearchModel
        searchShortcutMonitor = LocalEventMonitor(event: .keyDown) { event in
            guard VoiceInputShortcutHelper.isChatWindowKey else { return event }
            guard matchesSearchShortcut(event) else { return event }
            searchModel.present()
            return nil
        }
        searchShortcutMonitor?.start()
    }

    private func stopSearchShortcutMonitor() {
        searchShortcutMonitor?.stop()
        searchShortcutMonitor = nil
    }

    private func matchesSearchShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])

        guard modifiers == [.command] else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "f"
    }

    func handleCloseTapped() {
        closeChatWindow()
    }

    func closeChatWindow() {
        conversationSearchModel.dismiss()
        Windows.shared.close(.chat)
    }

    private func handleWindowFileDrop(_ pasteboard: NSPasteboard) -> Bool {
        surfaceModel.editorViewModel.handleFileDrop(pasteboard)
    }
}

struct ChatWindowComposerSection: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var editorViewModel: ChatEditorViewModel
    let scheduleStore: ScheduleStore
    let chatPresentationMode: ChatPresentationMode

    private var usesNativeLiquidGlassComposer: Bool {
        guard chatPresentationMode == .window,
              settingsManager.shouldUseMacOS26UI
        else {
            return false
        }

        guard #available(macOS 26.0, *) else {
            return false
        }

        switch settingsManager.glassMaterialMode {
        case .auto, .liquidGlass:
            return true
        case .legacy:
            return false
        }
    }

    private var usesLegacyLargeWindowLightComposerBackground: Bool {
        colorScheme == .light
            && chatPresentationMode == .window
            && !usesNativeLiquidGlassComposer
    }

    private var composerAppearance: ComposerAppearance {
        if usesNativeLiquidGlassComposer {
            return ComposerAppearance(
                showBackground: false,
                showBorder: true,
                showShadow: true,
                glassMaterial: colorScheme == .light
                    ? .regular.tint(.white, opacity: 1)
                    : .regular.tint(.white, opacity: 0.04),
                cornerRadius: 16,
                padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12),
                layoutMode: .standard
            )
        }

        if usesLegacyLargeWindowLightComposerBackground {
            return ComposerAppearance(
                showBackground: false,
                showBorder: true,
                showShadow: true,
                cornerRadius: 16,
                padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12),
                layoutMode: .standard
            )
        }

        return .standalone
    }

    var body: some View {
        ComposerEditor.ComposerView(
            viewModel: editorViewModel,
            accentColor: SettingsManager.shared.accentColor,
            accentForegroundColor: SettingsManager.shared.accentColorForegroundColor,
            placeholder: editorViewModel.selectedSkill?.placeholder ?? String(localized: "Ask anything"),
            appearance: composerAppearance,
            leadingModelSelector: editorViewModel.composerRealModelSelectorConfig,
            modelSelector: editorViewModel.composerModelSelectorConfig,
            voiceInput: editorViewModel.composerVoiceInputConfig,
            commandDataSource: SkillCommandDataSource.shared,
            onCommandSelected: { [editorViewModel] command in
                guard let skill = SkillManager.shared.skills.first(where: { $0.id == command.id }) else { return }
                if editorViewModel.chat != nil {
                    editorViewModel.selectSkill(skill)
                } else {
                    editorViewModel.activateSkill(skill)
                }
            },
            activeCommandBadge: editorViewModel.selectedSkill.map { skill in
                ActiveCommandBadge(
                    icon: SkillCommandDataSource.shared.renderSkillIcon(for: skill),
                    name: skill.displayName,
                    subtitle: skill.sourceRepo,
                    onDismiss: { editorViewModel.clearSelectedSkill() },
                    badgeAccessibilityID: AccessibilityID.Chat.skillBadge,
                    dismissAccessibilityID: AccessibilityID.Chat.skillDismissButton
                )
            },
            draftQuoteBadge: editorViewModel.draftQuote.flatMap { quote in
                guard let text = quote.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else {
                    return nil
                }

                return DraftQuoteBadge(
                    text: text,
                    onActivate: { editorViewModel.focusDraftQuote() },
                    onDismiss: { editorViewModel.clearQuote() }
                )
            },
            additionalMenuItems: { [editorViewModel] in
                buildComposerMenuItems(
                    editorViewModel: editorViewModel,
                    scheduleStore: scheduleStore
                )
            },
            allowsExternalFileDrop: false
        )
        .accessibilityIdentifier(AccessibilityID.Chat.composer)
        .overlay(alignment: .top) {
            if editorViewModel.selectedSkill == nil,
               let skill = editorViewModel.skillAutoMatcher.suggestedSkill
            {
                AutoSkillSuggestionOverlay(
                    skill: skill,
                    onRun: { editorViewModel.acceptAutoSuggestion() },
                    onDismiss: { editorViewModel.dismissAutoSuggestion() }
                )
                .offset(y: -50)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(
            .spring(duration: 0.28, bounce: 0.2),
            value: editorViewModel.skillAutoMatcher.suggestedSkill?.name
        )
        .background {
            if usesLegacyLargeWindowLightComposerBackground {
                RoundedRectangle(cornerRadius: composerAppearance.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .background {
            Color.clear
                .alert(
                    String(localized: "Microphone Access Required"),
                    isPresented: Binding(
                        get: { editorViewModel.isMicrophoneSettingsPromptPresented },
                        set: { isPresented in
                            if !isPresented {
                                editorViewModel.dismissMicrophoneSettingsPrompt()
                            }
                        }
                    )
                ) {
                    Button(String(localized: "Cancel"), role: .cancel) {
                        editorViewModel.dismissMicrophoneSettingsPrompt()
                    }
                    Button(String(localized: "Open settings")) {
                        editorViewModel.openMicrophoneSettings()
                    }
                } message: {
                    Text(String(localized: "Microphone access is required to record voice input."))
                }
        }
        .alert(
            editorViewModel.voiceAlert?.title ?? String(localized: "Voice Transcription Failed"),
            isPresented: Binding(
                get: { editorViewModel.voiceAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        editorViewModel.clearVoiceAlert()
                    }
                }
            )
        ) {
            switch editorViewModel.voiceAlert {
            case .transcriptionError, .none:
                Button(String(localized: "OK"), role: .cancel) {
                    editorViewModel.clearVoiceAlert()
                }
            }
        } message: {
            Text(editorViewModel.voiceAlert?.message ?? "")
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 800)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear {
            editorViewModel.refreshMicrophonePermissionState()
            editorViewModel.isFocused = true
        }
        .onReceiveNotification(name: NSWindow.didBecomeKeyNotification) { _ in
            editorViewModel.isFocused = true
        }
        .onReceiveNotification(name: .microphonePermissionDidChange) { _ in
            editorViewModel.refreshMicrophonePermissionState()
        }
        .onReceiveNotification(name: NSApplication.didBecomeActiveNotification) { _ in
            editorViewModel.refreshMicrophonePermissionState()
        }
        .onReceiveNotification(name: .windowDidOpen) { notification in
            guard let kind = notification.object as? Windows.Kind, kind == .chat else { return }
            editorViewModel.isFocused = true
        }
        .onChange(of: editorViewModel.text) { _, newValue in
            editorViewModel.skillAutoMatcher.updateInput(
                newValue,
                hasManualSkill: editorViewModel.selectedSkill != nil
            )
        }
        .onReceiveNotification(name: .skillActivationRequested) { notification in
            guard let skill = notification.object as? Skill else { return }
            editorViewModel.activateSkill(skill)
        }
    }
}

// MARK: - Skill Menu Items

private struct AutoSkillSuggestionOverlay: View {
    let skill: Skill
    let onRun: () -> Void
    let onDismiss: () -> Void

    @State private var isHoveringDismissButton = false
    @State private var isHoveringRunButton = false

    private var runButtonTitle: String {
        String(localized: "Run")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: SkillCommandDataSource.shared.renderSkillIcon(for: skill))
                .resizable()
                .frame(width: 16, height: 16)

            Text(skill.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.black.opacity(isHoveringDismissButton ? 0.08 : 0.001))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHoveringDismissButton ? 1 : 0.72)
            .onHover { isHoveringDismissButton = $0 }
            .accessibilityIdentifier(AccessibilityID.Chat.autoSkillDismissButton)

            Divider()
                .frame(height: 12)

            Button {
                onRun()
            } label: {
                Text(runButtonTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsManager.shared.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 28)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SettingsManager.shared.accentColor.opacity(isHoveringRunButton ? 0.18 : 0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
            .onHover { isHoveringRunButton = $0 }
            .accessibilityIdentifier(AccessibilityID.Chat.autoSkillRunButton)
            .accessibilityLabel(Text(runButtonTitle))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .accessibilityIdentifier(AccessibilityID.Chat.autoSkillBadge)
    }
}

private let skillMenuMaxVisible = 3

@MainActor
private func buildComposerMenuItems(
    editorViewModel: ChatEditorViewModel,
    scheduleStore: ScheduleStore
) -> [NSMenuItem] {
    let skillItems = buildSkillMenuItems(editorViewModel: editorViewModel)
    guard !scheduleStore.items.isEmpty else { return skillItems }
    return skillItems + [makeScheduleMenuItem(items: scheduleStore.items)]
}

@MainActor
private func buildSkillMenuItems(editorViewModel: ChatEditorViewModel) -> [NSMenuItem] {
    let skills = SkillManager.shared.skills
        .filter { !$0.disabled && $0.visibility != .hidden }
    guard !skills.isEmpty else { return [] }

    let handler = SkillMenuActionHandler { skillID in
        guard let skill = SkillManager.shared.skills.first(where: { $0.id == skillID }) else { return }
        editorViewModel.activateSkill(skill)
    }

    var items: [NSMenuItem] = []

    for skill in skills.prefix(skillMenuMaxVisible) {
        items.append(makeSkillMenuItem(skill: skill, handler: handler))
    }

    if skills.count > skillMenuMaxVisible {
        let moreItem = NSMenuItem(
            title: String(localized: "More Skills"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        for skill in skills.dropFirst(skillMenuMaxVisible) {
            submenu.addItem(makeSkillMenuItem(skill: skill, handler: handler))
        }
        moreItem.submenu = submenu
        items.append(moreItem)
    }

    if let first = items.first {
        objc_setAssociatedObject(first, "skillHandler", handler, .OBJC_ASSOCIATION_RETAIN)
    }

    return items
}

@MainActor
private func makeSkillMenuItem(skill: Skill, handler: SkillMenuActionHandler) -> NSMenuItem {
    let item = NSMenuItem(
        title: skill.displayName,
        action: #selector(SkillMenuActionHandler.selectSkill(_:)),
        keyEquivalent: ""
    )
    item.target = handler
    item.representedObject = skill.id
    item.image = SkillCommandDataSource.shared.renderSkillIcon(for: skill)
    return item
}

private final class SkillMenuActionHandler: NSObject {
    let onSelect: (String) -> Void

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    @objc
    func selectSkill(_ sender: NSMenuItem) {
        guard let skillID = sender.representedObject as? String else { return }
        onSelect(skillID)
    }
}

#Preview {
    ChatWindowView()
        .frame(width: 500, height: 600)
}
