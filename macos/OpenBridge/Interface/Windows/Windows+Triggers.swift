//
//  Windows+Triggers.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit
import QuickLookUI

extension Windows {
    func setupWindowTriggers() {
        let notifications: [(Notification.Name, Selector)] = [
            (NSWindow.willCloseNotification, #selector(handleWindowWillClose(_:))),
            (NSWindow.didBecomeKeyNotification, #selector(handleWindowDidBecomeKey(_:))),
            (NSWindow.didResignKeyNotification, #selector(handleWindowDidResignKey(_:))),
        ]
        for (name, selector) in notifications {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    private var windowTriggers: [(_ senderWindow: NSWindow) -> Void] {
        [
            anyWindowBecomeKeyHidesMainWindow(_:),
        ]
    }

    private func decodeWindowObject(_ sender: Any?) -> NSWindow? {
        guard let notification = sender as? NSNotification,
              let window = notification.object as? NSWindow
        else {
            assertionFailure()
            return nil
        }
        let managedWindows = allManagedWindows
        guard managedWindows.contains(window) else { return nil }
        return window
    }

    @objc
    func handleWindowDidBecomeKey(_ sender: Any?) {
        guard let window = decodeWindowObject(sender) else { return }
        Logger.ui.debug("window did become key: \(window)")
        DispatchQueue.main.async {
            self.windowTriggers.forEach { $0(window) }
        }
    }

    @objc
    func handleWindowWillClose(_ sender: Any?) {
        guard let window = decodeWindowObject(sender) else { return }
        Logger.ui.debug("window will close: \(window)")
        DispatchQueue.main.async {
            self.windowTriggers.forEach { $0(window) }
        }
    }

    @objc
    func handleWindowDidResignKey(_ sender: Any?) {
        guard let window = decodeWindowObject(sender) else { return }
        Logger.ui.debug("window did resign key: \(window)")
    }

    private func handleWindowResign(
        window: NSWindow,
        for kind: Kind,
        extraCheck: @escaping () -> Bool = { true }
    ) {
        guard window == windowInstance(for: kind),
              !isPinned(kind)
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, window.isVisible, extraCheck() else { return }
            close(kind)
        }
    }

    private func anyWindowBecomeKeyHidesMainWindow(_: NSWindow) {}
}
