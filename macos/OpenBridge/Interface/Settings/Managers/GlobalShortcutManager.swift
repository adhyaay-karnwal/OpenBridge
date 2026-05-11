//
//  GlobalShortcutManager.swift
//  OpenBridgeInterface
//
//  Created by GitHub Copilot on 20/10/2025.
//

import AppKit
import Foundation
import KeyboardShortcuts

// MARK: - Global Shortcut Manager

// This class manages the global shortcuts for the application.
// ⚠️ The "Global" in the name means that the shortcuts works even application is not active.

@MainActor
@Observable
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var registeredFeatures: [String: ShortcutFeature] = [:]
    private var listeners: [String: Task<Void, Never>] = [:]

    // MARK: - Shortcut Feature Definition

    struct ShortcutFeature: Hashable, Identifiable {
        var id: String {
            key
        }

        let key: String
        let name: String
        let description: String
        let defaultShortcut: KeyboardShortcuts.Shortcut
        let showInStatusMenu: Bool
        let iconSystemName: String?
        let handler: () -> Void

        init(
            key: String,
            name: String,
            description: String,
            defaultShortcut: KeyboardShortcuts.Shortcut,
            showInStatusMenu: Bool = false,
            iconSystemName: String? = nil,
            handler: @escaping () -> Void
        ) {
            self.key = key
            self.name = name
            self.description = description
            self.defaultShortcut = defaultShortcut
            self.showInStatusMenu = showInStatusMenu
            self.iconSystemName = iconSystemName
            self.handler = handler
        }

        var keyboardShortcutName: KeyboardShortcuts.Name {
            KeyboardShortcuts.Name(key, default: defaultShortcut)
        }

        func performAction() {
            handler()
        }

        static func == (lhs: ShortcutFeature, rhs: ShortcutFeature) -> Bool {
            lhs.key == rhs.key
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(key)
        }
    }

    // MARK: - Public API

    static var features: [ShortcutFeature] {
        Array(shared.registeredFeatures.values)
    }

    static func feature(for key: String) -> ShortcutFeature? {
        shared.registeredFeatures[key]
    }

    func register(_ feature: ShortcutFeature) {
        let key = feature.key
        guard registeredFeatures[key] == nil else {
            Logger.app.warning("Shortcut already registered: \(key)")
            return
        }

        registeredFeatures[key] = feature

        let name = feature.keyboardShortcutName
        Self.migrateLegacyDisabledStateIfNeeded(for: name)

        if Self.isEnabled(name) {
            KeyboardShortcuts.enable(name)
        }

        listeners[key] = Task { [weak self] in
            await self?.listen(for: feature)
        }

        Logger.app.debug("Registered shortcut: \(key)")
    }

    func unregister(key: String) {
        guard let feature = registeredFeatures.removeValue(forKey: key) else {
            Logger.app.warning("Shortcut not found for unregister: \(key)")
            return
        }

        listeners[key]?.cancel()
        listeners.removeValue(forKey: key)

        KeyboardShortcuts.disable(feature.keyboardShortcutName)

        Logger.app.debug("Unregistered shortcut: \(key)")
    }

    func shortcut(for key: String) -> KeyboardShortcuts.Shortcut? {
        registeredFeatures[key]?.keyboardShortcutName.shortcut
    }

    func resetToDefaults() {
        registeredFeatures.values.forEach { resetToDefault(for: $0.keyboardShortcutName) }
    }

    func resetToDefault(for name: KeyboardShortcuts.Name) {
        guard let feature = registeredFeatures[name.rawValue] else { return }
        Self.enable(name)
        KeyboardShortcuts.setShortcut(feature.defaultShortcut, for: name)
    }

    // MARK: - Private

    private init() {}

    private func listen(for feature: ShortcutFeature) async {
        let name = feature.keyboardShortcutName
        for await event in KeyboardShortcuts.events(for: name) where event == .keyUp {
            guard GlobalShortcutManager.isEnabled(name) else {
                Logger.app.debug("Ignoring shortcut for disabled feature: \(name.rawValue)")
                continue
            }

            AnalyticsManager.track(.init(do: .shortcutTriggered(shortcutKey: feature.key)))
            feature.performAction()
        }
    }
}
