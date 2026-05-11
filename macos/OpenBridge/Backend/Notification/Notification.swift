import AppKit
import Combine
import Foundation
import OSLog
import UserNotifications

@MainActor
final class HeartbeatNotificationService: NSObject {
    static let shared = HeartbeatNotificationService()

    private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "HeartbeatNotificationService")
    private let notificationCenter = UNUserNotificationCenter.current()

    private var hasBooted = false
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    override private init() {
        super.init()
    }

    func boot() {
        guard !hasBooted else { return }
        hasBooted = true

        notificationCenter.delegate = self
        observeAppState()
        observeRuntime()

        Task {
            await ensureNotificationAuthorizationIfNeeded(reason: "boot")
        }
    }

    func shutdown() {
        guard hasBooted else { return }
        hasBooted = false

        appDidBecomeActiveObserver.map(NotificationCenter.default.removeObserver)
        appDidBecomeActiveObserver = nil
        cancellables.removeAll()
        if notificationCenter.delegate === self {
            notificationCenter.delegate = nil
        }
    }

    func refreshAuthorization(reason: String) async {
        await ensureNotificationAuthorizationIfNeeded(reason: reason)
    }

    private func observeAppState() {
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.ensureNotificationAuthorizationIfNeeded(reason: "app_became_active")
            }
        }
    }

    private func observeRuntime() {
        AgentSessionManager.shared.runtimeDidReset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.ensureNotificationAuthorizationIfNeeded(reason: "runtime_reset")
                }
            }
            .store(in: &cancellables)

        AgentSessionManager.shared.heartbeatResultDidReceive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.scheduleNotification(for: result)
            }
            .store(in: &cancellables)
    }

    private func ensureNotificationAuthorizationIfNeeded(reason: String) async {
        let isEnabled = await shouldEnableHeartbeatNotifications()
        if !isEnabled {
            clearHeartbeatNotifications()
        }
        logger.info("Heartbeat notification authorization refresh reason=\(reason, privacy: .public) enabled=\(isEnabled)")
    }

    private func shouldEnableHeartbeatNotifications() async -> Bool {
        guard SettingsManager.shared.showHeartbeatNotifications else {
            return false
        }

        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleNotification(for result: HeartbeatRunResult) {
        guard SettingsManager.shared.showHeartbeatNotifications else { return }

        let sessionID = result.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { return }

        let resolvedTitle = title.isEmpty ? summary : title
        let resolvedBody = summary.isEmpty ? title : summary
        guard !resolvedTitle.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = resolvedTitle
        if !resolvedBody.isEmpty, resolvedBody != resolvedTitle {
            content.body = resolvedBody
        }
        content.userInfo = ["heartbeatSessionID": sessionID]
        content.threadIdentifier = "openbridge.heartbeat"

        let identifier = result.notificationIdentifier
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        SoundsService.play(event: .schedule)
        notificationCenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { [logger] error in
            if let error {
                logger.error("Failed to schedule heartbeat notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func clearHeartbeatNotifications() {
        let identifierPrefix = "openbridge.heartbeat."
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            guard !identifiers.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }

        notificationCenter.getDeliveredNotifications { [weak self] notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            guard !identifiers.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
        }
    }

    private func openHeartbeatSession(_ sessionID: String) async {
        do {
            try await AgentSessionManager.shared.setSessionHidden(sessionId: sessionID, hidden: false)
        } catch {
            logger.error("Failed to reveal heartbeat session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        ContinueInChatManager.shared.openConversation(sessionID)
    }
}

extension HeartbeatNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier.hasPrefix("openbridge.heartbeat.") else {
            return []
        }
        let isEnabled = await MainActor.run { SettingsManager.shared.showHeartbeatNotifications }
        guard isEnabled else {
            return []
        }
        return [.banner]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        let sessionID = request.content.userInfo["heartbeatSessionID"] as? String
        guard let sessionID, !sessionID.isEmpty else { return }
        await openHeartbeatSession(sessionID)
    }
}
