import Foundation
import OSLog

private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "LocalAgentEventAdapter")

/// Stateful adapter that converts local agent stream events into OpenBridge's
/// existing chat event types (AssistantState, SessionHistoryMessage).
///
/// The adapter maintains accumulated streaming text and active tool call state
/// to synthesize AssistantState snapshots compatible with the chat WebView.
@MainActor
final class LocalAgentEventAdapter {
    private enum ToolCallKind {
        case task
        case webBrowse
        case schedule
        case status
    }

    private struct TrackedToolCall {
        let id: String
        let name: String
        let kind: ToolCallKind
        let argumentsText: String?
        let taskPayload: TaskHistoryPayload?
        let schedulePayload: ScheduleToolPayload?
    }

    private struct TaskHistoryPayload {
        let action: String
        let taskId: String?
        let taskTitle: String?
        let todos: [SessionHistoryMessage.TodoItem]?
    }

    private struct ScheduleToolPayload {
        let action: String
        let name: String?
        let prompt: String?
    }

    private struct ToolHistoryArtifacts {
        var historyMessage: SessionHistoryMessage?
        var refreshSchedules = false
    }

    private var accumulatedText = ""
    private var reasoningSummaryText = ""
    private var isCurrentlyStreaming = false
    private var activeTools: [AssistantToolCallState] = []
    private var sequence = 1
    private var phase: String = "idle"
    private var phaseStartedAt: Double = 0
    private var hasAssistantMessageInCurrentRound = false
    private var seenMessageIDs: Set<Int64> = []
    private var streamingMessageId: String?
    private var pendingToolCalls: [TrackedToolCall] = []
    private var pendingToolCallsByID: [String: TrackedToolCall] = [:]
    private var toolCallSummariesByID: [String: String] = [:]
    private var explicitToolLifecycleCallIDs: Set<String> = []
    private let decoder = JSONDecoder()

    // MARK: - Public

    struct AdapterOutput {
        var historyMessages: [SessionHistoryMessage] = []
        var assistantState: AssistantState?
        var sessionStarted: Bool = false
        var sessionFinished: (state: String, error: String?)?
        var titleChanged: String?
        var refreshSchedules: Bool = false
    }

    /// Process a raw SSE event and return any openbridge events it produces.
    func process(eventType: String, data: String) -> AdapterOutput {
        var output = AdapterOutput()

        // Parse the JSON data into an LocalAgentStreamEvent.
        guard let jsonData = data.data(using: .utf8) else { return output }

        if processStreamOnlyEvent(eventType: eventType, jsonData: jsonData, output: &output) {
            return output
        }

        switch eventType {
        case "message":
            processMessagePayload(jsonData, output: &output)
        case "tool_result":
            processStoredToolResult(jsonData, output: &output)
        case "title":
            processTitleEvent(jsonData, output: &output)
        case "error":
            processErrorEvent(jsonData)
        default:
            break
        }

        return output
    }

    func process(storedMessage: LocalAgentStoredMessage) -> AdapterOutput {
        var output = AdapterOutput()
        handleStoredMessage(storedMessage, output: &output)
        return output
    }

    private func processStreamEvent(
        _ jsonData: Data,
        output: inout AdapterOutput,
        handler: (LocalAgentStreamEvent, inout AdapterOutput) -> Void
    ) {
        guard let event = decodeStreamEvent(jsonData) else { return }
        handler(event, &output)
    }

    private func processStreamOnlyEvent(
        eventType: String,
        jsonData: Data,
        output: inout AdapterOutput
    ) -> Bool {
        switch eventType {
        case "delta":
            processStreamEvent(jsonData, output: &output, handler: handleDelta)
            return true
        case "reasoning_summary":
            processStreamEvent(jsonData, output: &output, handler: handleReasoningSummary)
            return true
        case "tool_start":
            processStreamEvent(jsonData, output: &output, handler: handleToolStart)
            return true
        case "tool_end":
            processStreamEvent(jsonData, output: &output, handler: handleToolEnd)
            return true
        case "status":
            processStreamEvent(jsonData, output: &output, handler: handleStatus)
            return true
        default:
            return false
        }
    }

    private func processMessagePayload(_ jsonData: Data, output: inout AdapterOutput) {
        // Live stream messages have a "type" field; persisted catch-up
        // messages don't.
        if let event = decodeStreamEvent(jsonData) {
            handleMessage(event, output: &output)
            return
        }
        if let stored = decodeStoredMessage(jsonData) {
            handleStoredMessage(stored, output: &output)
        }
    }

    private func processStoredToolResult(_ jsonData: Data, output: inout AdapterOutput) {
        // Catch-up only (persisted tool messages).
        guard let stored = decodeStoredMessage(jsonData) else { return }
        handleStoredMessage(stored, output: &output)
    }

    private func processTitleEvent(_ jsonData: Data, output: inout AdapterOutput) {
        output.titleChanged = decodeStreamEvent(jsonData)?.content
    }

    private func processErrorEvent(_ jsonData: Data) {
        // Non-terminal round error — the agent may retry or continue.
        // Surface the error as an assistant state update but don't end the session.
        guard let event = decodeStreamEvent(jsonData) else { return }
        logger.warning("Agent round error: \(event.error ?? "unknown")")
        // Don't call sessionFinished — only status events with "failed" are terminal.
    }

