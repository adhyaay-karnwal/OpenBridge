//
//  SparkleUpdateManager.swift
//  OpenBridge
//
//  Manages Sparkle updates with custom UI behavior
//

import AppKit
import Combine
import Observation
@preconcurrency import Sparkle

@MainActor
final class SparkleUpdateManager: NSObject, ObservableObject {
    static let shared = SparkleUpdateManager()

    @Published var menuState: MenuState = .checkForUpdate {
        didSet {
            #if DEBUG
                if menuState == .restartToUpdate { assert(installationBlock != nil) }
            #endif
            syncChatUpdateNotification()
        }
    }

    @Published var updateChannelSwitchedToManually = false

    var installationBlock: (@Sendable () -> Void)?
    @Published var pendingUpdateVersion: String? {
        didSet {
            syncChatUpdateNotification()
        }
    }

    @Published var downloadingVersion: String? {
        didSet {
            syncChatUpdateNotification()
        }
    }

    var skippedInstallableUpdateIdentifier: String?
    var lastResolvedInstallableUpdateIdentifier: String?

    lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        applyAutomaticUpdatePreference(to: controller.updater)
        controller.startUpdater()
        return controller
    }()

    override private init() {
        super.init()

        Logger.updater.info(
            "Sparkle updater initialized: " +
                "autoChecks=\(updaterController.updater.automaticallyChecksForUpdates) " +
                "autoDownloads=\(updaterController.updater.automaticallyDownloadsUpdates) " +
                "feed=\(updaterController.updater.feedURL?.absoluteString ?? "(nil)")"
        )
        observeAutomaticUpdatePreference()
        syncChatUpdateNotification()

        // Avoid forcing a manual call to -[SPUUpdater checkForUpdatesInBackground].
        // By default, Sparkle calls this method automatically for you
        // on a scheduled basis (the default is once every 24 hours).
        // updaterController.updater.checkForUpdatesInBackground()
    }

    // MARK: - Public Methods

    func checkForUpdates() {
        // ohterwise check for if it is downloading, if so, do not go on
        if updaterController.updater.sessionInProgress { return }
        // user is requesting update manually in this launch session
        updateChannelSwitchedToManually = true
        updaterController.checkForUpdates(nil)
        // bring up our app to show any request later
        NSApp.activate()
        AnalyticsManager.track(.init(do: .appUpdateChecked))
    }

    func installUpdate() {
        guard let block = installationBlock else {
            assertionFailure("install update is only available when a install handler is set")
            checkForUpdates()
            return
        }
        AnalyticsManager.track(.init(do: .appUpdateInstalled))
        skippedInstallableUpdateIdentifier = nil
        menuState = .checkForUpdate
        installationBlock = nil
        pendingUpdateVersion = nil
        block() // this will replace the app with extracted one, restart should be quick
        NSApp.restart()
    }

    private func observeAutomaticUpdatePreference() {
        withObservationTracking {
            _ = SettingsManager.shared.autoUpdate
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyAutomaticUpdatePreference(to: self.updaterController.updater)
                self.observeAutomaticUpdatePreference()
            }
        }
    }

    private func applyAutomaticUpdatePreference(to updater: SPUUpdater) {
        let shouldAutomaticallyCheckForUpdates = SettingsManager.shared.autoUpdate
        updater.automaticallyChecksForUpdates = shouldAutomaticallyCheckForUpdates

        #if !DEBUG
            updater.automaticallyDownloadsUpdates = shouldAutomaticallyCheckForUpdates
        #else
            updater.automaticallyDownloadsUpdates = false
        #endif

        Logger.updater.info(
            "Applied automatic update preference: " +
                "autoChecks=\(updater.automaticallyChecksForUpdates) " +
                "autoDownloads=\(updater.automaticallyDownloadsUpdates)"
        )
    }
}
