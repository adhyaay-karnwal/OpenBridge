import Foundation

// MARK: - Intermediary Payload Types

//
// These types serve as intermediaries for constructing the @JSBridgeType
// types (AssistantState, AssistantToolCallState, etc.) which only have
// init(from:) constructors accepting these structs.

struct GoAssistantState: Decodable, Sendable {
    let phase: String
    let sequence: Int
    let phaseStartedAt: Double
    let updatedAt: Double
    let reasoning: GoAssistantStreamState?
    let messaging: GoAssistantStreamState?
    let tools: [GoAssistantToolCallState]?
    let asyncToolcalls: [GoAssistantAsyncToolcallState]?
}

struct GoAssistantStreamState: Decodable, Sendable {
    let messageId: String?
    let responseId: String?
    let text: String?
    let isStreaming: Bool?
}

struct GoAssistantToolCallState: Decodable, Sendable {
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
}

struct GoAssistantAsyncToolcallState: Decodable, Sendable {
    let toolcallId: String
    let llmCallId: String?
    let toolName: String
    let summary: String?
    let environmentId: String?
    let environmentLabel: String?
    let requestedMode: String?
    let promotedToAsync: Bool?
    let resultPath: String?
    let status: String
    let createdAt: Double
    let startedAt: Double?
    let endedAt: Double?
    let error: String?
    let exitCode: Int?
}

struct GoWorkspaceState: Decodable, Sendable {
    let sandboxId: String
    let environmentId: String?
    let environmentLabel: String?
    let fileDiff: [GoFileDiff]?
}

struct GoFileDiff: Decodable, Sendable {
    let path: String
    let mode: UInt32
    let isDir: Bool
    let isUpdated: Bool
    let isDeleted: Bool
    let movedFrom: String?
    let timestamp: Date
    let size: Int64
}