    private func decodeStreamEvent(_ jsonData: Data) -> LocalAgentStreamEvent? {
        try? decoder.decode(LocalAgentStreamEvent.self, from: jsonData)
    }

    private func decodeStoredMessage(_ jsonData: Data) -> LocalAgentStoredMessage? {
        try? decoder.decode(LocalAgentStoredMessage.self, from: jsonData)
    }

    /// Transition to thinking immediately after the user sends a message so the
    /// UI has a visible state before the first SSE event arrives.
    func beginRound() -> AdapterOutput {
        var output = AdapterOutput()
        let now = Date().timeIntervalSince1970
        reset()
        enterPhase("thinking", at: now)
        output.assistantState = buildAssistantState(updatedAt: now)
        return output
    }

    /// Clear an optimistic thinking state when the send request fails before
    /// the server emits any round events.
    func cancelRound() -> AdapterOutput {
        var output = AdapterOutput()
        guard phase != "idle" else { return output }
        let now = Date().timeIntervalSince1970
        enterPhase("idle", at: now)
        output.assistantState = buildAssistantState(updatedAt: now)
        reset()
        return output
    }

    /// Reset adapter state for a new turn.
    func reset() {
        resetPhaseState()
        pendingToolCalls = []
        pendingToolCallsByID = [:]
        toolCallSummariesByID = [:]
        explicitToolLifecycleCallIDs = []
        phase = "idle"
    }

    // MARK: - Event Handlers

    private func handleDelta(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let content = event.content else { return }
        let now = Date().timeIntervalSince1970

        // beginRound() moves the adapter to "thinking" before SSE arrives, so
        // the first live delta/tool event of a turn must also count as start.
        if phase == "idle" || phase == "thinking" {
            output.sessionStarted = true
        }
        enterPhase("messaging", at: now)

        // Capture or generate a stable message ID for the streaming turn so
        // the web frontend can create a synthetic message placeholder.
        if streamingMessageId == nil {
            if let mid = event.messageId {
                streamingMessageId = "agent-\(mid)"
            } else {
                streamingMessageId = "streaming-\(UUID().uuidString)"
            }
        }

        accumulatedText += content
        isCurrentlyStreaming = true
        output.assistantState = buildAssistantState(updatedAt: now)
    }

    private func handleReasoningSummary(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let content = event.content,
              !content.isEmpty
        else { return }
        let now = Date().timeIntervalSince1970

        if phase == "idle" || phase == "thinking" {
            output.sessionStarted = true
            enterPhase("thinking", at: now)
            reasoningSummaryText += content
            output.assistantState = buildAssistantState(updatedAt: now)
        }
    }

    private func handleToolStart(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let callId = event.callId, let toolName = event.toolName else { return }
        let now = Date().timeIntervalSince1970

        // beginRound() moves the adapter to "thinking" before SSE arrives, so
        // the first live delta/tool event of a turn must also count as start.
        if phase == "idle" || phase == "thinking" {
            output.sessionStarted = true
        }
        enterPhase("execution", at: now)
        let toolState = AssistantToolCallState(
            callId: callId,
            toolName: toolName,
            summary: event.arguments.map { toolCallSummary(name: toolName, arguments: $0) } ?? toolCallSummariesByID[callId],
            args: event.arguments,
            startedAt: now
        )
        activeTools.append(toolState)
        if shouldShowGenericToolStatus(callId: callId, toolName: toolName) {
            explicitToolLifecycleCallIDs.insert(callId)
            output.historyMessages.append(makeToolStatusHistoryMessage(
                trackedToolCall: TrackedToolCall(
                    id: callId,
                    name: toolName,
                    kind: .status,
                    argumentsText: event.arguments ?? pendingToolCallsByID[callId]?.argumentsText,
                    taskPayload: nil,
                    schedulePayload: nil
                ),
                timestamp: now,
                status: "running",
                messageId: event.messageId.map(String.init)
            ))
        }
        output.assistantState = buildAssistantState(updatedAt: now)
    }

    private func handleToolEnd(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let callId = event.callId else { return }
        let now = Date().timeIntervalSince1970

        if let index = activeTools.firstIndex(where: { $0.callId == callId }) {
            activeTools[index] = AssistantToolCallState(
                callId: callId,
                toolName: activeTools[index].toolName,
                summary: activeTools[index].summary,
                args: activeTools[index].args,
                startedAt: activeTools[index].startedAt,
                endedAt: now,
                success: event.error == nil,
                error: event.error
            )
        }
        if let trackedToolCall = trackedToolCallForStatusUpdate(callId: callId) {
            explicitToolLifecycleCallIDs.insert(callId)
            output.historyMessages.append(makeToolStatusHistoryMessage(
                trackedToolCall: trackedToolCall,
                timestamp: now,
                status: event.error == nil ? "completed" : "failed",
                messageId: event.messageId.map(String.init)
            ))
        }
        output.assistantState = buildAssistantState(updatedAt: now)
    }

