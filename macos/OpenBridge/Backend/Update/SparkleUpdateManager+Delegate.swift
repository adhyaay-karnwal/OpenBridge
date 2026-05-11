//
//  SparkleUpdateManager+Delegate.swift
//  OpenBridge
//
//  Created by qaq on 16/12/2025.
//

import AppKit
import Foundation
@preconcurrency import Sparkle

extension SparkleUpdateManager: SPUStandardUserDriverDelegate {
    func standardUserDriverDidShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows {
                guard let controller = window.windowController,
                      controller.className == "SUStatusController"
                else { continue }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension SparkleUpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with _: NSMutableURLRequest) {
        Logger.updater.info("⬇️ Starting update download...")
        Task { @MainActor in
            downloadingVersion = item.displayVersionString
            menuState = .downloadingUpdate
        }
    }

    nonisolated func updater(_: SPUUpdater, didDownloadUpdate _: SUAppcastItem) {
        Logger.updater.info("✅ Update downloaded")
        // wait until an update block is sent to use later
        // at willInstallUpdateOnQuit + immediateInstallationBlock
        // Task { @MainActor in menuState = .restartToUpdate }
    }

    nonisolated func updater(_: SPUUpdater, failedToDownloadUpdate _: SUAppcastItem, error: Error) {
        Logger.updater.error("❌ Failed to download update: \(error.localizedDescription)")
        Task { @MainActor in
            downloadingVersion = nil
            menuState = .checkForUpdate
        }
    }

    nonisolated func userDidCancelDownload(_: SPUUpdater) {
        Logger.updater.info("⏹️ User canceled update download")
        Task { @MainActor in
            downloadingVersion = nil
            menuState = .checkForUpdate
        }
    }

    nonisolated func updaterDidNotFindUpdate(_: SPUUpdater) {
        Logger.updater.info("ℹ️ No update available")
        Task { @MainActor in menuState = .checkForUpdate }
    }

    nonisolated func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.updater.info("✨ Found valid update: version=\(item.displayVersionString)")
    }

    nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping @Sendable () -> Void
    ) -> Bool {
        Task { @MainActor in
            downloadingVersion = nil
            pendingUpdateVersion = item.displayVersionString
            installationBlock = immediateInstallationBlock
            menuState = .restartToUpdate

//            别弹窗了 一堆问题
//            let alert = NSAlert()
//            alert.alertStyle = .informational
//            alert.messageText = String(localized: "Update Ready")
//            alert.informativeText = String(localized: "An update has been downloaded. Restart OpenBridge to install it.")
//            alert.addButton(withTitle: String(localized: "Restart"))
//            alert.addButton(withTitle: String(localized: "Later"))
//
//            NSApp.activate(ignoringOtherApps: true)
//            let response = alert.runModal()
//            if response == .alertFirstButtonReturn {
//                self.installUpdate()
//            }
        }
        return true
    }

    nonisolated func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor _: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            Logger.updater.error(error.localizedDescription)
        }
    }

    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        Logger.updater.error("❌ Update aborted: \(error.localizedDescription)")
        Task { @MainActor in menuState = .checkForUpdate }
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        true
    }
}
