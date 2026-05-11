import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct OpenBridgeShortcutRecorder<Label: View>: View {
    private let name: KeyboardShortcuts.Name
    private let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?
    private let hasLabel: Bool
    private let label: Label

    init(
        _ title: LocalizedStringKey,
        name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) where Label == Text {
        self.init(
            for: name,
            onChange: onChange,
            hasLabel: true
        ) {
            Text(title)
        }
    }

    init(
        _ title: String,
        name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) where Label == Text {
        self.init(
            for: name,
            onChange: onChange,
            hasLabel: true
        ) {
            Text(title)
        }
    }

    init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            for: name,
            onChange: onChange,
            hasLabel: true,
            label: label
        )
    }

    init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) where Label == EmptyView {
        self.init(
            for: name,
            onChange: onChange,
            hasLabel: false,
            label: { EmptyView() }
        )
    }

    private init(
        for name: KeyboardShortcuts.Name,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil,
        hasLabel: Bool,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.onChange = onChange
        self.hasLabel = hasLabel
        self.label = label()
    }

    var body: some View {
        Group {
            if hasLabel {
                if #available(macOS 13, *) {
                    LabeledContent {
                        RecorderButton(name: name, onChange: onChange)
                    } label: {
                        label
                    }
                } else {
                    HStack {
                        label
                        Spacer()
                        RecorderButton(name: name, onChange: onChange)
                    }
                }
            } else {
                RecorderButton(name: name, onChange: onChange)
            }
        }
    }
}

@MainActor
private struct RecorderButton: View {
    let name: KeyboardShortcuts.Name
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    @State private var isRecording = false
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var previewShortcut: KeyboardShortcuts.Shortcut?
    @State private var errorMessage: String?
    @State private var eventMonitor: LocalEventMonitor?
    @State private var hasTemporarilyDisabledShortcut = false
    @State private var pendingShortcut: KeyboardShortcuts.Shortcut?
    @State private var pendingKeyCode: UInt16?
    @State private var shouldClearOnCommit = false
    @State private var livePreviewText: String?
    @State private var isEnabled = false

    private var buttonLabel: String? {
        guard let shortcut = currentShortcut else { return nil }
        guard isEnabled else { return nil }
        return shortcut.description.lowercased()
    }

    private var isNotSet: Bool {
        buttonLabel == nil
    }

    private let modifierKeyCodes: Set<UInt16> = [
        54, // Right Command
        55, // Left Command
        56, // Left Shift
        57, // Caps Lock
        58, // Left Option
        59, // Left Control
        60, // Right Shift
        61, // Right Option
        62, // Right Control
        63, // Function
    ]

    init(name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?) {
        self.name = name
        self.onChange = onChange
        _currentShortcut = State(initialValue: KeyboardShortcuts.getShortcut(for: name))
        _isEnabled = State(initialValue: GlobalShortcutManager.isEnabled(name))
    }