    private func handleMessage(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let messageId = event.messageId else { return }
        let timestamp = Date().timeIntervalSince1970

        // Deduplicate.
        guard !seenMessageIDs.contains(messageId) else { return }
        seenMessageIDs.insert(messageId)

        let role = event.role ?? "assistant"

        if role == "tool" {
            guard let trackedToolCall = resolveTrackedToolCall(explicitID: event.toolUseId ?? event.callId) else { return }
            let artifacts = makeHistoryArtifactsForToolResult(
                messageId: messageId,
                timestamp: timestamp,
                content: event.content,
                trackedToolCall: trackedToolCall
            )
            if let historyMessage = artifacts.historyMessage {
                output.historyMessages.append(historyMessage)
            }
            output.refreshSchedules = output.refreshSchedules || artifacts.refreshSchedules
            return
        }

        let trackedToolCalls = role == "assistant" ? registerToolCalls(from: event.content) : []

        let historyMessage = makeHistoryMessage(
            id: "agent-\(messageId)",
            type: "message",
            role: role,
            content: event.content,
            messageId: String(messageId)
        )
        output.historyMessages.append(historyMessage)

        if role == "assistant" {
            for trackedToolCall in trackedToolCalls where shouldEmitMessageDerivedToolStatus(trackedToolCall) {
                output.historyMessages.append(makeToolStatusHistoryMessage(
                    trackedToolCall: trackedToolCall,
                    timestamp: timestamp,
                    status: "running",
                    messageId: String(messageId)
                ))
            }
        }

        // If this is an assistant message, reset streaming state and emit an
        // updated assistantState so the web frontend removes the synthetic
        // streaming message now that the final history message is available.
        if role == "assistant" {
            hasAssistantMessageInCurrentRound = true
            accumulatedText = ""
            isCurrentlyStreaming = false
            streamingMessageId = nil
            output.assistantState = buildAssistantState(updatedAt: timestamp)
        }
    }

    private func handleStoredMessage(_ stored: LocalAgentStoredMessage, output: inout AdapterOutput) {
        guard !seenMessageIDs.contains(stored.messageId) else { return }
        seenMessageIDs.insert(stored.messageId)

        if stored.role == "tool" {
            guard let trackedToolCall = resolveTrackedToolCall(explicitID: stored.toolUseId) else { return }
            let artifacts = makeHistoryArtifactsForToolResult(
                messageId: stored.messageId,
                timestamp: Double(stored.createdAt),
                content: stored.content,
                trackedToolCall: trackedToolCall
            )
            if let historyMessage = artifacts.historyMessage {
                output.historyMessages.append(historyMessage)
            }
            output.refreshSchedules = output.refreshSchedules || artifacts.refreshSchedules
            return
        }

        let trackedToolCalls = stored.role == "assistant" ? registerToolCalls(from: stored.content) : []

        let historyMessage = makeHistoryMessage(
            id: "agent-\(stored.messageId)",
            type: "message",
            role: stored.role,
            content: stored.content,
            messageId: String(stored.messageId)
        )
        output.historyMessages.append(historyMessage)

        if stored.role == "assistant" {
            for trackedToolCall in trackedToolCalls where shouldEmitMessageDerivedToolStatus(trackedToolCall) {
                output.historyMessages.append(makeToolStatusHistoryMessage(
                    trackedToolCall: trackedToolCall,
                    timestamp: Double(stored.createdAt),
                    status: "running",
                    messageId: String(stored.messageId)
                ))
            }
        }

        if stored.role == "assistant" {
            hasAssistantMessageInCurrentRound = true
            accumulatedText = ""
            isCurrentlyStreaming = false
            streamingMessageId = nil
            output.assistantState = buildAssistantState(updatedAt: Double(stored.createdAt))
        }
    }

    private func handleStatus(_ event: LocalAgentStreamEvent, output: inout AdapterOutput) {
        guard let status = event.status else { return }
        let shouldPreserveOptimisticThinking =
            phase == "thinking" &&
            !hasAssistantMessageInCurrentRound &&
            status != "waiting"

        switch status {
        case "paused":
            // Local agent "paused" = OpenBridge "completed" (agent finished, waiting for user input).
            finishRound(
                output: &output,
                state: "completed",
                error: nil,
                preserveOptimisticThinkingState: shouldPreserveOptimisticThinking
            )
        case "waiting":
            enterWait(output: &output)
        case "failed":
            finishRound(output: &output, state: "failed", error: event.error)
        case "cancelled":
            finishRound(output: &output, state: "cancelled", error: nil)
        case "completed":
            finishRound(
                output: &output,
                state: "completed",
                error: nil,
                preserveOptimisticThinkingState: shouldPreserveOptimisticThinking
            )
        default:
            break
        }
    }

    // MARK: - State Building

    private func buildAssistantState(updatedAt: Double = Date().timeIntervalSince1970) -> AssistantState {
        let messaging = isCurrentlyStreaming
            ? AssistantStageStreamState(
                messageId: streamingMessageId,
                responseId: nil,
                text: accumulatedText,
                isStreaming: true
            )
            : nil
        let reasoning = phase == "thinking" && !reasoningSummaryText.isEmpty
            ? AssistantStageStreamState(
                messageId: nil,
                responseId: nil,
                text: reasoningSummaryText,
                isStreaming: false
            )
            : nil

        return AssistantState(
            phase: phase,
            sequence: sequence,
            phaseStartedAt: phaseStartedAt,
            updatedAt: updatedAt,
            reasoning: reasoning,
            messaging: messaging,
            tools: activeTools,
            asyncToolcalls: []
        )
    }

    private func enterPhase(_ nextPhase: String, at now: Double) {
        guard phase != nextPhase else { return }
        sequence += 1
        phase = nextPhase
        resetPhaseState(phaseStartedAt: now)
    }

