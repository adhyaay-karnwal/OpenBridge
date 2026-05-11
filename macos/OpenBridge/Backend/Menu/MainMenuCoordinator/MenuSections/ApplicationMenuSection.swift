import AppKit

@MainActor
final class ApplicationMenuSection: MainMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = makeApplicationMenu()
        return [appMenuItem]
    }

    private func makeApplicationMenu() -> NSMenu {
        let processName = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: processName)

        let aboutItem = NSMenuItem(
            title: "About \(processName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(
            title: "Hide \(processName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.keyEquivalentModifierMask = [.command]
        hideItem.target = NSApp
        menu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(processName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func openSettings() {
        Windows.shared.open(.settings)
    }
}
