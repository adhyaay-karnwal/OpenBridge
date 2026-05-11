import Foundation
import KWWKAgent
import KWWKAI

func makeManageScheduleTool() -> AgentTool {
    AgentTool(
        name: "manage_schedule",
        label: "Manage Schedule",
        description: """
        Create, list, inspect, update, pause, resume, or delete local scheduled tasks. \
        Schedules are stored on this Mac and run by OpenBridge while the app is running. \
        Use five-field cron expressions: minute hour day-of-month month day-of-week.
        """,
        parameters: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["create", "list", "inspect", "update", "pause", "resume", "delete"],
                ],
                "schedule_id": ["type": "string"],
                "name": ["type": "string"],
                "description": ["type": "string"],
                "prompt": ["type": "string"],
                "cron_expr": ["type": "string"],
                "timezone": ["type": "string"],
                "count_limit": ["type": "integer"],
                "date_time_limit": ["type": "string"],
            ],
            "required": ["action"],
            "additionalProperties": false,
        ],
        execute: { _, args, _, _ in
            try await executeManageSchedule(args: args)
        }
    )
}

@MainActor
private func executeManageSchedule(args: KWWKAI.JSONValue) async throws -> AgentToolResult {
    let object = args.objectValue ?? [:]
    let action = trimmedString(object["action"])?.lowercased() ?? ""
    let repository = ScheduleRepository.shared

    switch action {
    case "create":
        let request = try ScheduleCreateRequest(
            name: trimmedString(object["name"]) ?? "",
            description: trimmedString(object["description"]) ?? "",
            prompt: requiredString(object["prompt"], name: "prompt"),
            cronExpr: requiredString(object["cron_expr"], name: "cron_expr"),
            countLimit: intValue(object["count_limit"]),
            dateTimeLimit: dateValue(object["date_time_limit"]),
            timezone: trimmedString(object["timezone"]) ?? TimeZone.current.identifier
        )
        let schedule = try await repository.create(request)
        return try schedule.toolResult(action: "created")

    case "list":
        let schedules = try await repository.list()
        return try scheduleListToolResult(schedules)

    case "inspect":
        let scheduleID = try requiredString(object["schedule_id"], name: "schedule_id")
        let schedule = try await repository.inspect(scheduleID: scheduleID)
        return try schedule.toolResult(action: "inspected")

    case "update":
        let scheduleID = try requiredString(object["schedule_id"], name: "schedule_id")
        let request = ScheduleUpdateRequest(
            name: trimmedString(object["name"]),
            description: trimmedString(object["description"]),
            prompt: trimmedString(object["prompt"]),
            cronExpr: trimmedString(object["cron_expr"]),
            countLimit: intValue(object["count_limit"]),
            dateTimeLimit: dateValue(object["date_time_limit"]),
            timezone: trimmedString(object["timezone"]),
            clearCountLimit: boolValue(object["clear_count_limit"]) ?? false,
            clearDateTimeLimit: boolValue(object["clear_date_time_limit"]) ?? false
        )
        let schedule = try await repository.update(scheduleID: scheduleID, request: request)
        return try schedule.toolResult(action: "updated")

    case "pause", "resume", "delete":
        let scheduleID = try requiredString(object["schedule_id"], name: "schedule_id")
        switch action {
        case "pause":
            try await repository.pause(scheduleID: scheduleID)
            let schedule = try await repository.inspect(scheduleID: scheduleID)
            return try schedule.toolResult(action: action)
        case "resume":
            try await repository.resume(scheduleID: scheduleID)
            let schedule = try await repository.inspect(scheduleID: scheduleID)
            return try schedule.toolResult(action: action)
        default:
            let deleted = await (try? repository.inspect(scheduleID: scheduleID)) ?? ScheduleDefinition(
                id: scheduleID,
                name: "",
                description: "",
                prompt: "",
                cronExpr: "* * * * *",
                countLimit: 0,
                dateTimeLimit: nil,
                timezone: TimeZone.current.identifier,
                isPaused: false,
                isDeleted: true,
                willTriggerAgain: false,
                deletedAt: Date(),
                runHistory: [],
                nextRunAt: nil,
                lastError: "",
                createdAt: Date(),
                updatedAt: Date()
            )
            try await repository.delete(scheduleID: scheduleID)
            return try deleted.copyForToolDeleted().toolResult(action: action)
        }

    default:
        throw RuntimeError(localized: "Unsupported schedule action: \(action)")
    }
}

private func scheduleListToolResult(_ schedules: [ScheduleDefinition]) throws -> AgentToolResult {
    let payload = [
        "schedules": schedules.map { $0.toolPayload(action: "listed") },
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return AgentToolResult(content: [.text(TextContent(text: String(data: data, encoding: .utf8) ?? "{}"))])
}

private extension ScheduleDefinition {
    func toolResult(action: String) throws -> AgentToolResult {
        let data = try JSONSerialization.data(withJSONObject: toolPayload(action: action), options: [.sortedKeys])
        return AgentToolResult(content: [.text(TextContent(text: String(data: data, encoding: .utf8) ?? "{}"))])
    }

    func toolPayload(action: String) -> [String: Any] {
        var payload: [String: Any] = [
            "action": action,
            "schedule_id": id,
            "name": name,
            "description": description,
            "prompt": prompt,
            "cron_expr": cronExpr,
            "timezone": timezone,
            "status": isDeleted ? "deleted" : (isPaused ? "paused" : "active"),
            "will_trigger_again": willTriggerAgain,
            "last_error": lastError,
            "run_count": runHistory.count,
        ]
        if let nextRunAt {
            payload["next_run_at"] = Int64(nextRunAt.timeIntervalSince1970)
        }
        return payload
    }

    func copyForToolDeleted() -> ScheduleDefinition {
        ScheduleDefinition(
            id: id,
            name: name,
            description: description,
            prompt: prompt,
            cronExpr: cronExpr,
            countLimit: countLimit,
            dateTimeLimit: dateTimeLimit,
            timezone: timezone,
            isPaused: isPaused,
            isDeleted: true,
            willTriggerAgain: false,
            deletedAt: Date(),
            runHistory: runHistory,
            nextRunAt: nil,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

private func trimmedString(_ value: KWWKAI.JSONValue?) -> String? {
    guard case let .string(raw) = value else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func requiredString(_ value: KWWKAI.JSONValue?, name: String) throws -> String {
    guard let string = trimmedString(value) else {
        throw RuntimeError(localized: "manage_schedule requires `\(name)`")
    }
    return string
}

private func intValue(_ value: KWWKAI.JSONValue?) -> Int? {
    switch value {
    case let .int(value):
        value
    case let .double(value):
        Int(value)
    default:
        nil
    }
}

private func boolValue(_ value: KWWKAI.JSONValue?) -> Bool? {
    guard case let .bool(value) = value else { return nil }
    return value
}

private func dateValue(_ value: KWWKAI.JSONValue?) -> Date? {
    guard let string = trimmedString(value) else { return nil }
    if let timestamp = TimeInterval(string) {
        return Date(timeIntervalSince1970: timestamp)
    }
    return ISO8601DateFormatter().date(from: string)
}