    private func finishRound(
        output: inout AdapterOutput,
        state: String,
        error: String?,
        preserveOptimisticThinkingState: Bool = false
    ) {
        let now = Date().timeIntervalSince1970
        if !preserveOptimisticThinkingState {
            enterPhase("idle", at: now)
            output.assistantState = buildAssistantState(updatedAt: now)
        }
        output.sessionFinished = (state: state, error: error)
        reset()
    }

    private func enterWait(output: inout AdapterOutput) {
        let now = Date().timeIntervalSince1970
        if phase == "idle" || phase == "thinking" {
            output.sessionStarted = true
        }
        if phase != "execution" {
            enterPhase("execution", at: now)
        }
        output.assistantState = buildAssistantState(updatedAt: now)
    }

    private func resetPhaseState(phaseStartedAt: Double = 0) {
        accumulatedText = ""
        reasoningSummaryText = ""
        isCurrentlyStreaming = false
        streamingMessageId = nil
        activeTools = []
        hasAssistantMessageInCurrentRound = false
        self.phaseStartedAt = phaseStartedAt
    }

    // MARK: - Message Building

    private func makeHistoryMessage(
        id: String,
        type: String,
        role: String,
        content: String?,
        timestamp: Double = Date().timeIntervalSince1970,
        toolUseId: String? = nil,
        messageId: String? = nil
    ) -> SessionHistoryMessage {
        var contentBlocks: [SessionHistoryMessage.Content]?
        if let raw = content, !raw.isEmpty {
            contentBlocks = parseContentBlocks(raw)
        }

        return SessionHistoryMessage(
            id: id,
            type: type,
            role: role,
            timestamp: timestamp,
            content: contentBlocks,
            messageId: messageId,
            taskId: nil,
            action: nil,
            taskTitle: nil,
            todos: nil,
            sandboxId: nil,
            acceptedSummary: nil,
            reviewDiff: nil,
            reviewDiffTotal: nil,
            confirmationId: nil,
            traceparent: nil,
            tracestate: nil,
            question: nil,
            questionReply: nil,
            saveFileRequest: nil,
            saveFileReply: nil,
            permissionRequest: nil,
            permissionReply: nil,
            secretInput: nil,
            secretInputReply: nil,
            schedule: nil,
            toolUseId: toolUseId,
            errorType: nil,
            error: nil
        )
    }

    private func makeTaskHistoryMessage(
        id: String,
        timestamp: Double,
        taskPayload: TaskHistoryPayload,
        messageId: String? = nil
    ) -> SessionHistoryMessage {
        SessionHistoryMessage(
            id: id,
            type: "task",
            role: nil,
            timestamp: timestamp,
            content: nil,
            messageId: messageId,
            taskId: taskPayload.taskId,
            action: taskPayload.action,
            taskTitle: taskPayload.taskTitle,
            todos: taskPayload.todos,
            sandboxId: nil,
            acceptedSummary: nil,
            reviewDiff: nil,
            reviewDiffTotal: nil,
            confirmationId: nil,
            traceparent: nil,
            tracestate: nil,
            question: nil,
            questionReply: nil,
            saveFileRequest: nil,
            saveFileReply: nil,
            permissionRequest: nil,
            permissionReply: nil,
            secretInput: nil,
            secretInputReply: nil,
            schedule: nil,
            toolUseId: nil,
            errorType: nil,
            error: nil
        )
    }

    private func makeToolStatusHistoryMessage(
        trackedToolCall: TrackedToolCall,
        timestamp: Double,
        status: String,
        messageId: String? = nil
    ) -> SessionHistoryMessage {
        SessionHistoryMessage(
            id: "agent-tool-\(trackedToolCall.id)",
            type: "message",
            role: "tool",
            timestamp: timestamp,
            content: [makeTextContent(makeToolStatusContent(trackedToolCall: trackedToolCall, status: status))],
            messageId: messageId,
            taskId: nil,
            action: nil,
            taskTitle: nil,
            todos: nil,
            sandboxId: nil,
            acceptedSummary: nil,
            reviewDiff: nil,
            reviewDiffTotal: nil,
            confirmationId: nil,
            traceparent: nil,
            tracestate: nil,
            question: nil,
            questionReply: nil,
            saveFileRequest: nil,
            saveFileReply: nil,
            permissionRequest: nil,
            permissionReply: nil,
            secretInput: nil,
            secretInputReply: nil,
            schedule: nil,
            toolUseId: trackedToolCall.id,
            errorType: nil,
            error: nil
        )
    }

    /// Parse persisted content strings into SessionHistoryMessage.Content blocks.
    ///
    /// The local history store uses several formats:
    /// - User messages: `[{"type":"text","text":"hello"}]` (JSON array of content blocks)
    /// - Assistant messages: `{"text":"response","reasoning_content":"..."}` (JSON object)
    /// - Plain text: `"hello"` (raw string, e.g. from tool results)
    private func parseContentBlocks(_ raw: String) -> [SessionHistoryMessage.Content] {
        LocalAgentContentParser.parse(raw) ?? [makeTextContent(raw)]
    }

    private func makeTextContent(_ text: String) -> SessionHistoryMessage.Content {
        SessionHistoryMessage.Content(
            type: "text", text: text, url: nil, fileRef: nil, fileName: nil, mimeType: nil
        )
    }

