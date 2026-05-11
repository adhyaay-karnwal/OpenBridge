@testable import OpenBridge
import Testing

struct HeartbeatNotificationTests {
    @Test
    func `surface observation uses session id and run timestamp`() {
        let heartbeat = makeHeartbeat(
            lastRunAt: 1_745_000_123,
            lastSurfaceSessionId: "  session-123  "
        )

        #expect(
            heartbeat.surfaceObservation
                == HeartbeatSurfaceObservation(sessionID: "session-123", runAt: 1_745_000_123)
        )
    }

    @Test
    func `surface observation ignores heartbeats without a completed run`() {
        let heartbeat = makeHeartbeat(
            lastRunAt: nil,
            lastSurfaceSessionId: "session-123"
        )

        #expect(heartbeat.surfaceObservation == nil)
    }

    @Test
    func `notification identifier changes for each run of the same session`() {
        let first = HeartbeatRunResult(sessionID: "session-123", title: "Heartbeat", summary: "First", runAt: 100)
        let second = HeartbeatRunResult(sessionID: "session-123", title: "Heartbeat", summary: "Second", runAt: 200)

        #expect(first.notificationIdentifier == "openbridge.heartbeat.session-123.100")
        #expect(second.notificationIdentifier == "openbridge.heartbeat.session-123.200")
        #expect(first.notificationIdentifier != second.notificationIdentifier)
    }

    private func makeHeartbeat(lastRunAt: Int64?, lastSurfaceSessionId: String?) -> LocalAgentHeartbeat {
        LocalAgentHeartbeat(
            agentId: "agent-123",
            scheduleId: "schedule-123",
            prompt: "prompt",
            cronExpr: "*/30 * * * *",
            timezone: "Etc/UTC",
            templateId: nil,
            reasoningEffort: nil,
            status: "active",
            nextRunAt: 1_745_000_999,
            lastRunAt: lastRunAt,
            lastResult: "ok",
            lastTitle: "Heartbeat",
            lastSummary: "summary",
            lastError: nil,
            lastSessionId: "session-123",
            lastSurfaceSessionId: lastSurfaceSessionId,
            createdAt: 1_745_000_000,
            updatedAt: 1_745_000_123
        )
    }
}
