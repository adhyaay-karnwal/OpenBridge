import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let voiceInputToggle = Self(
        "voiceInputToggle",
        default: .init(.m, modifiers: .control)
    )
}

@MainActor
enum VoiceInputShortcutHelper {
    enum TargetWindow: String {
        case panel = "com.openbridge.window.chat"
        case main = "com.openbridge.window.chat.main"
    }

    static let defaultShortcut = KeyboardShortcuts.Shortcut(.m, modifiers: .control)
    static let initializationStateKey = "openbridge.voiceInputShortcut.hasInitializedDefault"

    static func ensureShortcutRegistered() {
        if !hasInitializedDefault {
            if storedShortcut == nil {
                KeyboardShortcuts.setShortcut(defaultShortcut, for: .voiceInputToggle)
            }
            markInitialized()
        }

        unregisterGlobalHotKey()
    }

    static func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        markInitialized()
        KeyboardShortcuts.setShortcut(shortcut, for: .voiceInputToggle)
        unregisterGlobalHotKey()
    }

    static func resetToDefault() {
        markInitialized()
        KeyboardShortcuts.setShortcut(defaultShortcut, for: .voiceInputToggle)
        unregisterGlobalHotKey()
    }

    static func clearShortcut() {
        markInitialized()
        KeyboardShortcuts.setShortcut(nil, for: .voiceInputToggle)
        unregisterGlobalHotKey()
    }

    static var shortcutDisplayString: String? {
        ensureShortcutRegistered()
        return storedShortcut?.description
    }

    static func matches(event: NSEvent) -> Bool {
        ensureShortcutRegistered()
        guard let stored = storedShortcut,
              let eventShortcut = KeyboardShortcuts.Shortcut(event: event)
        else {
            return false
        }
        return stored == eventShortcut
    }

    static func handleEvent(
        _ event: NSEvent,
        in targetWindow: TargetWindow,
        editorViewModel: ChatEditorViewModel
    ) -> NSEvent? {
        guard isEventInTargetWindow(event, targetWindow: targetWindow) else { return event }

        if event.keyCode == 53, editorViewModel.voiceInputState != .idle {
            editorViewModel.requestCancelVoiceInput()
            return nil
        }

        guard matches(event: event) else { return event }

        switch editorViewModel.voiceInputState {
        case .idle:
            editorViewModel.requestStartVoiceRecording()
        case .recording:
            editorViewModel.requestStopVoiceRecording()
        case .transcribing:
            return event
        }

        return nil
    }

    static var isChatWindowKey: Bool {
        NSApp.keyWindow?.identifier?.rawValue == "com.openbridge.window.chat"
    }

    private static var storedShortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .voiceInputToggle)
    }

    private static var hasInitializedDefault: Bool {
        UserDefaults.standard.bool(forKey: initializationStateKey)
    }

    private static func markInitialized() {
        UserDefaults.standard.set(true, forKey: initializationStateKey)
    }

    private static func isEventInTargetWindow(_ event: NSEvent, targetWindow: TargetWindow) -> Bool {
        let windowIdentifier = event.window?.identifier?.rawValue ?? NSApp.keyWindow?.identifier?.rawValue
        return windowIdentifier == targetWindow.rawValue
    }

    /// Voice Input is handled by the chat window's local event monitor.
    /// Keep KeyboardShortcuts as persisted storage and unregister its Carbon hotkey.
    private static func unregisterGlobalHotKey() {
        KeyboardShortcuts.disable(.voiceInputToggle)
    }
}