    /// Assistant content looks like:
    /// `{"text":"...","tool_calls":[{"id":"call_xxx","function":{"name":"manage_task","arguments":"{...}"}}]}`
    private func registerToolCalls(from content: String?) -> [TrackedToolCall] {
        guard let raw = content,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCalls = obj["tool_calls"] as? [[String: Any]]
        else { return [] }

        var trackedToolCalls: [TrackedToolCall] = []

        for call in toolCalls {
            guard let callId = call["id"] as? String,
                  let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { continue }

            let argumentsText = function["arguments"] as? String
            let summary = toolCallSummary(name: name, arguments: argumentsText)
            toolCallSummariesByID[callId] = summary
            if let index = activeTools.firstIndex(where: { $0.callId == callId }) {
                activeTools[index] = AssistantToolCallState(
                    callId: activeTools[index].callId,
                    toolName: activeTools[index].toolName,
                    summary: summary,
                    args: activeTools[index].args,
                    startedAt: activeTools[index].startedAt,
                    endedAt: activeTools[index].endedAt,
                    success: activeTools[index].success,
                    error: activeTools[index].error
                )
            }

            let kind = toolKind(for: name)

            let taskPayload = kind == .task
                ? parseTaskHistoryPayload(arguments: argumentsText)
                : nil
            let schedulePayload = kind == .schedule
                ? parseScheduleToolPayload(arguments: argumentsText)
                : nil

            let trackedToolCall = TrackedToolCall(
                id: callId,
                name: name,
                kind: kind,
                argumentsText: argumentsText,
                taskPayload: taskPayload,
                schedulePayload: schedulePayload
            )
            trackedToolCalls.append(trackedToolCall)
            pendingToolCalls.append(trackedToolCall)
            pendingToolCallsByID[callId] = trackedToolCall
        }

        return trackedToolCalls
    }

    private func resolveTrackedToolCall(explicitID: String?) -> TrackedToolCall? {
        if let explicitID {
            guard let trackedToolCall = pendingToolCallsByID.removeValue(forKey: explicitID) else {
                logger.debug("Ignoring tool result for untracked call id \(explicitID)")
                return nil
            }
            pendingToolCalls.removeAll { $0.id == explicitID }
            return trackedToolCall
        }

        while !pendingToolCalls.isEmpty {
            let trackedToolCall = pendingToolCalls.removeFirst()
            if pendingToolCallsByID.removeValue(forKey: trackedToolCall.id) != nil {
                if trackedToolCall.kind == .status {
                    continue
                }
                return trackedToolCall
            }
        }

        return nil
    }

    private func makeHistoryArtifactsForToolResult(
        messageId: Int64,
        timestamp: Double,
        content: String?,
        trackedToolCall: TrackedToolCall
    ) -> ToolHistoryArtifacts {
        switch trackedToolCall.name {
        case "WebBrowse":
            return ToolHistoryArtifacts(historyMessage: makeHistoryMessage(
                id: "agent-\(messageId)",
                type: "message",
                role: "tool",
                content: content,
                timestamp: timestamp,
                toolUseId: trackedToolCall.id,
                messageId: String(messageId)
            ))
        case "manage_task":
            guard !toolResultContainsError(content),
                  var taskPayload = trackedToolCall.taskPayload
            else { return ToolHistoryArtifacts() }

            if taskPayload.action == "start" {
                taskPayload = TaskHistoryPayload(
                    action: taskPayload.action,
                    taskId: extractStartedTaskID(from: content),
                    taskTitle: taskPayload.taskTitle,
                    todos: taskPayload.todos
                )
            }

            guard let taskId = taskPayload.taskId, !taskId.isEmpty else { return ToolHistoryArtifacts() }

            return ToolHistoryArtifacts(historyMessage: makeTaskHistoryMessage(
                id: "agent-task-\(messageId)",
                timestamp: timestamp,
                taskPayload: TaskHistoryPayload(
                    action: taskPayload.action,
                    taskId: taskId,
                    taskTitle: taskPayload.taskTitle,
                    todos: taskPayload.todos
                ),
                messageId: String(messageId)
            ))
        case "manage_schedule":
            return makeScheduleHistoryArtifacts(
                messageId: messageId,
                timestamp: timestamp,
                content: content,
                trackedToolCall: trackedToolCall
            )
        default:
            return ToolHistoryArtifacts(historyMessage: makeToolStatusHistoryMessage(
                trackedToolCall: trackedToolCall,
                timestamp: timestamp,
                status: toolResultContainsError(content) ? "failed" : "completed",
                messageId: String(messageId)
            ))
        }
    }

    private func parseTaskHistoryPayload(arguments: String?) -> TaskHistoryPayload? {
        guard let arguments,
              let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String
        else { return nil }

        let mappedAction: String
        switch action {
        case "start", "update", "cancel":
            mappedAction = action
        case "complete":
            mappedAction = "end"
        default:
            return nil
        }

        return TaskHistoryPayload(
            action: mappedAction,
            taskId: obj["task_id"] as? String,
            taskTitle: obj["title"] as? String,
            todos: parseTodos(raw: obj["todos"])
        )
    }

    private func parseScheduleToolPayload(arguments: String?) -> ScheduleToolPayload? {
        guard let arguments,
              let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String
        else { return nil }

        return ScheduleToolPayload(
            action: action,
            name: obj["name"] as? String,
            prompt: obj["prompt"] as? String
        )
    }

