import AppKit
import KeyboardShortcuts

@MainActor
final class ShortcutItemsSection: BarMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        for feature in GlobalShortcutManager.features where feature.showInStatusMenu {
            let item = NSMenuItem(
                title: feature.name,
                action: #selector(performAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = feature.key
            if let iconName = feature.iconSystemName {
                item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            }

            if let shortcut = feature.keyboardShortcutName.shortcut,
               GlobalShortcutManager.isEnabled(feature.keyboardShortcutName)
            {
                item.setShortcut(shortcut)
            }

            items.append(item)
        }

        return items
    }

    @objc func performAction(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let feature = GlobalShortcutManager.feature(for: key)
        else {
            return
        }
        feature.performAction()
    }
}