    var body: some View {
        Button {
            guard !isRecording else {
                return
            }
            startRecording()
            isRecording = true
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
        .onChange(of: isRecording) { _, isRecording in
            if !isRecording {
                stopRecording()
            }
        }
        .onReceiveNotification(name: .keyboardShortcutsShortcutDidChange) { notification in
            guard notification.userInfo?["name"] as? KeyboardShortcuts.Name == name else { return }
            currentShortcut = KeyboardShortcuts.getShortcut(for: name)
            isEnabled = GlobalShortcutManager.isEnabled(name)
        }
        .overlay(alignment: .trailing) {
            if !isNotSet {
                Image(systemName: "xmark")
                    .foregroundColor(.gray)
                    .padding(.trailing, 4)
                    .onTapGesture {
                        disableShortcut(for: name)
                    }
            }
        }
    }

    private func disableShortcut(for name: KeyboardShortcuts.Name) {
        GlobalShortcutManager.disable(name)
        isEnabled = false
        currentShortcut = nil
        AnalyticsManager.track(.init(do: .settingsShortcutChanged(shortcutKey: name.rawValue, newShortcut: nil)))
    }

    private func startRecording() {
        previewShortcut = nil
        errorMessage = nil
        livePreviewText = nil
        if !hasTemporarilyDisabledShortcut {
            KeyboardShortcuts.disable(name)
            hasTemporarilyDisabledShortcut = true
        }
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
        shouldClearOnCommit = false
        livePreviewText = nil
        if hasTemporarilyDisabledShortcut {
            KeyboardShortcuts.enable(name)
            hasTemporarilyDisabledShortcut = false
        }
    }

    private func cancelRecording() {
        isRecording = false
    }

    private func commit(shortcut: KeyboardShortcuts.Shortcut?) {
        if errorMessage == nil {
            GlobalShortcutManager.enable(name)
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            isEnabled = true
            AnalyticsManager.track(.init(do: .settingsShortcutChanged(shortcutKey: name.rawValue, newShortcut: shortcut?.description)))
        }
        currentShortcut = shortcut
        onChange?(shortcut)
        pendingShortcut = nil
        pendingKeyCode = nil
        shouldClearOnCommit = false
        isRecording = false
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
        let modifiers = event.openBridgeNormalizedModifiers
        livePreviewText = modifierPreview(for: modifiers)

        if modifiers.isEmpty, event.specialKey == .tab {
            cancelRecording()
            return event
        }

        if modifierKeyCodes.contains(event.keyCode) {
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            shouldClearOnCommit = false
            errorMessage = nil
            return nil
        }

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return nil
        }

        if modifiers.isEmpty, event.specialKey == .delete || event.specialKey == .deleteForward || event.specialKey == .backspace {
            return nil
        }

        guard !modifiers.subtracting([.shift, .function]).isEmpty || event.specialKey?.isFunctionKey == true else {
            NSSound.beep()
            errorMessage = "Please include Command, Control, Option, or use a function key."
            previewShortcut = nil
            livePreviewText = nil
            pendingKeyCode = event.keyCode
            shouldClearOnCommit = true
            return nil
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return nil
        }

        previewShortcut = shortcut
        errorMessage = nil
        livePreviewText = shortcut.description

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

        pendingShortcut = shortcut
        pendingKeyCode = event.keyCode
        shouldClearOnCommit = false
        return nil
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.openBridgeNormalizedModifiers
        livePreviewText = modifierPreview(for: modifiers)

        if modifierKeyCodes.contains(event.keyCode) {
            pendingShortcut = nil
            pendingKeyCode = nil
            shouldClearOnCommit = false
            return nil
        }

        guard let pendingKeyCode, pendingKeyCode == event.keyCode else {
            return event
        }

        if shouldClearOnCommit {
            isRecording = false
            return nil
        }

        guard let shortcut = pendingShortcut else {
            return event
        }

        commit(shortcut: shortcut)
        return nil
    }

    private func modifierPreview(for modifiers: NSEvent.ModifierFlags) -> String? {
        let symbols = modifiers.ks_symbolicRepresentation
        return symbols.isEmpty ? nil : symbols
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.openBridgeNormalizedModifiers
        livePreviewText = modifierPreview(for: modifiers)

        if modifiers.isEmpty {
            previewShortcut = nil
            pendingShortcut = nil
            pendingKeyCode = nil
            shouldClearOnCommit = false
        }

        return nil
    }

    private func menuConflict(for shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else {
            return nil
        }

        return findMenuItem(for: shortcut, in: mainMenu)
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

        return SystemShortcutsProvider.shared.containsReservedShortcut(shortcut)
    }
}

@MainActor
private final class SystemShortcutsProvider {
    static let shared = SystemShortcutsProvider()

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

private extension NSEvent.SpecialKey {
    var isFunctionKey: Bool {
        Self.functionKeys.contains(self)
    }

    private static var functionKeys: Set<NSEvent.SpecialKey> {
        [
            .f1,
            .f2,
            .f3,
            .f4,
            .f5,
            .f6,
            .f7,
            .f8,
            .f9,
            .f10,
            .f11,
            .f12,
            .f13,
            .f14,
            .f15,
            .f16,
            .f17,
            .f18,
            .f19,
            .f20,
            .f21,
            .f22,
            .f23,
            .f24,
            .f25,
            .f26,
            .f27,
            .f28,
            .f29,
            .f30,
            .f31,
            .f32,
            .f33,
            .f34,
            .f35,
        ]
    }
}

private extension NSEvent {
    var openBridgeNormalizedModifiers: NSEvent.ModifierFlags {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
    }
}

@MainActor
private func findMenuItem(for shortcut: KeyboardShortcuts.Shortcut, in menu: NSMenu) -> NSMenuItem? {
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

        if let submenu = item.submenu, let found = findMenuItem(for: shortcut, in: submenu) {
            return found
        }
    }

    return nil
}
