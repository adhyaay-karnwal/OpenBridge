import Foundation
import KWWKAgent
import KWWKAI

func makeManageTaskTool() -> AgentTool {
    AgentTool(
        name: "manage_task",
        label: "Manage Task",
        description: """
        Create and update the visible task checklist for the current user request. \
        Use this for multi-step work so OpenBridge can show progress in the notch and chat todo list. \
        Keep todo items concise and mark exactly one active item as in_progress when work is underway.
        """,
        parameters: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["start", "update", "complete", "cancel"],
                ],
                "task_id": ["type": "string"],
                "title": ["type": "string"],
                "todos": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "content": ["type": "string"],
                            "status": [
                                "type": "string",
                                "enum": ["not_started", "in_progress", "completed"],
                            ],
                        ],
                        "required": ["content", "status"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["action"],
            "additionalProperties": false,
        ],
        execute: { toolCallId, args, _, _ in
            try await MainActor.run {
                try executeManageTask(toolCallId: toolCallId, args: args)
            }
        }
    )
}

private func executeManageTask(toolCallId: String, args: KWWKAI.JSONValue) throws -> AgentToolResult {
    let object = args.objectValue ?? [:]
    let action = trimmedTaskString(object["action"])?.lowercased() ?? ""

    let mappedAction: String
    switch action {
    case "start", "update", "cancel":
        mappedAction = action
    case "complete":
        mappedAction = "end"
    default:
        throw RuntimeError(localized: "Unsupported task action: \(action)")
    }

    let taskID = trimmedTaskString(object["task_id"]) ?? toolCallId
    var payload: [String: Any] = [
        "action": mappedAction,
        "task_id": taskID,
        "status": taskStatus(for: mappedAction),
    ]
    if let title = trimmedTaskString(object["title"]) {
        payload["title"] = title
    }
    let todos = taskTodos(object["todos"])
    if !todos.isEmpty {
        payload["todos"] = todos
    }

    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return AgentToolResult(content: [.text(TextContent(text: String(data: data, encoding: .utf8) ?? "{}"))])
}

private func taskStatus(for action: String) -> String {
    switch action {
    case "end":
        "completed"
    case "cancel":
        "cancelled"
    default:
        "running"
    }
}

private func taskTodos(_ value: KWWKAI.JSONValue?) -> [[String: String]] {
    guard case let .array(items) = value else { return [] }

    return items.compactMap { item in
        guard case let .object(object) = item,
              let content = trimmedTaskString(object["content"]),
              let status = trimmedTaskString(object["status"])
        else { return nil }
        return [
            "content": content,
            "status": status,
        ]
    }
}

private func trimmedTaskString(_ value: KWWKAI.JSONValue?) -> String? {
    guard case let .string(raw) = value else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