    private func parseTodos(raw: Any?) -> [SessionHistoryMessage.TodoItem]? {
        guard let rawTodos = raw as? [[String: Any]] else { return nil }
        return rawTodos.compactMap { rawTodo in
            guard let content = rawTodo["content"] as? String,
                  let status = rawTodo["status"] as? String
            else { return nil }
            return SessionHistoryMessage.TodoItem(content: content, status: status)
        }
    }

    private func toolResultContainsError(_ content: String?) -> Bool {
        guard let content,
              let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["error"] is String
    }

    private func makeScheduleHistoryArtifacts(
        messageId: Int64,
        timestamp: Double,
        content: String?,
        trackedToolCall: TrackedToolCall
    ) -> ToolHistoryArtifacts {
        guard let schedulePayload = trackedToolCall.schedulePayload else {
            return ToolHistoryArtifacts()
        }

        let mutatingActions = Set(["create", "update", "pause", "resume", "delete"])
        let shouldRefresh = !toolResultContainsError(content) && mutatingActions.contains(schedulePayload.action)
        guard schedulePayload.action == "create", !toolResultContainsError(content) else {
            return ToolHistoryArtifacts(refreshSchedules: shouldRefresh)
        }

        let scheduleResult = parseScheduleResult(content)
        let title = scheduleCardTitle(result: scheduleResult, payload: schedulePayload)
        let subtitle = scheduleCardSubtitle(result: scheduleResult)

        let historyMessage = SessionHistoryMessage(
            id: "agent-schedule-\(messageId)",
            type: "schedule",
            role: nil,
            timestamp: timestamp,
            content: nil,
            messageId: String(messageId),
            taskId: nil,
            action: nil,
            taskTitle: nil,
            todos: nil,
            sandboxId: nil,
            acceptedSummary: nil,
            reviewDiff: nil,
            reviewDiffTotal: nil,
            confirmationId: nil,
            traceparent: nil,
            tracestate: nil,
            question: nil,
            questionReply: nil,
            saveFileRequest: nil,
            saveFileReply: nil,
            permissionRequest: nil,
            permissionReply: nil,
            secretInput: nil,
            secretInputReply: nil,
            schedule: SessionHistoryMessage.ScheduleReference(
                scheduleId: scheduleResult?.scheduleID ?? "",
                title: title,
                subtitle: subtitle,
                isPaused: scheduleResult?.isPaused ?? false,
                hasError: false
            ),
            toolUseId: trackedToolCall.id,
            errorType: nil,
            error: nil
        )
        return ToolHistoryArtifacts(historyMessage: historyMessage, refreshSchedules: shouldRefresh)
    }

    private struct ParsedScheduleResult {
        let scheduleID: String
        let name: String
        let prompt: String
        let isPaused: Bool
        let nextRunAt: Date?
    }

