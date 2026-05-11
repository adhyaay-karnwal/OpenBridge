import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                SettingInfoBanner(
                    iconName: "keyboard.fill",
                    title: "Shortcuts",
                    info: "Configure global keyboard shortcuts for quick access",
                    backgroundStyle: .init(iconBackground: .gradient(.purple))
                )
            }

            Section(String(localized: "Global")) {
                ForEach(GlobalShortcutManager.features) { feature in
                    OpenBridgeShortcutRecorder(feature.name, name: feature.keyboardShortcutName)
                }
            }

            Section(String(localized: "Chat Window")) {
                ChatWindowShortcutRecorder(
                    String(localized: "Voice Input"),
                    name: .voiceInputToggle
                )
            }

            Section(footer: resetToDefaultFooter) {
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
        .onAppear {
            VoiceInputShortcutHelper.ensureShortcutRegistered()
        }
    }

    var resetToDefaultFooter: some View {
        Button("Reset to Default") {
            showResetConfirmation = true
        }
        .alert("Are you sure you want to reset all shortcuts to default?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                AnalyticsManager.track(.init(do: .settingsShortcutsReset))
                GlobalShortcutManager.shared.resetToDefaults()
                VoiceInputShortcutHelper.resetToDefault()
                showResetConfirmation = false
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Chat Window Shortcut Recorder

private struct ChatWindowShortcutRecorder: View {
    private let title: String
    private let name: KeyboardShortcuts.Name

    init(_ title: String, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    var body: some View {
        LabeledContent {
            ChatWindowShortcutRecorderButton(name: name)
        } label: {
            Text(title)
        }
    }
}

@MainActor
private struct ChatWindowShortcutRecorderButton: View {
    let name: KeyboardShortcuts.Name

    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var previewShortcut: KeyboardShortcuts.Shortcut?
    @State private var errorMessage: String?
    @State private var eventMonitor: LocalEventMonitor?
    @State private var pendingShortcut: KeyboardShortcuts.Shortcut?
    @State private var pendingKeyCode: UInt16?
    @State private var livePreviewText: String?

    private var buttonLabel: String? {
        currentShortcut?.description
    }

    private var isNotSet: Bool {
        currentShortcut == nil
    }

    private let modifierKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    ]

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        VoiceInputShortcutHelper.ensureShortcutRegistered()
        _currentShortcut = State(initialValue: KeyboardShortcuts.getShortcut(for: name))
    }

    var body: some View {
        Button {
            guard !isRecording else { return }
            startRecording()
        } label: {
            Text(buttonLabel ?? "Not set")
                .font(.body.monospaced())
                .frame(minWidth: 80)
                .kerning(isNotSet ? 0 : 2)
        }
        .buttonStyle(.bordered)
        .popover(
            isPresented: $isRecording,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            VStack(spacing: 12) {
                Text("Recording…")
                    .font(.headline)

                if let shortcut = previewShortcut {
                    Text(shortcut.description)
                        .font(.title3.monospaced())
                } else if let livePreviewText {
                    Text(livePreviewText)
                        .font(.title3.monospaced())
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.title3)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Press a new shortcut")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    cancelRecording()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .frame(width: 240)
        }
        .onChange(of: isRecording) { _, newValue in
            if !newValue { stopRecording() }
        }
        .onReceiveNotification(name: .keyboardShortcutsShortcutDidChange) { notification in
            guard notification.userInfo?["name"] as? KeyboardShortcuts.Name == name else { return }
            VoiceInputShortcutHelper.ensureShortcutRegistered()
            currentShortcut = KeyboardShortcuts.getShortcut(for: name)
        }
        .overlay(alignment: .trailing) {
            if !isNotSet {
                Image(systemName: "xmark")
                    .foregroundColor(.gray)
                    .padding(.trailing, 4)
                    .onTapGesture {
                        clearShortcut()
                    }
            }
        }
    }

    private func startRecording() {
        isRecording = true
        previewShortcut = nil
        errorMessage = nil
        livePreviewText = nil
        eventMonitor = LocalEventMonitor(event: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event: event)
        }.start()
    }

    private func stopRecording() {
        eventMonitor?.stop()
        eventMonitor = nil
        previewShortcut = nil
        errorMessage = nil
        pendingShortcut = nil
        pendingKeyCode = nil
        livePreviewText = nil
    }

    private func cancelRecording() {
        isRecording = false
    }

    private func commit(shortcut: KeyboardShortcuts.Shortcut) {
        VoiceInputShortcutHelper.setShortcut(shortcut)
        currentShortcut = KeyboardShortcuts.getShortcut(for: name)
        AnalyticsManager.track(.init(do: .settingsShortcutChanged(shortcutKey: name.rawValue, newShortcut: shortcut.description)))
        pendingShortcut = nil
        pendingKeyCode = nil
        isRecording = false
    }

    private func clearShortcut() {
        VoiceInputShortcutHelper.clearShortcut()
        currentShortcut = nil
        AnalyticsManager.track(.init(do: .settingsShortcutChanged(shortcutKey: name.rawValue, newShortcut: nil)))
    }

    private func handle(event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.normalizedModifiers

        if modifiers.isEmpty, event.keyCode == 53 {
            cancelRecording()
            return nil
        }

        if modifierKeyCodes.contains(event.keyCode) {
            livePreviewText = modifiers.ks_symbolicRepresentation.nilIfEmpty
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            errorMessage = nil
            return nil
        }

        guard !modifiers.subtracting([.shift, .function]).isEmpty
            || event.specialKey?.isFunctionKey == true
        else {
            NSSound.beep()
            errorMessage = String(localized: "Please include Command, Control, Option, or use a function key.")
            previewShortcut = nil
            livePreviewText = nil
            return nil
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return nil }

        if let menuItem = menuConflict(for: shortcut) {
            NSSound.beep()
            _ = presentAlert(
                title: "Shortcut Already In Use",
                message: "Menu item \"\(menuItem.title)\" already uses this shortcut."
            )
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            livePreviewText = nil
            return nil
        }

        if isDisallowed(shortcut) {
            NSSound.beep()
            _ = presentAlert(
                title: "Shortcut Not Allowed",
                message: "macOS 15 requires Option to be combined with Command or Control in sandboxed apps."
            )
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            livePreviewText = nil
            return nil
        }

        if isTakenBySystem(shortcut) {
            NSSound.beep()
            _ = presentAlert(
                title: "Shortcut Reserved by macOS",
                message: "This shortcut is already used by the system. You can change system shortcuts in System Settings."
            )
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            livePreviewText = nil
            return nil
        }

        previewShortcut = shortcut
        errorMessage = nil
        livePreviewText = shortcut.description
        pendingShortcut = shortcut
        pendingKeyCode = event.keyCode
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.normalizedModifiers
        livePreviewText = modifiers.ks_symbolicRepresentation.nilIfEmpty

        if modifierKeyCodes.contains(event.keyCode) {
            pendingShortcut = nil
            pendingKeyCode = nil
            return nil
        }

        guard let pendingKeyCode, pendingKeyCode == event.keyCode,
              let shortcut = pendingShortcut
        else {
            return event
        }

        commit(shortcut: shortcut)
        return nil
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.normalizedModifiers
        livePreviewText = modifiers.ks_symbolicRepresentation.nilIfEmpty

        if modifiers.isEmpty {
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
        }
        return nil
    }

    private func menuConflict(for shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else {
            return nil
        }

        return findChatWindowShortcutMenuItem(for: shortcut, in: mainMenu)
    }

    private func presentAlert(title: String, message: String?, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message ?? ""
        alert.alertStyle = .warning
        for button in buttons {
            alert.addButton(withTitle: button)
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                NSApp.stopModal(withCode: response)
            }
            return NSApp.runModal(for: window)
        }

        return alert.runModal()
    }

    private func isDisallowed(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let isSandboxed = ProcessInfo.processInfo.environment.keys.contains("APP_SANDBOX_CONTAINER_ID")

        guard osVersion.majorVersion == 15, osVersion.minorVersion == 0 || osVersion.minorVersion == 1, isSandboxed else {
            return false
        }

        guard shortcut.modifiers.contains(.option) else {
            return false
        }
        let requiredCompanions: NSEvent.ModifierFlags = [.command, .control, .function, .capsLock]
        return shortcut.modifiers.isDisjoint(with: requiredCompanions)
    }

    private func isTakenBySystem(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        if shortcut == KeyboardShortcuts.Shortcut(.f12, modifiers: []) {
            return false
        }

        return ChatWindowSystemShortcutsProvider.shared.containsReservedShortcut(shortcut)
    }
}

