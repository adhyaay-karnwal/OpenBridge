import Foundation

// MARK: - API Response Types

struct LocalAgentSessionInfo: Decodable {
    let sessionId: String
    let agentId: String
    let name: String
    let purpose: String?
    let status: String
    let activityStatus: String?
    let lastRoundError: String?
    let createdAt: Int64
    let lastActivityAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentId = "agent_id"
        case name
        case purpose
        case status
        case activityStatus = "activity_status"
        case lastRoundError = "last_round_error"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
    }
}

enum AgentSessionVisibility {
    static let hiddenConversationListPurposes = [
        "heartbeat_followup",
        "bridge",
        "slack_bridge",
    ]

    static func isVisibleInConversationList(purpose: String?) -> Bool {
        let normalizedPurpose = purpose?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !hiddenConversationListPurposes.contains {
            $0.caseInsensitiveCompare(normalizedPurpose ?? "") == .orderedSame
        }
    }
}

struct LocalAgentCreateAgentResponse: Decodable {
    let agentId: String
    let defaultSessionId: String

    private enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case defaultSessionId = "default_session_id"
    }
}

struct LocalAgentSendMessageResponse: Decodable {
    let messageId: String

    private enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

/// A persisted message from the local agent history store.
struct LocalAgentStoredMessage: Decodable {
    let messageId: Int64
    let role: String
    let content: String
    let toolUseId: String?
    let sessionId: String?
    let model: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let createdAt: Int64

    private enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case role
        case content
        case toolUseId = "tool_use_id"
        case sessionId = "session_id"
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case createdAt = "created_at"
    }
}

struct LocalAgentMessageSearchResult: Decodable {
    let messageId: Int64
    let role: String
    let sessionId: String?
    let createdAt: Int64
    let snippet: String
    let score: Double

    private enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case role
        case sessionId = "session_id"
        case createdAt = "created_at"
        case snippet
        case score
    }
}

struct LocalAgentSchedule: Decodable {
    let scheduleId: String
    let agentId: String
    let name: String
    let prompt: String
    let cronExpr: String
    let timezone: String
    let templateId: String?
    let reasoningEffort: String?
    let status: String
    let nextRunAt: Int64
    let lastRunAt: Int64?
    let createdAt: Int64
    let updatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case scheduleId = "schedule_id"
        case agentId = "agent_id"
        case name
        case prompt
        case cronExpr = "cron_expr"
        case timezone
        case templateId = "template_id"
        case reasoningEffort = "reasoning_effort"
        case status
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LocalAgentScheduleRun: Decodable {
    let runId: String
    let scheduleId: String
    let scheduledFor: Int64
    let status: String
    let sessionId: String?
    let error: String?
    let createdAt: Int64
    let updatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case scheduleId = "schedule_id"
        case scheduledFor = "scheduled_for"
        case status
        case sessionId = "session_id"
        case error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LocalAgentHeartbeat: Decodable {
    let agentId: String
    let scheduleId: String
    let prompt: String
    let cronExpr: String
    let timezone: String
    let templateId: String?
    let reasoningEffort: String?
    let status: String
    let nextRunAt: Int64
    let lastRunAt: Int64?
    let lastResult: String?
    let lastTitle: String?
    let lastSummary: String?
    let lastError: String?
    let lastSessionId: String?
    let lastSurfaceSessionId: String?
    let createdAt: Int64
    let updatedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case scheduleId = "schedule_id"
        case prompt
        case cronExpr = "cron_expr"
        case timezone
        case templateId = "template_id"
        case reasoningEffort = "reasoning_effort"
        case status
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastResult = "last_result"
        case lastTitle = "last_title"
        case lastSummary = "last_summary"
        case lastError = "last_error"
        case lastSessionId = "last_session_id"
        case lastSurfaceSessionId = "last_surface_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LocalAgentHeartbeatDispatch: Decodable {
    let status: String
    let sessionId: String?
    let existingSessionId: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "session_id"
        case existingSessionId = "existing_session_id"
    }
}

// MARK: - SSE Stream Event

/// Represents a single local agent stream event.
struct LocalAgentStreamEvent: Decodable {
    let type: String?
    let content: String?
    let messageId: Int64?
    let role: String?
    let callId: String?
    let toolName: String?
    let arguments: String?
    let toolUseId: String?
    let elapsedMs: Int64?
    let error: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case messageId = "message_id"
        case role
        case callId = "call_id"
        case toolName = "tool_name"
        case arguments
        case toolUseId = "tool_use_id"
        case elapsedMs = "elapsed_ms"
        case error
        case status
    }
}