    private func parseScheduleResult(_ content: String?) -> ParsedScheduleResult? {
        guard let content,
              let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let scheduleID = (obj["schedule_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if scheduleID.isEmpty {
            return nil
        }
        let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prompt = (obj["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = (obj["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextRunAt = (obj["next_run_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return ParsedScheduleResult(
            scheduleID: scheduleID,
            name: name,
            prompt: prompt,
            isPaused: status == "paused",
            nextRunAt: nextRunAt
        )
    }

    private func scheduleCardTitle(result: ParsedScheduleResult?, payload: ScheduleToolPayload) -> String {
        let explicitName = result?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitName.isEmpty {
            return explicitName
        }
        let prompt = result?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? payload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let firstLine = prompt.split(whereSeparator: \.isNewline).first, !firstLine.isEmpty {
            return String(firstLine)
        }
        return String(localized: "Scheduled task")
    }

    private func scheduleCardSubtitle(result: ParsedScheduleResult?) -> String {
        guard let result else {
            return String(localized: "Scheduled")
        }
        if result.isPaused {
            return String(localized: "Paused")
        }
        if let nextRunAt = result.nextRunAt {
            return String(localized: "Next run ") + scheduleTimestampText(nextRunAt)
        }
        return String(localized: "Scheduled")
    }

    private func extractStartedTaskID(from content: String?) -> String? {
        guard let content,
              let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["task_id"] as? String
    }

    private func shouldShowGenericToolStatus(callId: String, toolName: String) -> Bool {
        if let trackedToolCall = pendingToolCallsByID[callId] {
            return trackedToolCall.kind == .status
        }
        return toolKind(for: toolName) == .status
    }

    private func shouldEmitMessageDerivedToolStatus(_ trackedToolCall: TrackedToolCall) -> Bool {
        trackedToolCall.kind == .status && !explicitToolLifecycleCallIDs.contains(trackedToolCall.id)
    }

    private func trackedToolCallForStatusUpdate(callId: String) -> TrackedToolCall? {
        if let trackedToolCall = pendingToolCallsByID[callId], trackedToolCall.kind == .status {
            return trackedToolCall
        }
        guard let activeTool = activeTools.first(where: { $0.callId == callId }),
              toolKind(for: activeTool.toolName) == .status
        else { return nil }
        return TrackedToolCall(
            id: callId,
            name: activeTool.toolName,
            kind: .status,
            argumentsText: activeTool.args,
            taskPayload: nil,
            schedulePayload: nil
        )
    }

    private func toolKind(for name: String) -> ToolCallKind {
        switch name {
        case "manage_task":
            .task
        case "WebBrowse":
            .webBrowse
        case "manage_schedule":
            .schedule
        default:
            .status
        }
    }

    private func makeToolStatusContent(trackedToolCall: TrackedToolCall, status: String) -> String {
        var payload: [String: Any] = [
            "kind": "tool_call",
            "tool_name": trackedToolCall.name,
            "status": status,
            "completed": status != "running",
        ]
        if let argumentsText = trackedToolCall.argumentsText {
            payload["arguments"] = argumentsText
        }
        if let command = toolCommand(name: trackedToolCall.name, arguments: trackedToolCall.argumentsText) {
            payload["command"] = command
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return toolCallSummary(name: trackedToolCall.name, arguments: trackedToolCall.argumentsText)
        }
        return text
    }

    private func parseJSONObject(_ raw: String?) -> [String: Any]? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimmedArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(trimmedString(_:))
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }
}

private extension LocalAgentEventAdapter {
    func numericValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }

    func shorten(_ text: String, maxLength: Int = 96) -> String {
        guard text.count > maxLength else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength - 1)
        return text[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func quote(_ text: String?, fallback: String) -> String {
        "\"\(shorten(text ?? fallback, maxLength: 40))\""
    }

    func humanizeToolName(_ toolName: String) -> String {
        let withSpaces = toolName
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = withSpaces.first else { return "Tool call" }
        return first.uppercased() + String(withSpaces.dropFirst())
    }

    func environmentLocation(_ environment: String?) -> (preposition: String, label: String)? {
        guard let environment else { return nil }
        let trimmed = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if normalized == "vfs" {
            return nil
        }
        if normalized == "sandbox" || normalized.hasPrefix("sandbox-") || normalized == "local-vm" || normalized.hasPrefix("local-vm-") {
            return ("in", "a safe workspace on this Mac")
        }
        if normalized == "local" || normalized.hasPrefix("local-") {
            return ("on", "this Mac")
        }
        if normalized == "cloud-vm" {
            return ("in", "a safe workspace on this Mac")
        }

        return ("in", trimmed)
    }

    func environmentSuffix(_ environment: String?) -> String {
        guard let location = environmentLocation(environment) else { return "" }
        return " \(location.preposition) \(location.label)"
    }

    func pathLabel(_ path: String?, environment: String?) -> String {
        "\(path ?? "file")\(environmentSuffix(environment))"
    }

    func formatTimeout(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let rounded = Int(seconds.rounded())
        if rounded < 60 {
            return "\(rounded)s"
        }
        let minutes = rounded / 60
        let remain = rounded % 60
        if remain == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remain)s"
    }

    func urlLabel(_ rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        return URL(string: rawURL)?.host ?? rawURL
    }

    func shortIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        return String(value.prefix(12))
    }

    func toolCommand(name: String, arguments: String?) -> String? {
        guard name == "Exec" else { return nil }
        return trimmedString(parseJSONObject(arguments)?["command"])
    }

    func toolCallSummary(name: String, arguments: String?) -> String {
        let args = parseJSONObject(arguments)

        if let summary = fileToolCallSummary(name: name, args: args) {
            return summary
        }
        if let summary = executionToolCallSummary(name: name, args: args) {
            return summary
        }
        if let summary = webToolCallSummary(name: name, args: args) {
            return summary
        }
        if let summary = workflowToolCallSummary(name: name, args: args) {
            return summary
        }

        return humanizeToolName(name)
    }

    func fileToolCallSummary(name: String, args: [String: Any]?) -> String? {
        let path = trimmedString(args?["path"])
        let environment = trimmedString(args?["environment"])

        switch name {
        case "Read":
            return shorten("Read \(pathLabel(path, environment: environment))")
        case "Write":
            return shorten("Write \(pathLabel(path, environment: environment))")
        case "Edit":
            return shorten("Edit \(pathLabel(path, environment: environment))")
        case "Delete":
            let prefix = boolValue(args?["recursive"]) ? "Delete recursively " : "Delete "
            return shorten(prefix + pathLabel(path, environment: environment))
        case "Stat":
            return shorten("Inspect \(pathLabel(path, environment: environment))")
        case "List":
            let prefix = boolValue(args?["recursive"]) ? "List recursively " : "List "
            return shorten(prefix + pathLabel(path, environment: environment))
        case "Glob":
            let pattern = quote(trimmedString(args?["pattern"]), fallback: "files")
            return shorten("Find \(pattern) in \(path ?? "/")\(environmentSuffix(environment))")
        case "Grep":
            let pattern = quote(trimmedString(args?["pattern"]), fallback: "pattern")
            return shorten("Search \(path ?? "/")\(environmentSuffix(environment)) for \(pattern)")
        case "Copy":
            let source = trimmedString(args?["src_path"]) ?? "source"
            let destination = trimmedString(args?["dst_path"]) ?? "destination"
            let sourceEnvironment = trimmedString(args?["src_environment"])
            let destinationEnvironment = trimmedString(args?["dst_environment"])
            return shorten("Copy \(source)\(environmentSuffix(sourceEnvironment)) to \(destination)\(environmentSuffix(destinationEnvironment))")
        default:
            return nil
        }
    }

    func executionToolCallSummary(name: String, args: [String: Any]?) -> String? {
        switch name {
        case "JavaScript":
            return "Run JavaScript"
        case "Exec":
            let label = trimmedString(args?["description"]) ?? trimmedString(args?["command"])
            let environment = trimmedString(args?["environment"])
            return shorten("Run \(quote(label, fallback: "command"))\(environmentSuffix(environment))")
        case "RequestPermission":
            let description = trimmedString(args?["description"])
            let environment = trimmedString(args?["environment"])
            return shorten("Request permission for \(quote(description, fallback: "action"))\(environmentSuffix(environment))")
        case "wait_for":
            let duration = formatTimeout(numericValue(args?["timeout_seconds"])) ?? "a while"
            return shorten("Wait \(duration) for \(quote(trimmedString(args?["reason"]), fallback: "event"))")
        default:
            return nil
        }
    }

    func webToolCallSummary(name: String, args: [String: Any]?) -> String? {
        switch name {
        case "ExaSearch":
            return shorten("Search web for \(quote(trimmedString(args?["query"]), fallback: "query"))")
        case "ExaContents":
            let urls = trimmedArray(args?["urls"])
            if urls.isEmpty {
                return "Fetch web pages"
            }
            if urls.count == 1 {
                return shorten("Fetch \(urlLabel(urls[0]) ?? urls[0])")
            }
            return shorten("Fetch \(urls.count) web pages")
        case "WebBrowse":
            let target = urlLabel(trimmedString(args?["url"])) ?? trimmedString(args?["url"])
            let goal = trimmedString(args?["goal"])
            if let target, let goal {
                return shorten("Browse \(target) for \(quote(goal, fallback: "goal"))")
            }
            if let target {
                return shorten("Browse \(target)")
            }
            return "Browse website"
        default:
            return nil
        }
    }

    func workflowToolCallSummary(name: String, args: [String: Any]?) -> String? {
        if name == "cancel_operation" {
            return shorten("Cancel operation \(shortIdentifier(trimmedString(args?["operation_id"])) ?? "operation")")
        }
        if name == "ListEnvironments" {
            return "List environments"
        }
        if name == "manage_task" {
            return taskManagementToolCallSummary(args: args)
        }
        if name == "manage_schedule" {
            return scheduleManagementToolCallSummary(args: args)
        }
        return nil
    }

    func taskManagementToolCallSummary(args: [String: Any]?) -> String {
        let action = trimmedString(args?["action"])
        let title = trimmedString(args?["title"])
        let taskID = trimmedString(args?["task_id"])

        switch action {
        case "start":
            return shorten("Start task \(quote(title, fallback: "task"))")
        case "update":
            return shorten("Update task \(taskID ?? "task")")
        case "complete":
            return shorten("Complete task \(taskID ?? "task")")
        case "cancel":
            return shorten("Cancel task \(taskID ?? "task")")
        default:
            return "Manage task"
        }
    }

    func scheduleManagementToolCallSummary(args: [String: Any]?) -> String {
        let action = trimmedString(args?["action"]) ?? "list"
        let name = trimmedString(args?["name"])
        let scheduleID = trimmedString(args?["schedule_id"])

        switch action {
        case "create":
            return shorten("Create schedule \(quote(name, fallback: "schedule"))")
        case "list":
            return "List schedules"
        case "get":
            return shorten("Inspect schedule \(scheduleID ?? "schedule")")
        case "update":
            return shorten("Update schedule \(scheduleID ?? quote(name, fallback: "schedule"))")
        case "pause":
            return shorten("Pause schedule \(scheduleID ?? "schedule")")
        case "resume":
            return shorten("Resume schedule \(scheduleID ?? "schedule")")
        case "delete":
            return shorten("Delete schedule \(scheduleID ?? "schedule")")
        default:
            return "Manage schedule"
        }
    }
}

// MARK: - AssistantToolCallState Convenience Init

extension AssistantToolCallState {
    init(
        callId: String,
        toolName: String,
        summary: String? = nil,
        args: String? = nil,
        startedAt: Double,
        endedAt: Double? = nil,
        success: Bool? = nil,
        error: String? = nil
    ) {
        self.init(from: GoAssistantToolCallState(
            callId: callId,
            toolName: toolName,
            summary: summary,
            args: args,
            startedAt: startedAt,
            endedAt: endedAt,
            success: success,
            error: error,
            result: nil,
            status: nil,
            statusUpdatedAt: nil
        ))
    }
}

// MARK: - AssistantState Convenience Init

extension AssistantState {
    init(
        phase: String,
        sequence: Int,
        phaseStartedAt: Double,
        updatedAt: Double,
        reasoning: AssistantStageStreamState?,
        messaging: AssistantStageStreamState?,
        tools: [AssistantToolCallState],
        asyncToolcalls _: [AssistantAsyncToolcallState]
    ) {
        self.init(from: GoAssistantState(
            phase: phase,
            sequence: sequence,
            phaseStartedAt: phaseStartedAt,
            updatedAt: updatedAt,
            reasoning: reasoning.map { GoAssistantStreamState(
                messageId: $0.messageId,
                responseId: $0.responseId,
                text: $0.text,
                isStreaming: $0.isStreaming
            ) },
            messaging: messaging.map { GoAssistantStreamState(
                messageId: $0.messageId,
                responseId: $0.responseId,
                text: $0.text,
                isStreaming: $0.isStreaming
            ) },
            tools: tools.map { GoAssistantToolCallState(
                callId: $0.callId,
                toolName: $0.toolName,
                summary: $0.summary,
                args: $0.args,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                success: $0.success,
                error: $0.error,
                result: $0.result,
                status: $0.status,
                statusUpdatedAt: $0.statusUpdatedAt
            ) },
            asyncToolcalls: nil
        ))
    }
}
