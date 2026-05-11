//
//  BarMenuCoordinator+Delegate.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import Cocoa

extension BarMenuCoordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Rebuild menu items to reflect latest task state
        menu.removeAllItems()
        let allItems = allSections.map { $0.sectionItems() }
        for (idx, items) in allItems.enumerated() {
            for item in items {
                menu.addItem(item)
            }
            if idx < allItems.count - 1 {
                menu.addItem(NSMenuItem.separator())
            }
        }
    }

    func menuDidClose(_: NSMenu) {
        rebuild()
    }
}