private extension NSEvent {
    var normalizedModifiers: NSEvent.ModifierFlags {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
    }
}

private extension NSEvent.SpecialKey {
    var isFunctionKey: Bool {
        let fKeys: Set<NSEvent.SpecialKey> = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
            .f21, .f22, .f23, .f24, .f25, .f26, .f27, .f28, .f29, .f30,
            .f31, .f32, .f33, .f34, .f35,
        ]
        return fKeys.contains(self)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
private final class ChatWindowSystemShortcutsProvider {
    static let shared = ChatWindowSystemShortcutsProvider()

    private(set) lazy var systemShortcuts: Set<KeyboardShortcuts.Shortcut> = {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr, let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        let mapped = shortcuts.compactMap { item -> KeyboardShortcuts.Shortcut? in
            guard
                (item[kHISymbolicHotKeyEnabled] as? Bool) == true,
                let keyCode = item[kHISymbolicHotKeyCode] as? Int,
                let modifiers = item[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }

            return KeyboardShortcuts.Shortcut(
                carbonKeyCode: keyCode,
                carbonModifiers: modifiers
            )
        }

        return Set(mapped)
    }()

    private let standardApplicationShortcuts: Set<KeyboardShortcuts.Shortcut> = Set([
        KeyboardShortcuts.Shortcut(.c, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.v, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.x, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.z, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.a, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.q, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.w, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.n, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.o, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.p, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.s, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.f, modifiers: [.command]),
    ])

    func containsReservedShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        systemShortcuts.contains(shortcut) || standardApplicationShortcuts.contains(shortcut)
    }
}

@MainActor
private func findChatWindowShortcutMenuItem(
    for shortcut: KeyboardShortcuts.Shortcut,
    in menu: NSMenu
) -> NSMenuItem? {
    for item in menu.items {
        var keyEquivalent = item.keyEquivalent
        var modifierMask = item.keyEquivalentModifierMask

        if shortcut.modifiers.contains(.shift), keyEquivalent.lowercased() != keyEquivalent {
            keyEquivalent = keyEquivalent.lowercased()
            modifierMask.insert(.shift)
        }

        if
            let shortcutKey = shortcut.nsMenuItemKeyEquivalent,
            !shortcutKey.isEmpty,
            shortcutKey == keyEquivalent,
            shortcut.modifiers == modifierMask
        {
            return item
        }

        if let submenu = item.submenu, let found = findChatWindowShortcutMenuItem(for: shortcut, in: submenu) {
            return found
        }
    }

    return nil
}
