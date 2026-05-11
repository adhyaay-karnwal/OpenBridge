import Foundation
import JSBridge
import OSLog

// MARK: - Workspace State (Session-level accumulated changes)

@JSBridgeType
struct FileDiff: Codable, Sendable, Identifiable, Equatable {
    var id: String {
        path
    }

    let path: String
    let mode: UInt32
    let isDir: Bool
    let isUpdated: Bool
    let isDeleted: Bool
    let movedFrom: String?
    let timestamp: String
    let size: Int64

    init(
        path: String,
        mode: UInt32,
        isDir: Bool,
        isUpdated: Bool,
        isDeleted: Bool,
        movedFrom: String? = nil,
        timestamp: String,
        size: Int64
    ) {
        self.path = path
        self.mode = mode
        self.isDir = isDir
        self.isUpdated = isUpdated
        self.isDeleted = isDeleted
        self.movedFrom = movedFrom
        self.timestamp = timestamp
        self.size = size
    }

    init(from diff: GoFileDiff) {
        path = diff.path
        mode = diff.mode
        isDir = diff.isDir
        isUpdated = diff.isUpdated
        isDeleted = diff.isDeleted
        movedFrom = diff.movedFrom
        timestamp = Self.formatTimestamp(diff.timestamp)
        size = diff.size
    }

    private static func formatTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

@JSBridgeType
struct WorkspaceState: Codable, Sendable, Equatable {
    let sessionId: String
    let environmentId: String
    let environmentLabel: String
    let fileDiff: [FileDiff]

    init(sessionId: String, environmentId: String, environmentLabel: String, fileDiff: [FileDiff]) {
        self.sessionId = sessionId
        self.environmentId = environmentId
        self.environmentLabel = environmentLabel
        self.fileDiff = fileDiff
    }

    init(from goState: GoWorkspaceState) {
        sessionId = goState.sandboxId
        environmentId = goState.environmentId ?? ""
        environmentLabel = goState.environmentLabel ?? ""
        fileDiff = goState.fileDiff?.map { FileDiff(from: $0) } ?? []
    }
}

@JSBridgeType
struct AssistantStageStreamState: Codable, Sendable, Equatable {
    let messageId: String?
    let responseId: String?
    let text: String
    let isStreaming: Bool

    init(messageId: String?, responseId: String?, text: String, isStreaming: Bool) {
        self.messageId = messageId
        self.responseId = responseId
        self.text = text
        self.isStreaming = isStreaming
    }

    init(from goState: GoAssistantStreamState) {
        messageId = goState.messageId
        responseId = goState.responseId
        text = goState.text ?? ""
        isStreaming = goState.isStreaming ?? false
    }
}

@JSBridgeType
struct AssistantToolCallState: Codable, Sendable, Equatable, Identifiable {
    var id: String {
        callId
    }

    let callId: String
    let toolName: String
    let summary: String?
    let args: String?
    let startedAt: Double
    let endedAt: Double?
    let success: Bool?
    let error: String?
    let result: String?
    let status: String?
    let statusUpdatedAt: Double?

    init(
        callId: String,
        toolName: String,
        summary: String?,
        args: String?,
        startedAt: Double,
        endedAt: Double?,
        success: Bool?,
        error: String?,
        result: String?,
        status: String?,
        statusUpdatedAt: Double?
    ) {
        self.callId = callId
        self.toolName = toolName
        self.summary = summary
        self.args = args
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.success = success
        self.error = error
        self.result = result
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt
    }

    init(from goState: GoAssistantToolCallState) {
        callId = goState.callId
        toolName = goState.toolName
        summary = goState.summary
        args = goState.args
        startedAt = goState.startedAt
        endedAt = goState.endedAt
        success = goState.success
        error = goState.error
        result = goState.result
        status = goState.status
        statusUpdatedAt = goState.statusUpdatedAt
    }
}

@JSBridgeType
struct AssistantState: Codable, Sendable, Equatable {
    let phase: String
    let sequence: Int
    let phaseStartedAt: Double
    let updatedAt: Double
    let reasoning: AssistantStageStreamState?
    let messaging: AssistantStageStreamState?
    let tools: [AssistantToolCallState]
    let asyncToolcalls: [AssistantAsyncToolcallState]

    init(from goState: GoAssistantState) {
        phase = goState.phase
        sequence = goState.sequence
        phaseStartedAt = goState.phaseStartedAt
        updatedAt = goState.updatedAt
        reasoning = goState.reasoning.map(AssistantStageStreamState.init(from:))
        messaging = goState.messaging.map(AssistantStageStreamState.init(from:))
        tools = goState.tools?.map(AssistantToolCallState.init(from:)) ?? []
        asyncToolcalls = goState.asyncToolcalls?.map(AssistantAsyncToolcallState.init(from:)) ?? []
    }
}

@JSBridgeType
struct AssistantAsyncToolcallState: Codable, Sendable, Equatable, Identifiable {
    var id: String {
        toolcallId
    }

    let toolcallId: String
    let llmCallId: String?
    let toolName: String
    let summary: String?
    let environmentId: String?
    let environmentLabel: String?
    let requestedMode: String?
    let promotedToAsync: Bool
    let resultPath: String?
    let status: String
    let createdAt: Double
    let startedAt: Double?
    let endedAt: Double?
    let error: String?
    let exitCode: Int?

    init(from goState: GoAssistantAsyncToolcallState) {
        toolcallId = goState.toolcallId
        llmCallId = goState.llmCallId
        toolName = goState.toolName
        summary = goState.summary
        environmentId = goState.environmentId
        environmentLabel = goState.environmentLabel
        requestedMode = goState.requestedMode
        promotedToAsync = goState.promotedToAsync ?? false
        resultPath = goState.resultPath
        status = goState.status
        createdAt = goState.createdAt
        startedAt = goState.startedAt
        endedAt = goState.endedAt
        error = goState.error
        exitCode = goState.exitCode
    }
}

// MARK: - Errors

enum AgentSessionError: LocalizedError {
    case sessionClosed
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .sessionClosed:
            String(localized: "Session is closed")
        case let .sessionNotFound(id):
            String(localized: "Session not found: \(id)")
        }
    }
}
