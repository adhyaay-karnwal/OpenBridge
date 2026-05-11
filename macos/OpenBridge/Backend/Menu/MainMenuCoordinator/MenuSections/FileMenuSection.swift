import AppKit

@MainActor
final class FileMenuSection: MainMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = makeFileMenu()
        return [fileMenuItem]
    }

    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "File"))

        let closeWindowItem = NSMenuItem(
            title: String(localized: "Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = [.command]
        closeWindowItem.target = nil
        menu.addItem(closeWindowItem)

        return menu
    }
}
