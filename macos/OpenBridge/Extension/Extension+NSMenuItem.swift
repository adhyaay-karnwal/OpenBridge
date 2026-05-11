//
//  Extension+NSMenuItem.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit
import KeyboardShortcuts

extension NSMenuItem {
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        if let keyEquivalent = shortcut.nsMenuItemKeyEquivalent {
            self.keyEquivalent = keyEquivalent
            keyEquivalentModifierMask = shortcut.modifiers
        }
    }
}
