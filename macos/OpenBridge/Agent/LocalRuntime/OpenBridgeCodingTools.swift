import Foundation
import KWWKAgent
import KWWKAI

func makeOpenBridgeCodingTools(sessionID: String) -> [AgentTool] {
    [
        makeOpenBridgeRequestPermissionTool(sessionID: sessionID),
        makeOpenBridgeReadTool(sessionID: sessionID),
        makeOpenBridgeWriteTool(sessionID: sessionID),
        makeOpenBridgeEditTool(sessionID: sessionID),
        makeOpenBridgeBashTool(sessionID: sessionID),
        makeOpenBridgeGrepTool(sessionID: sessionID),
        makeOpenBridgeFindTool(sessionID: sessionID),
        makeOpenBridgeLSTool(sessionID: sessionID),
        makeOpenBridgeCurrentChangesTool(sessionID: sessionID),
    ]
}

private func makeOpenBridgeRequestPermissionTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "request_permission",
        label: "request_permission",
        description: """
        Request permission to perform write or execute operations on a protected environment.

        You MUST call this before using bash, write, or edit in environment="local".
        Provide a clear description of what you plan to do so the user can make an informed decision.

        Permission is temporary for the current task execution. If permission is pending and you can keep making progress in sandbox, continue there. If blocked on approval, wait and explain what you are waiting for.
        """,
        parameters: [
            "type": "object",
            "properties": [
                "environment": [
                    "type": "string",
                    "enum": ["local", "sandbox"],
                    "description": "Protected environment label. Use local for direct work on this Mac. sandbox does not require permission.",
                ],
                "description": [
                    "type": "string",
                    "description": "Clear description of the direct host work you plan to perform.",
                ],
            ],
            "required": ["environment", "description"],
            "additionalProperties": false,
        ],
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            guard let object = args.objectValue,
                  let environment = stringValue(object["environment"]),
                  !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CodingToolError.invalidArgument("request_permission: `environment` is required")
            }
            guard let description = stringValue(object["description"]),
                  !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CodingToolError.invalidArgument("request_permission: `description` is required")
            }
            let connector = try await connectorForEnvironment(environment)
            let result = try await connector.requestToolPermission(
                requestedEnvironment: environment,
                description: description,
                sessionID: sessionID
            )
            return AgentToolResult(content: [.text(TextContent(text: permissionToolText(result)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeReadTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "read",
        label: "read",
        description: "Read a text or binary file from environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: commonFileParameters(extra: [
            "offset": ["type": "number", "description": "Line number to start reading from, 1-indexed."],
            "limit": ["type": "number", "description": "Maximum number of lines to read."],
        ], required: ["path"]),
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let result = try await connector.handleToolRead(params: connectorJSON(from: args), sessionID: sessionID)
            return AgentToolResult(content: [.text(TextContent(text: readToolText(result)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeWriteTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "write",
        label: "write",
        description: "Write UTF-8 content to a file in environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: commonFileParameters(extra: [
            "content": ["type": "string"],
        ], required: ["path", "content"]),
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let result = try await connector.handleToolWrite(params: connectorJSON(from: args), sessionID: sessionID)
            return AgentToolResult(content: [.text(TextContent(text: mutationToolText(action: "Wrote", args: args, result: result)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeEditTool(sessionID: String) -> AgentTool {
    let parameters: KWWKAI.JSONValue = commonFileParameters(extra: [
        "edits": [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "oldText": ["type": "string"],
                    "newText": ["type": "string"],
                ],
                "required": ["oldText", "newText"],
            ],
        ],
    ], required: ["path", "edits"])

    return AgentTool(
        name: "edit",
        label: "edit",
        description: "Edit a file in environment=\"sandbox\" or environment=\"local\" using exact text replacements. Defaults to sandbox.",
        parameters: parameters,
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            guard let object = args.objectValue,
                  let path = stringValue(object["path"])
            else {
                throw CodingToolError.invalidArgument("edit: `path` is required")
            }
            guard case let .array(rawEdits) = object["edits"] ?? .null, !rawEdits.isEmpty else {
                throw CodingToolError.invalidArgument("edit: `edits` must contain at least one replacement")
            }

            let edits = try rawEdits.map { item -> EditDiff.Edit in
                guard let editObject = item.objectValue,
                      let oldText = stringValue(editObject["oldText"]),
                      let newText = stringValue(editObject["newText"])
                else {
                    throw CodingToolError.invalidArgument("edit: each edit must include oldText and newText")
                }
                return EditDiff.Edit(oldText: oldText, newText: newText)
            }

            let connector = try await connectorForTool(args)
            let readResult = try await connector.handleToolRead(params: connectorJSON(from: [
                "path": .string(path),
                "environment": object["environment"] ?? .null,
            ]), sessionID: sessionID)
            guard case let .object(readObject) = readResult,
                  case let .string(content) = readObject["content"] ?? .null,
                  case let .string(encoding) = readObject["encoding"] ?? .null,
                  encoding == "utf8"
            else {
                throw CodingToolError.invalidArgument("edit: file is not valid UTF-8")
            }

            let (bom, withoutBOM) = EditDiff.stripBOM(content)
            let ending = EditDiff.detectLineEnding(withoutBOM)
            let normalized = EditDiff.normalizeToLF(withoutBOM)
            let applied = try EditDiff.applyEdits(to: normalized, edits: edits, path: path)
            let final = bom + EditDiff.restoreLineEndings(applied.newContent, ending: ending)
            let result = try await connector.handleToolWrite(params: connectorJSON(from: [
                "path": .string(path),
                "content": .string(final),
                "environment": object["environment"] ?? .null,
            ]), sessionID: sessionID)

            let diff = EditDiff.generateDiff(old: applied.baseContent, new: applied.newContent)
            return AgentToolResult(
                content: [.text(TextContent(text: mutationToolText(action: "Edited", args: args, result: result)))],
                details: .object(["diff": .string(diff)])
            )
        }
    )
}

private func makeOpenBridgeBashTool(sessionID: String) -> AgentTool {
    let parameters: KWWKAI.JSONValue = [
        "type": "object",
        "properties": [
            "command": ["type": "string"],
            "description": ["type": "string"],
            "working_dir": ["type": "string"],
            "timeout": ["type": "number"],
            "environment": environmentParameter(),
        ],
        "required": ["command"],
        "additionalProperties": false,
    ]
    return AgentTool(
        name: "bash",
        label: "bash",
        description: "Execute a shell command in environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: parameters,
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let result = try await connector.handleToolExec(
                params: connectorJSON(from: args),
                sessionID: sessionID,
                callerAgentID: "openbridge-agent"
            )
            guard case let .object(object) = result else {
                throw CodingToolError.runtime("bash: invalid execution result")
            }
            let stdout = localString(object["stdout"]) ?? ""
            let stderr = localString(object["stderr"]) ?? ""
            let exitCode = localInt(object["exit_code"]) ?? 0
            if exitCode != 0 {
                throw CodingToolError.commandFailed(stderr: stderr.isEmpty ? stdout : stderr, exitCode: Int32(exitCode))
            }
            return AgentToolResult(content: [.text(TextContent(text: commandOutput(stdout: stdout, stderr: stderr)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeGrepTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "grep",
        label: "grep",
        description: "Search file contents in environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: commonSearchParameters(required: ["pattern"]),
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let result = try await connector.handleGrep(params: connectorJSON(from: args), sessionID: sessionID)
            return AgentToolResult(content: [.text(TextContent(text: grepToolText(result)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeFindTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "find",
        label: "find",
        description: "Find files by glob in environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: commonSearchParameters(required: ["pattern"]),
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let result = try await connector.handleGlob(params: connectorJSON(from: args), sessionID: sessionID)
            return AgentToolResult(content: [.text(TextContent(text: findToolText(result, args: args)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeLSTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "ls",
        label: "ls",
        description: "List a directory in environment=\"sandbox\" or environment=\"local\". Defaults to sandbox.",
        parameters: commonFileParameters(extra: [:], required: []),
        execute: { _, args, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let connector = try await connectorForTool(args)
            let params = ensurePathParameter(args)
            let result = try await connector.handleList(params: connectorJSON(from: params), sessionID: sessionID)
            return AgentToolResult(content: [.text(TextContent(text: listToolText(result)))], details: aiJSON(from: result))
        }
    )
}

private func makeOpenBridgeCurrentChangesTool(sessionID: String) -> AgentTool {
    AgentTool(
        name: "current_changes",
        label: "current_changes",
        description: """
        Get the current file changes staged in the sandbox workspace.

        Returns the files created, modified, deleted, or moved during this session. Call this after completing sandbox file operations to review what will be applied before finishing the task.
        """,
        parameters: [
            "type": "object",
            "properties": [
                "environment": [
                    "type": "string",
                    "enum": ["sandbox"],
                    "description": "Only sandbox supports workspace review. Defaults to sandbox.",
                ],
            ],
            "required": [],
            "additionalProperties": false,
        ],
        execute: { _, _, cancellation, _ in
            try cancellation?.throwIfCancelled()
            let state = try await AgentSessionManager.shared.localVMWorkspaceState(sessionId: sessionID)
            guard let state else {
                return AgentToolResult(
                    content: [.text(TextContent(text: "Sandbox workspace review is not available."))],
                    details: .object(["available": .bool(false)])
                )
            }
            return AgentToolResult(
                content: [.text(TextContent(text: currentChangesToolText(state)))],
                details: currentChangesToolDetails(state)
            )
        }
    )
}

@MainActor
private func connectorForTool(_ args: KWWKAI.JSONValue) async throws -> LocalRuntimeConnector {
    let environment = args.objectValue.flatMap { stringValue($0["environment"]) }
    return try await connectorForEnvironment(environment)
}

@MainActor
private func connectorForEnvironment(_ environment: String?) async throws -> LocalRuntimeConnector {
    try await AgentSessionManager.shared.connectorForLocalTool(environment: environment)
}

private nonisolated func commonFileParameters(extra: [String: KWWKAI.JSONValue], required: [String]) -> KWWKAI.JSONValue {
    var properties: [String: KWWKAI.JSONValue] = [
        "path": ["type": "string"],
        "environment": environmentParameter(),
    ]
    for (key, value) in extra {
        properties[key] = value
    }
    return .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
        "additionalProperties": false,
    ])
}

private nonisolated func commonSearchParameters(required: [String]) -> KWWKAI.JSONValue {
    [
        "type": "object",
        "properties": [
            "pattern": ["type": "string"],
            "path": ["type": "string"],
            "glob": ["type": "string"],
            "context": ["type": "number"],
            "environment": environmentParameter(),
        ],
        "required": .array(required.map { .string($0) }),
        "additionalProperties": false,
    ]
}

private nonisolated func environmentParameter() -> KWWKAI.JSONValue {
    [
        "type": "string",
        "enum": ["sandbox", "local"],
        "description": "Execution target. Use sandbox by default. local is protected and should be used only when the user explicitly requests direct host work or sandbox cannot complete the task.",
    ]
}

private nonisolated func ensurePathParameter(_ args: KWWKAI.JSONValue) -> KWWKAI.JSONValue {
    var object = args.objectValue ?? [:]
    if object["path"] == nil {
        object["path"] = "."
    }
    return .object(object)
}

private nonisolated func connectorJSON(from value: KWWKAI.JSONValue) -> JSONValue {
    switch value {
    case .null:
        .null
    case let .bool(value):
        .bool(value)
    case let .int(value):
        .int(value)
    case let .double(value):
        .double(value)
    case let .string(value):
        .string(value)
    case let .array(values):
        .array(values.map(connectorJSON))
    case let .object(object):
        .object(object.mapValues(connectorJSON))
    }
}

private nonisolated func aiJSON(from value: JSONValue) -> KWWKAI.JSONValue {
    switch value {
    case .null:
        .null
    case let .bool(value):
        .bool(value)
    case let .int(value):
        .int(value)
    case let .double(value):
        .double(value)
    case let .string(value):
        .string(value)
    case let .array(values):
        .array(values.map(aiJSON))
    case let .object(object):
        .object(object.mapValues(aiJSON))
    }
}

private nonisolated func stringValue(_ value: KWWKAI.JSONValue?) -> String? {
    guard case let .string(value) = value else { return nil }
    return value
}

private nonisolated func localString(_ value: JSONValue?) -> String? {
    guard case let .string(value) = value else { return nil }
    return value
}

private nonisolated func localInt(_ value: JSONValue?) -> Int? {
    switch value {
    case let .int(value):
        value
    case let .double(value):
        Int(value)
    default:
        nil
    }
}

private nonisolated func localBool(_ value: JSONValue?) -> Bool? {
    guard case let .bool(value) = value else { return nil }
    return value
}

private nonisolated func currentChangesToolDetails(_ state: WorkspaceState) -> KWWKAI.JSONValue {
    .object([
        "available": .bool(true),
        "session_id": .string(state.sessionId),
        "environment_id": .string(state.environmentId),
        "environment_label": .string(state.environmentLabel),
        "file_diff": .array(state.fileDiff.map { diff in
            .object([
                "path": .string(diff.path),
                "mode": .int(Int(diff.mode)),
                "is_dir": .bool(diff.isDir),
                "is_updated": .bool(diff.isUpdated),
                "is_deleted": .bool(diff.isDeleted),
                "moved_from": diff.movedFrom.map { .string($0) } ?? .null,
                "timestamp": .string(diff.timestamp),
                "size": .int(Int(diff.size)),
            ])
        }),
    ])
}

private nonisolated func currentChangesToolText(_ state: WorkspaceState) -> String {
    let diffs = state.fileDiff
    guard !diffs.isEmpty else {
        return "No file changes detected."
    }

    let created = diffs.filter { !$0.isDeleted && $0.movedFrom == nil && !$0.isUpdated }
    let modified = diffs.filter { !$0.isDeleted && $0.movedFrom == nil && $0.isUpdated }
    let moved = diffs.filter { !$0.isDeleted && $0.movedFrom != nil }
    let deleted = diffs.filter(\.isDeleted)

    var sections = ["Total changes: \(diffs.count) file(s)"]
    appendChangeSection(title: "Created", marker: "+", diffs: created, into: &sections)
    appendChangeSection(title: "Modified", marker: "~", diffs: modified, into: &sections)
    appendMovedSection(diffs: moved, into: &sections)
    appendChangeSection(title: "Deleted", marker: "-", diffs: deleted, includeSize: false, into: &sections)
    return sections.joined(separator: "\n\n")
}

private nonisolated func appendChangeSection(
    title: String,
    marker: String,
    diffs: [FileDiff],
    includeSize: Bool = true,
    into sections: inout [String]
) {
    guard !diffs.isEmpty else { return }
    let lines = diffs.map { diff in
        let suffix = includeSize ? " (\(formattedByteSize(diff.size)))" : ""
        return "  \(marker) \(diff.path)\(suffix)"
    }
    sections.append("\(title) (\(diffs.count)):\n\(lines.joined(separator: "\n"))")
}

private nonisolated func appendMovedSection(diffs: [FileDiff], into sections: inout [String]) {
    guard !diffs.isEmpty else { return }
    let lines = diffs.map { diff in
        "  -> \(diff.path) (from \(diff.movedFrom ?? "unknown"))"
    }
    sections.append("Moved (\(diffs.count)):\n\(lines.joined(separator: "\n"))")
}

private nonisolated func formattedByteSize(_ size: Int64) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(max(size, 0))
    var index = 0
    while value >= 1024, index < units.count - 1 {
        value /= 1024
        index += 1
    }
    if index == 0 {
        return "\(Int(value)) \(units[index])"
    }
    return String(format: "%.1f %@", value, units[index])
}

private nonisolated func readToolText(_ result: JSONValue) -> String {
    guard case let .object(object) = result else { return "" }
    let content = localString(object["content"]) ?? ""
    let encoding = localString(object["encoding"]) ?? "utf8"
    if encoding == "base64" {
        return "[binary file, base64 content in tool details]"
    }
    return content
}

private nonisolated func mutationToolText(action: String, args: KWWKAI.JSONValue, result: JSONValue) -> String {
    let path = args.objectValue.flatMap { stringValue($0["path"]) } ?? "file"
    let size: Int = {
        guard case let .object(object) = result else { return 0 }
        return localInt(object["size"]) ?? 0
    }()
    return "\(action) \(size) bytes to \(path)"
}

private nonisolated func permissionToolText(_ result: JSONValue) -> String {
    guard case let .object(object) = result else {
        return "Permission request completed"
    }
    let message = localString(object["message"]) ?? "Permission request completed"
    let approved = localBool(object["approved"]) == true
    return approved ? message : "Permission denied: \(message)"
}

private nonisolated func commandOutput(stdout: String, stderr: String) -> String {
    if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return stdout
    }
    if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return stderr
    }
    return "\(stdout)\n\(stderr)"
}

private nonisolated func grepToolText(_ result: JSONValue) -> String {
    guard case let .object(object) = result,
          case let .array(matches) = object["matches"] ?? .null
    else { return "No matches found" }
    let lines = matches.compactMap { value -> String? in
        guard case let .object(match) = value else { return nil }
        let file = localString(match["file"]) ?? "file"
        let line = localInt(match["line"]) ?? 0
        let content = localString(match["content"]) ?? ""
        return "\(file):\(line): \(content)"
    }

    let timedOut = localBool(object["timed_out"]) == true
    if timedOut {
        let message = "Search timed out after 10 seconds. Narrow the search by setting a smaller path or adding a glob."
        guard !lines.isEmpty else { return message }
        return ([message] + lines).joined(separator: "\n")
    }
    if lines.isEmpty { return "No matches found" }
    return lines.joined(separator: "\n")
}

private nonisolated func findToolText(_ result: JSONValue, args: KWWKAI.JSONValue) -> String {
    let pattern = args.objectValue.flatMap { stringValue($0["pattern"]) } ?? "pattern"
    guard case let .object(object) = result,
          case let .array(matches) = object["matches"] ?? .null
    else { return "No files match \(pattern)" }
    if matches.isEmpty { return "No files match \(pattern)" }
    return matches.compactMap(localString).joined(separator: "\n")
}

private nonisolated func listToolText(_ result: JSONValue) -> String {
    guard case let .object(object) = result,
          case let .array(entries) = object["entries"] ?? .null
    else { return "" }
    return entries.compactMap { value -> String? in
        guard case let .object(entry) = value else { return nil }
        let name = localString(entry["name"]) ?? ""
        let kind = localString(entry["kind"]) ?? "file"
        switch kind {
        case "dir":
            return "\(name)/"
        case "symlink":
            return "\(name)@"
        default:
            return name
        }
    }.joined(separator: "\n")
}
