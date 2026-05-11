import Foundation

extension LocalAgentSession {
    func makeToolStatusHistoryMessage(
        callId: String,
        toolName: String,
        args: String?,
        status: String
    ) -> SessionHistoryMessage {
        SessionHistoryMessage(
            id: "local-tool-\(callId)",
            type: "message",
            role: "tool",
            timestamp: Date().timeIntervalSince1970,
            content: [
                SessionHistoryMessage.Content(
                    type: "text",
                    text: Self.toolStatusContent(toolName: toolName, args: args, status: status)
                ),
            ],
            messageId: nil,
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
            toolUseId: callId,
            errorType: nil,
            error: nil
        )
    }

    static func toolCallSummary(name: String, arguments: String?) -> String {
        let args = parseJSONObject(arguments)
        if name == "Exec" {
            let label = trimmedString(args?["description"]) ?? trimmedString(args?["command"])
            return shorten("Run \(quote(label, fallback: "command"))\(environmentSuffix(trimmedString(args?["environment"])))")
        }
        if let fileSummary = fileToolCallSummary(name: name, args: args) {
            return fileSummary
        }
        if let webSummary = webToolCallSummary(name: name, args: args) {
            return webSummary
        }
        if name == "WebBrowse" {
            if let target = urlLabel(trimmedString(args?["url"])) ?? trimmedString(args?["url"]) {
                return shorten("Browse \(target)")
            }
            return "Browse website"
        }
        if name == "manage_schedule" {
            return "Manage schedule"
        }
        if name == "manage_memory" {
            return "Manage memory"
        }
        return humanizeToolName(name)
    }

    private static func toolStatusContent(toolName: String, args: String?, status: String) -> String {
        var payload: [String: Any] = [
            "kind": "tool_call",
            "tool_name": toolName,
            "status": status,
            "completed": status != "running",
        ]
        if let args {
            payload["arguments"] = args
        }
        if let command = toolCommand(name: toolName, arguments: args) {
            payload["command"] = command
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return toolCallSummary(name: toolName, arguments: args)
        }
        return text
    }

    private static func fileToolCallSummary(name: String, args: [String: Any]?) -> String? {
        let path = trimmedString(args?["path"])
        let environment = trimmedString(args?["environment"])
        switch name {
        case "Read":
            return shorten("Read \(pathLabel(path, environment: environment))")
        case "Write":
            return shorten("Write \(pathLabel(path, environment: environment))")
        case "Edit":
            return shorten("Edit \(pathLabel(path, environment: environment))")
        case "List":
            let prefix = boolValue(args?["recursive"]) ? "List recursively " : "List "
            return shorten(prefix + pathLabel(path, environment: environment))
        case "Grep":
            return shorten("Search \(path ?? "/")\(environmentSuffix(environment)) for \(quote(trimmedString(args?["pattern"]), fallback: "pattern"))")
        case "Glob":
            return shorten("Find \(quote(trimmedString(args?["pattern"]), fallback: "files")) in \(path ?? "/")\(environmentSuffix(environment))")
        default:
            return nil
        }
    }

    private static func webToolCallSummary(name: String, args: [String: Any]?) -> String? {
        switch name {
        case "ExaSearch":
            return shorten("Search web for \(quote(trimmedString(args?["query"]), fallback: "query"))")
        case "ExaContents":
            let urls = trimmedArray(args?["urls"])
            if urls.count == 1 {
                return shorten("Fetch \(urlLabel(urls[0]) ?? urls[0])")
            }
            return urls.isEmpty ? "Fetch web pages" : "Fetch \(urls.count) web pages"
        default:
            return nil
        }
    }

    private static func toolCommand(name: String, arguments: String?) -> String? {
        guard name == "Exec" else { return nil }
        return trimmedString(parseJSONObject(arguments)?["command"])
    }

    private static func parseJSONObject(_ raw: String?) -> [String: Any]? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(trimmedString(_:))
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private static func environmentSuffix(_ environment: String?) -> String {
        guard let environment else { return "" }
        let trimmed = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == "vfs" {
            return ""
        }
        if normalized == "local" || normalized.hasPrefix("local-") {
            return " on this Mac"
        }
        if normalized == "sandbox" || normalized.hasPrefix("sandbox-") || normalized == "local-vm" || normalized.hasPrefix("local-vm-") || normalized == "cloud-vm" {
            return " in a safe workspace on this Mac"
        }
        return " in \(trimmed)"
    }

    private static func pathLabel(_ path: String?, environment: String?) -> String {
        "\(path ?? "file")\(environmentSuffix(environment))"
    }

    private static func urlLabel(_ rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        return URL(string: rawURL)?.host ?? rawURL
    }

    private static func quote(_ text: String?, fallback: String) -> String {
        "\"\(shorten(text ?? fallback, maxLength: 40))\""
    }

    private static func shorten(_ text: String, maxLength: Int = 96) -> String {
        guard text.count > maxLength else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength - 1)
        return text[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func humanizeToolName(_ toolName: String) -> String {
        let withSpaces = toolName
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = withSpaces.first else { return "Tool call" }
        return first.uppercased() + String(withSpaces.dropFirst())
    }
}
