import KeyboardShortcuts

// MARK: - Disabled Shortcut Persistence / Migration

/// Legacy builds persisted a custom disabled flag while keeping the old shortcut value.
/// That representation lets `KeyboardShortcuts.events(for:)` re-register the hotkey on launch.
/// The current representation uses `KeyboardShortcuts.setShortcut(nil, for:)` so the library
/// persists the explicit “Not set” state and keeps the shortcut unregistered.
extension GlobalShortcutManager {
    private static func legacyDisabledPersistedKey(for name: KeyboardShortcuts.Name) -> String {
        "KeyboardShortcuts_Disabled_\(name.rawValue)"
    }

    static func migrateLegacyDisabledStateIfNeeded(for name: KeyboardShortcuts.Name) {
        let legacyKey = legacyDisabledPersistedKey(for: name)
        guard UserDefaults.standard.bool(forKey: legacyKey) else { return }

        UserDefaults.standard.removeObject(forKey: legacyKey)

        guard KeyboardShortcuts.getShortcut(for: name) != nil else { return }
        KeyboardShortcuts.setShortcut(nil, for: name)
    }

    static func disable(_ name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.setShortcut(nil, for: name)
        UserDefaults.standard.removeObject(forKey: legacyDisabledPersistedKey(for: name))
    }

    static func isEnabled(_ name: KeyboardShortcuts.Name) -> Bool {
        migrateLegacyDisabledStateIfNeeded(for: name)
        return KeyboardShortcuts.getShortcut(for: name) != nil
    }

    static func enable(_ name: KeyboardShortcuts.Name) {
        UserDefaults.standard.removeObject(forKey: legacyDisabledPersistedKey(for: name))
        KeyboardShortcuts.enable(name)
    }
}
