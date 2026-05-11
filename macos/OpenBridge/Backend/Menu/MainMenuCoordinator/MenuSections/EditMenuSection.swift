import AppKit
import Cocoa

@MainActor
final class EditMenuSection: MainMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = makeEditMenu()
        return [editMenuItem]
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Undo"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Redo"),
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))

        menu.addItem(makeFirstResponderItem(
            title: String(localized: "Select All"),
            action: #selector(NSStandardKeyBindingResponding.selectAll(_:)),
            keyEquivalent: "a"
        ))

        return menu
    }

    private func makeFirstResponderItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
