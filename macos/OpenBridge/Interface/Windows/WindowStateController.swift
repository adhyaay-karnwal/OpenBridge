//
//  WindowStateController.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit

@MainActor
final class WindowStateController {
    private nonisolated struct WindowState: Codable {
        struct ScreenState: Codable {
            let displayID: UInt32
            let size: CGSize
        }

        let frame: CGRect
        let screen: ScreenState
    }

    private weak var window: NSWindow?
    private let preferredContentSize: NSSize
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow, preferredContentSize: NSSize) {
        self.window = window
        self.preferredContentSize = preferredContentSize

        applyInitialState()
        startObserving(window: window)
    }

    @MainActor
    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func applyEmptyState() {
        window?.setContentSize(preferredContentSize)
        window?.center()
    }

    private func applyInitialState() {
        guard let window, let identifier = window.identifier?.rawValue else {
            return
        }

        guard let state = loadState(for: identifier) else {
            applyEmptyState()
            return
        }

        guard let screen = NSScreen.screen(withDisplayID: state.screen.displayID),
              sizesMatch(screen.frame.size, state.screen.size)
        else {
            clearState(for: identifier)
            applyEmptyState()
            return
        }

        if let extendablePanel = window as? NSExtendablePanel {
            extendablePanel.setBaseContentFrame(state.frame)
        } else {
            window.setFrame(state.frame, display: false)
        }
    }

    private func startObserving(window: NSWindow) {
        let notifications: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.willCloseNotification,
        ]
        let center = NotificationCenter.default
        for name in notifications {
            observers.append(center.addObserver(
                forName: name,
                object: window,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated { self?.persistState() }
                }
            ))
        }
    }

    private func persistState() {
        guard
            let window,
            let identifier = window.identifier?.rawValue
        else {
            return
        }

        let screenCandidate = window.screen ?? NSScreen.main
        guard let screen = screenCandidate, let displayID = screen.displayID else {
            return
        }

        let frameToSave: NSRect = if let extendablePanel = window as? NSExtendablePanel {
            extendablePanel.baseContentFrame
        } else {
            window.frame
        }

        let state = WindowState(
            frame: frameToSave,
            screen: .init(
                displayID: displayID,
                size: screen.frame.size
            )
        )

        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey(for: identifier))
    }

    func resetWindowFrameToPreferredContentSize() {
        guard let window else { return }
        window.setContentSize(preferredContentSize)
        window.center()
    }
}

private nonisolated extension WindowStateController {
    private func loadState(for identifier: String) -> WindowState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: identifier)) else {
            return nil
        }
        return try? JSONDecoder().decode(WindowState.self, from: data)
    }

    private func clearState(for identifier: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: identifier))
    }

    private func storageKey(for identifier: String) -> String {
        "openbridge.window.state.\(identifier)"
    }

    private func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        let tolerance: CGFloat = 1
        return abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
