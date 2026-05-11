import Foundation

@MainActor
extension SparkleUpdateManager {
    func triggerUpdateAction() {
        guard installationBlock != nil else {
            Logger.updater.info("Immediate install unavailable, falling back to update check")
            checkForUpdates()
            return
        }

        installUpdate()
    }

    func dismissChatUpdateNotification() {
        guard let installableUpdateIdentifier = currentInstallableUpdateIdentifier else { return }
        skippedInstallableUpdateIdentifier = installableUpdateIdentifier
        syncChatUpdateNotification()
    }

    func presentDebugChatUpdateNotification() {
        ChatWindowNotificationController.shared.presentDebugUpdateNotification { [weak self] in
            self?.triggerUpdateAction()
        }
    }

    func syncChatUpdateNotification() {
        let installableUpdateIdentifier = currentInstallableUpdateIdentifier

        if installableUpdateIdentifier != lastResolvedInstallableUpdateIdentifier {
            lastResolvedInstallableUpdateIdentifier = installableUpdateIdentifier
            skippedInstallableUpdateIdentifier = nil
        }

        if installableUpdateIdentifier == nil {
            skippedInstallableUpdateIdentifier = nil
        }

        let isSkipped = installableUpdateIdentifier != nil &&
            skippedInstallableUpdateIdentifier == installableUpdateIdentifier

        guard installableUpdateIdentifier != nil, !isSkipped else {
            ChatWindowNotificationController.shared.dismissInstallableUpdateNotification()
            return
        }

        ChatWindowNotificationController.shared.presentInstallableUpdateNotification(
            onInstall: { [weak self] in
                self?.triggerUpdateAction()
            },
            onDismiss: { [weak self] in
                self?.dismissChatUpdateNotification()
            }
        )
    }

    private var currentInstallableUpdateIdentifier: String? {
        guard canRelaunch else { return nil }

        if let pendingUpdateVersion, !pendingUpdateVersion.isEmpty {
            return "sparkle:\(pendingUpdateVersion)"
        }

        return "sparkle:pending"
    }
}
