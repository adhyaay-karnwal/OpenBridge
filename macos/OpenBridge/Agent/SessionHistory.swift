//
//  SessionHistory.swift
//  OpenBridge
//
//  History message types shared across the app and the chat WebView.
//

import Foundation
import JSBridge
import OSLog

private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "SessionHistory")

/// Shared decoder for history messages.
private let historyMessageDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

// MARK: - History Message Types

@JSBridgeType
struct SessionHistoryMessage: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let role: String?
    let timestamp: Double
    let content: [Content]?
    let messageId: String?

    // Task fields
    let taskId: String?
    let action: String?
    let taskTitle: String?
    let todos: [TodoItem]?

    // Sandbox fields
    let sandboxId: String?
    let acceptedSummary: String?
    let reviewDiff: [FileDiff]?
    let reviewDiffTotal: Int?

    // Question fields
    let confirmationId: String?
    let traceparent: String?
    let tracestate: String?
    let question: QuestionInfo?
    let questionReply: QuestionReplyInfo?
    let saveFileRequest: SaveFileRequestInfo?
    let saveFileReply: SaveFileReplyInfo?

    // Permission fields
    let permissionRequest: PermissionRequestInfo?
    let permissionReply: PermissionReplyInfo?

    // Secret input fields
    let secretInput: SecretInputInfo?
    let secretInputReply: SecretInputReplyInfo?

    /// Schedule fields
    let schedule: ScheduleReference?

    /// Tool result fields
    let toolUseId: String?

    /// Error fields
    let errorType: String?
    let error: String?

    @JSBridgeType
    struct Content: Codable, Equatable {
        let type: String
        let text: String?
        let url: String?
        let fileRef: FileRef?
        let fileRefs: [FileRef]?
        let fileName: String?
        let mimeType: String?
        let sizeBytes: Int64?
        let entryKind: String?
        let quoteRef: QuoteReference?

        init(
            type: String,
            text: String? = nil,
            url: String? = nil,
            fileRef: FileRef? = nil,
            fileRefs: [FileRef]? = nil,
            fileName: String? = nil,
            mimeType: String? = nil,
            sizeBytes: Int64? = nil,
            entryKind: String? = nil,
            quoteRef: QuoteReference? = nil
        ) {
            self.type = type
            self.text = text
            self.url = url
            self.fileRef = fileRef
            self.fileRefs = fileRefs
            self.fileName = fileName
            self.mimeType = mimeType
            self.sizeBytes = sizeBytes
            self.entryKind = entryKind
            self.quoteRef = quoteRef
        }
    }

    @JSBridgeType
    struct QuoteReference: Codable, Equatable {
        let sourceMessageId: String
        let startOffset: Int
        let endOffset: Int
    }

    @JSBridgeType
    struct FileRef: Codable, Equatable {
        let environmentId: String?
        let path: String
    }

    @JSBridgeType
    struct TodoItem: Codable, Equatable {
        let content: String
        let status: String
    }

    @JSBridgeType
    struct QuestionInfo: Codable, Equatable {
        let question: String
        let header: String?
        let options: [QuestionOption]
        let multiSelect: Bool?
    }

    @JSBridgeType
    struct QuestionOption: Codable, Equatable {
        let label: String
        let description: String?
    }

    @JSBridgeType
    struct QuestionReplyInfo: Codable, Equatable {
        let reply: AnyCodable?
        let cancelled: Bool?
    }

    @JSBridgeType
    struct SaveFileRequestInfo: Codable, Equatable {
        let environmentId: String
        let path: String
        let fileName: String?
        let mimeType: String?
        let title: String?
        let message: String?
        let size: Int64?
    }

    @JSBridgeType
    struct SaveFileReplyInfo: Codable, Equatable {
        let approved: Bool?
        let cancelled: Bool?
        let fileName: String?
        let mimeType: String?
        let bytesWritten: Int64?
    }

    @JSBridgeType
    struct PermissionRequestInfo: Codable, Equatable {
        let environmentId: String
        let environmentLabel: String?
        let kind: String?
        let description: String
        /// When non-nil, the chat UI renders mode-selection buttons instead
        /// of a plain Allow/Deny. On approve, the reply carries `mode`.
        let computerUseStart: ComputerUseStartInfo?
    }

    @JSBridgeType
    struct ComputerUseStartInfo: Codable, Equatable {
        /// Modes the user may pick. Always ["background", "foreground"] today
        /// but transmitted explicitly so the UI doesn't hard-code the list.
        let availableModes: [String]
        /// App identifiers the agent wants to focus on (foreground mode only).
        let apps: [String]?
        /// Daemon-reported TCC state for the panes it needs. When present and
        /// any pane is `granted: false`, the chat UI warns the user; nil when
        /// the daemon couldn't be reached.
        let permissions: [ComputerUsePermissionPane]?
    }

    @JSBridgeType
    struct ComputerUsePermissionPane: Codable, Equatable {
        /// Pane identifier the daemon uses, e.g. "accessibility" or
        /// "screen_recording". UI can label these however it likes.
        let pane: String
        let granted: Bool
    }

    @JSBridgeType
    struct PermissionReplyInfo: Codable, Equatable {
        let approved: Bool
        let reason: String?
        /// Populated when the user accepted a ComputerUse start message; the
        /// string matches one of `ComputerUseStartInfo.availableModes`.
        let mode: String?
    }

    @JSBridgeType
    struct SecretInputInfo: Codable, Equatable {
        let prompt: String
        let label: String?
        let slot: String?
    }

    @JSBridgeType
    struct SecretInputReplyInfo: Codable, Equatable {
        let provided: Bool
        let cancelled: Bool?
    }

    @JSBridgeType
    struct ScheduleReference: Codable, Equatable {
        let scheduleId: String
        let title: String
        let subtitle: String?
        let isPaused: Bool?
        let hasError: Bool?
    }

    var traceContextCarrier: TraceContextCarrier? {
        guard let traceparent, !traceparent.isEmpty else { return nil }
        return TraceContextCarrier(traceparent: traceparent, tracestate: tracestate)
    }
}

// MARK: - History Event (for WebView bridge)

enum SessionHistoryEvent {
    case added(message: SessionHistoryMessage)
    case reset(messages: [SessionHistoryMessage])
    case workspaceStateChanged(WorkspaceState?)
}

// MARK: - Decoder Utility

enum SessionHistoryDecoder {
    static func decodeHistoryMessages(from data: Data) throws -> [SessionHistoryMessage] {
        try historyMessageDecoder.decode([SessionHistoryMessage].self, from: data)
    }
}
