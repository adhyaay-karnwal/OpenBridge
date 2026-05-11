import Foundation
import KWWKAgent
import KWWKAI

func makeManageMemoryTool() -> AgentTool {
    AgentTool(
        name: "manage_memory",
        label: "Manage Memory",
        description: """
        Create, list, search, inspect, update, or delete durable local memories. \
        Store stable user preferences, recurring instructions, and long-lived facts that should help future conversations. \
        Do not store secrets, credentials, payment details, or one-off task details.
        """,
        parameters: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["create", "list", "search", "inspect", "update", "delete"],
                ],
                "memory_id": ["type": "string"],
                "content": ["type": "string"],
                "query": ["type": "string"],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
            "required": ["action"],
            "additionalProperties": false,
        ],
        execute: { _, args, _, _ in
            try await executeManageMemory(args: args)
        }
    )
}

@MainActor
private func executeManageMemory(args: KWWKAI.JSONValue) async throws -> AgentToolResult {
    let object = args.objectValue ?? [:]
    let action = trimmedMemoryString(object["action"])?.lowercased() ?? ""
    let repository = MemoryRepository.shared

    switch action {
    case "create":
        let memory = try await repository.create(MemoryCreateRequest(
            content: requiredMemoryString(object["content"], name: "content"),
            tags: memoryStringArray(object["tags"])
        ))
        return try memory.toolResult(action: "created")

    case "list":
        let memories = try await repository.list()
        return try memoryListToolResult(memories)

    case "search":
        let memories = try await repository.list(query: trimmedMemoryString(object["query"]))
        return try memoryListToolResult(memories)

    case "inspect":
        let memoryID = try requiredMemoryString(object["memory_id"], name: "memory_id")
        let memory = try await repository.inspect(memoryID: memoryID)
        return try memory.toolResult(action: "inspected")

    case "update":
        let memoryID = try requiredMemoryString(object["memory_id"], name: "memory_id")
        let memory = try await repository.update(
            memoryID: memoryID,
            request: MemoryUpdateRequest(
                content: trimmedMemoryString(object["content"]),
                tags: object["tags"] == nil ? nil : memoryStringArray(object["tags"])
            )
        )
        return try memory.toolResult(action: "updated")

    case "delete":
        let memoryID = try requiredMemoryString(object["memory_id"], name: "memory_id")
        let memory = try await repository.inspect(memoryID: memoryID)
        try await repository.delete(memoryID: memoryID)
        return try memory.copyForToolDeleted().toolResult(action: "deleted")

    default:
        throw RuntimeError(localized: "Unsupported memory action: \(action)")
    }
}

private func memoryListToolResult(_ memories: [MemoryEntry]) throws -> AgentToolResult {
    let payload = [
        "memories": memories.map { $0.toolPayload(action: "listed") },
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return AgentToolResult(content: [.text(TextContent(text: String(data: data, encoding: .utf8) ?? "{}"))])
}

private extension MemoryEntry {
    func toolResult(action: String) throws -> AgentToolResult {
        let data = try JSONSerialization.data(withJSONObject: toolPayload(action: action), options: [.sortedKeys])
        return AgentToolResult(content: [.text(TextContent(text: String(data: data, encoding: .utf8) ?? "{}"))])
    }

    func toolPayload(action: String) -> [String: Any] {
        [
            "action": action,
            "memory_id": id,
            "content": content,
            "tags": tags,
            "status": isDeleted ? "deleted" : "active",
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt),
        ]
    }

    func copyForToolDeleted() -> MemoryEntry {
        MemoryEntry(
            id: id,
            content: content,
            tags: tags,
            isDeleted: true,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

private func trimmedMemoryString(_ value: KWWKAI.JSONValue?) -> String? {
    guard case let .string(raw) = value else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func requiredMemoryString(_ value: KWWKAI.JSONValue?, name: String) throws -> String {
    guard let string = trimmedMemoryString(value) else {
        throw RuntimeError(localized: "manage_memory requires `\(name)`")
    }
    return string
}

private func memoryStringArray(_ value: KWWKAI.JSONValue?) -> [String] {
    guard case let .array(values) = value else { return [] }
    return values.compactMap(trimmedMemoryString)
}
