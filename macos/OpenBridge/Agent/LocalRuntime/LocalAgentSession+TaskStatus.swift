import Foundation

extension LocalAgentSession {
    func makeTaskHistoryMessageFromManageTaskResult(
        _ resultText: String,
        fallbackToolCallId: String,
        fallbackArgs: String?
    ) -> SessionHistoryMessage? {
        let result = Self.parseTaskObject(resultText)
        let args = Self.parseTaskObject(fallbackArgs)

        let action = Self.taskAction(from: result["action"] ?? args["action"])
        guard let action else { return nil }

        let taskID = Self.trimmedTaskString(result["task_id"] ?? args["task_id"]) ?? fallbackToolCallId
        let title = Self.trimmedTaskString(result["title"] ?? args["title"])
        let todos = Self.taskTodos(from: result["todos"] ?? args["todos"])

        return SessionHistoryMessage(
            id: "local-task-\(taskID)-\(action)-\(UUID().uuidString)",
            type: "task",
            role: nil,
            timestamp: Date().timeIntervalSince1970,
            content: nil,
            messageId: nil,
            taskId: taskID,
            action: action,
            taskTitle: title,
            todos: todos,
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
            toolUseId: fallbackToolCallId,
            errorType: nil,
            error: nil
        )
    }

    private static func parseTaskObject(_ raw: String?) -> [String: Any] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func taskAction(from raw: Any?) -> String? {
        let action = trimmedTaskString(raw)?.lowercased()
        switch action {
        case "start", "update", "cancel":
            return action
        case "complete", "end":
            return "end"
        default:
            return nil
        }
    }

    private static func taskTodos(from raw: Any?) -> [SessionHistoryMessage.TodoItem]? {
        guard let rawTodos = raw as? [Any] else { return nil }
        let todos = rawTodos.compactMap { rawTodo -> SessionHistoryMessage.TodoItem? in
            guard let object = rawTodo as? [String: Any],
                  let content = trimmedTaskString(object["content"]),
                  let status = trimmedTaskString(object["status"])
            else { return nil }
            return SessionHistoryMessage.TodoItem(content: content, status: status)
        }
        return todos.isEmpty ? nil : todos
    }

    private static func trimmedTaskString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
