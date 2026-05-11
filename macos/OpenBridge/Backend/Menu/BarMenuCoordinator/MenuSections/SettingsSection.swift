import AppKit

@MainActor
final class SettingsSection: BarMenuCoordinator.SectionBuilder {
    private let updateManager = SparkleUpdateManager.shared

    func sectionItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        items.append(settingsItem)

        let skillSettingsItem = NSMenuItem(
            title: String(localized: "Open Skill Settings"),
            action: #selector(openSkillSettings),
            keyEquivalent: ""
        )
        skillSettingsItem.target = self
        items.append(skillSettingsItem)

        let exploreSkillsItem = NSMenuItem(
            title: String(localized: "Explore More Skills"),
            action: #selector(openSkills),
            keyEquivalent: ""
        )
        exploreSkillsItem.target = self
        items.append(exploreSkillsItem)

        if updateManager.isDownloading {
            let title = if let version = updateManager.downloadingVersion {
                String(localized: "Downloading Update (\(version))…")
            } else {
                String(localized: "Downloading Update…")
            }
            let downloadingItem = NSMenuItem(
                title: title,
                action: nil,
                keyEquivalent: ""
            )
            downloadingItem.isEnabled = false
            items.append(downloadingItem)
        } else if updateManager.canRelaunch {
            let title = if let version = updateManager.pendingUpdateVersion {
                String(localized: "Restart to Update (\(version))")
            } else {
                String(localized: "Restart to Update")
            }
            let restartItem = NSMenuItem(
                title: title,
                action: #selector(installUpdate),
                keyEquivalent: ""
            )
            restartItem.target = self
            items.append(restartItem)
        }

        let checkUpdatesItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        // Hide check updates if disabled OR if we already have a restart option OR if downloading
        checkUpdatesItem.isHidden = updateManager.canRelaunch || updateManager.isDownloading
        items.append(checkUpdatesItem)

        let quitItem = NSMenuItem(
            title: String(localized: "Quit OpenBridge"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        items.append(quitItem)

        return items
    }

    @objc func openSettings() {
        AnalyticsManager.track(.init(do: .trayMenuAction(action: "settings")))
        Windows.shared.open(.settings)
    }

    @objc func openSkillSettings() {
        AnalyticsManager.track(.init(do: .trayMenuAction(action: "skillSettings")))
        SettingsNavigation.shared.navigate(to: .mySkills)
        Windows.shared.open(.settings)
    }

    @objc func openSkills() {
        NSWorkspace.shared.open(Constant.skillsURL)
    }

    @objc func checkForUpdates() {
        AnalyticsManager.track(.init(do: .trayMenuAction(action: "checkUpdates")))
        updateManager.checkForUpdates()
    }

    @objc func installUpdate() {
        AnalyticsManager.track(.init(do: .trayMenuAction(action: "installUpdate")))
        updateManager.installUpdate()
    }

    @objc func quit() {
        AnalyticsManager.track(.init(do: .trayMenuAction(action: "quit")))
        NSApplication.shared.terminate(nil)
    }
}
