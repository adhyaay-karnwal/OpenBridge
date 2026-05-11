import CoreLocation
import Foundation
import OSLog

private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "LocalAgentSessionAppRequest")

extension LocalAgentSession {
    /// Inspect the latest assistant streaming text for an
    /// `<app-request type="…" />` tag. When a recognized tag is found at the
    /// start of the message, kick off the matching client-side flow (such as
    /// a CoreLocation fix) and send the result back as a `<user-reminder>`
    /// block so the agent can continue its response.
    func observeAssistantMessagingText(_ text: String) {
        guard !appRequestHandledInCurrentRound else { return }
        guard let kind = AppRequestDetector.detect(in: text) else { return }
        appRequestHandledInCurrentRound = true
        let token = appRequestToken

        switch kind {
        case .location:
            dispatchLocationRequest(token: token)
        }
    }

    /// Reset the per-round deduplication state so a new assistant turn can
    /// trigger another app request.
    func resetAppRequestRoundState() {
        appRequestHandledInCurrentRound = false
        appRequestToken += 1
    }

    /// Fallback detection for assistant messages that arrive fully-formed (no
    /// delta stream) - e.g. when the local agent delivers a cached response or
    /// model responded in a single chunk. Mirrors `observeAssistantMessagingText`
    /// so round-level dedup still applies.
    func observeAppRequestInPersistedMessage(_ message: SessionHistoryMessage) {
        guard message.type == "message", message.role == "assistant" else { return }
        guard let text = message.content?.first(where: { $0.type == "text" })?.text,
              !text.isEmpty
        else { return }
        observeAssistantMessagingText(text)
    }

    private func dispatchLocationRequest(token: Int) {
        Task { [weak self] in
            let reminderBody: String
            do {
                let fix = try await LocationService.shared.requestLocation()
                reminderBody = Self.formatLocationSuccessReminderBody(fix)
            } catch {
                reminderBody = Self.formatLocationFailureReminderBody(error)
            }

            guard let session = self, session.appRequestToken == token else { return }
            let currentSessionID = session.sessionID

            let reminder = """
            <user-reminder>
            \(reminderBody)
            </user-reminder>
            """

            let content = SessionHistoryMessage.Content(type: "text", text: reminder)

            do {
                _ = try await session.send(content: [content])
            } catch {
                logger.error("Failed to deliver location reminder to session \(currentSessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func formatLocationSuccessReminderBody(_ fix: LocationService.LocationFix) -> String {
        let accuracy = Int(fix.accuracy.rounded())
        return "Geolocation result: latitude=\(fix.latitude), longitude=\(fix.longitude), accuracy=\(accuracy)m"
    }

    private static func formatLocationFailureReminderBody(_ error: Error) -> String {
        // Stay in English for agent-facing contract: mirrors the web app's
        // `GeolocationPositionError.message`, which the skill doc quotes.
        let message = (error as? LocationService.LocationError)?.agentDescription
            ?? error.localizedDescription
        return "Geolocation request failed: \(message)"
    }
}
