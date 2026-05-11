import Foundation
import OSLog

private let computerUseLogger = Logger(
    subsystem: Logger.loggingSubsystem,
    category: "LocalRuntimeConnectorComputerUse"
)

/// Response envelope expected by the local ComputerUse tool. Fields left empty
/// are omitted during encoding.
private struct ComputerUseResponse: Encodable {
    var ok: Bool
    var error: String?
    var message: String?
    var mode: String?
    var help: String?
    var text: String?
    var imageDataURL: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var imageSizeBytes: Int?

    private enum CodingKeys: String, CodingKey {
        case ok, error, message, mode, help, text
        case imageDataURL = "image_data_url"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case imageSizeBytes = "image_size_bytes"
    }

    static func failure(_ message: String) -> ComputerUseResponse {
        ComputerUseResponse(ok: false, error: message)
    }

    static func success(text: String? = nil, message: String? = nil) -> ComputerUseResponse {
        ComputerUseResponse(ok: true, message: message, text: text)
    }
}

private struct ComputerUseToolCall: Decodable {
    let environment: String?
    let action: String
    let thinking: String?
    let args: JSONValue?
}

extension LocalRuntimeConnector {
    func handleComputerUse(_ msg: ConnectorMessage) async {
        guard environmentKind == .localMacOS else {
            await sendResponse(.error(id: msg.id, message: "computer_use is only supported on local macOS"))
            return
        }

        guard let params = msg.params else {
            await sendResponse(.error(id: msg.id, message: "missing params"))
            return
        }

        let call: ComputerUseToolCall
        do {
            call = try params.decode(ComputerUseToolCall.self)
        } catch {
            await sendResponse(.error(id: msg.id, message: "invalid params: \(error.localizedDescription)"))
            return
        }

        let response = await performComputerUse(call: call, sessionId: msg.sessionId)
        let payload: JSONValue
        do {
            payload = try jsonValue(from: response)
        } catch {
            await sendResponse(.error(id: msg.id, message: "encode computer_use response: \(error.localizedDescription)"))
            return
        }
        await sendResponse(.response(id: msg.id, result: payload))
    }

    private func performComputerUse(
        call: ComputerUseToolCall,
        sessionId: String?
    ) async -> ComputerUseResponse {
        let client = ComputerUseDaemonClient.shared
        let action = call.action.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch action {
            case "start":
                return try await startSession(call: call, client: client, sessionId: sessionId)
            case "end", "stop":
                await updateForegroundThinkingIfNeeded(call.thinking, action: action, client: client)
                defer { ComputerUseSessionRegistry.shared.noteStopped(sessionID: sessionId) }
                let text = try await client.stopSession()
                return .success(text: text.isEmpty ? nil : text, message: "session ended")
            case "status":
                let text = try await client.sessionStatusJSON()
                return .success(text: text)
            case "mode-help":
                guard let mode = extractMode(from: call.args) else {
                    return .failure("mode-help requires args.mode = \"foreground\" or \"background\"")
                }
                let help = try await client.modeHelp(mode)
                return ComputerUseResponse(ok: true, help: help)
            default:
                return try await dispatchAction(action: action, args: call.args, thinking: call.thinking, client: client)
            }
        } catch let error as ComputerUseDaemonClient.ClientError {
            computerUseLogger.error("ComputerUse daemon error: \(error.description, privacy: .public)")
            return .failure(error.description)
        } catch {
            computerUseLogger.error("ComputerUse error: \(error.localizedDescription, privacy: .public)")
            return .failure(error.localizedDescription)
        }
    }

    private func startSession(
        call: ComputerUseToolCall,
        client: ComputerUseDaemonClient,
        sessionId: String?
    ) async throws -> ComputerUseResponse {
        let requestedApps = extractStringArray(from: call.args, key: "apps")
        let description = buildStartDescription(call: call, apps: requestedApps)

        // Pre-flight daemon TCC state so the picker shows which permissions
        // still need granting. Best-effort: if the daemon isn't reachable
        // yet, we still show the picker without the hint.
        let permissions: [SessionHistoryMessage.ComputerUsePermissionPane]? = if let status = try? await client.permissionsStatus() {
            status.panes.map {
                SessionHistoryMessage.ComputerUsePermissionPane(pane: $0.name, granted: $0.granted)
            }
        } else {
            nil
        }

        let reply = await awaitComputerUseStart(
            availableModes: [
                ComputerUseDaemonClient.Mode.background.rawValue,
                ComputerUseDaemonClient.Mode.foreground.rawValue,
            ],
            apps: requestedApps.isEmpty ? nil : requestedApps,
            permissions: permissions,
            description: description,
            sessionId: sessionId
        )
        guard reply.approved else {
            return .failure("user denied computer_use start")
        }
        // Mode is chosen entirely by the user. Fallback to background only as
        // a safety net if the reply envelope is malformed; in practice the UI
        // always supplies `mode`.
        let chosenMode = ComputerUseDaemonClient.Mode(rawValue: reply.mode ?? "") ?? .background
        let display = extractInt(from: call.args, key: "display")
        let startToken = ComputerUseSessionRegistry.shared.beginStart(sessionID: sessionId)
        defer { ComputerUseSessionRegistry.shared.finishStart(startToken) }

        try await Task.sleep(nanoseconds: 1_000_000_000)
        guard ComputerUseSessionRegistry.shared.shouldContinueStart(startToken) else {
            return .failure("computer_use start cancelled")
        }

        let startMessage = try await client.startSession(
            mode: chosenMode,
            apps: requestedApps,
            display: display,
            observer: chosenMode == .foreground ? resolveObserverArgs() : nil
        )
        guard ComputerUseSessionRegistry.shared.markStarted(startToken, mode: chosenMode) else {
            _ = try? await client.stopSession()
            return .failure("computer_use start cancelled")
        }
        await updateForegroundThinkingIfNeeded(call.thinking, action: "start", client: client)
        let help = await (try? client.modeHelp(chosenMode)) ?? ""
        guard ComputerUseSessionRegistry.shared.isActive(startToken) else {
            return .failure("computer_use start cancelled")
        }

        return ComputerUseResponse(
            ok: true,
            message: startMessage.isEmpty ? nil : startMessage,
            mode: chosenMode.rawValue,
            help: help.isEmpty ? nil : help
        )
    }

    private func buildStartDescription(
        call: ComputerUseToolCall,
        apps: [String]
    ) -> String {
        var lines = ["Agent wants to start ComputerUse."]
        if !apps.isEmpty {
            lines.append("Apps in focus: \(apps.joined(separator: ", "))")
        }
        if let env = call.environment, !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Requested environment: \(env)")
        }
        return lines.joined(separator: "\n")
    }

    private func dispatchAction(
        action: String,
        args: JSONValue?,
        thinking: String?,
        client: ComputerUseDaemonClient
    ) async throws -> ComputerUseResponse {
        await updateForegroundThinkingIfNeeded(thinking, action: action, client: client)
        let dict = flattenArgsObject(args)
        let argv = ComputerUseDaemonClient.encodeActionArgs(action: action, args: dict)
        let text = try await client.dispatchAction(argv)
        return decodeDaemonText(text)
    }

    private func updateForegroundThinkingIfNeeded(
        _ thinking: String?,
        action: String,
        client: ComputerUseDaemonClient
    ) async {
        let text = thinking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty,
              action != "thinking",
              ComputerUseSessionRegistry.shared.currentMode == .foreground
        else { return }

        do {
            _ = try await client.dispatchAction(["thinking", "--text", text])
        } catch {
            computerUseLogger.warning("failed to update ComputerUse thinking: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Foreground mode returns image actions as a JSON object with
    /// `image_data_url`; everything else is opaque text. Detect the JSON
    /// envelope and fold it into the ComputerUseResponse so the Go tool can
    /// emit structured image blocks.
    private func decodeDaemonText(_ text: String) -> ComputerUseResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let imageDataURL = payload["image_data_url"] as? String,
              !imageDataURL.isEmpty
        else {
            return .success(text: text.isEmpty ? nil : text)
        }
        return ComputerUseResponse(
            ok: true,
            message: payload["message"] as? String,
            text: nil,
            imageDataURL: imageDataURL,
            imageWidth: payload["image_width"] as? Int,
            imageHeight: payload["image_height"] as? Int,
            imageSizeBytes: payload["image_size_bytes"] as? Int
        )
    }

    // MARK: - Helpers

    private func extractMode(from args: JSONValue?) -> ComputerUseDaemonClient.Mode? {
        guard case let .object(dict) = args,
              case let .string(raw) = dict["mode"] ?? .null
        else { return nil }
        return ComputerUseDaemonClient.Mode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func extractStringArray(from args: JSONValue?, key: String) -> [String] {
        guard case let .object(dict) = args,
              case let .array(items) = dict[key] ?? .null
        else { return [] }
        return items.compactMap {
            if case let .string(value) = $0 { return value }
            return nil
        }
    }

    private func extractInt(from args: JSONValue?, key: String) -> Int? {
        guard case let .object(dict) = args else { return nil }
        switch dict[key] ?? .null {
        case let .int(value):
            return value
        case let .double(value):
            return Int(value)
        case let .string(raw):
            return Int(raw)
        default:
            return nil
        }
    }

    private func flattenArgsObject(_ args: JSONValue?) -> [String: JSONValue] {
        guard case let .object(dict) = args else { return [:] }
        return dict
    }

    /// Route observer summaries through OpenBridge via the internal
    /// `ObserverBridgeServer` socket. This keeps observer summary handling
    /// inside the local host app, with no daemon-side model API key.
    ///
    /// We start the server lazily right before handing the daemon the
    /// socket path; if it was already running (previous session),
    /// `start()` is a no-op.
    private func resolveObserverArgs() -> ComputerUseDaemonClient.ObserverStartArgsWire {
        ObserverBridgeServer.shared.start()
        return ComputerUseDaemonClient.ObserverStartArgsWire(
            bridgeSocketPath: ObserverBridgeServer.currentSocketPath,
            captureIntervalMs: nil,
            finalSummaryTimeoutMs: nil
        )
    }
}

// MARK: - JSONValue helpers

private func jsonValue(from encodable: some Encodable) throws -> JSONValue {
    let encoder = JSONEncoder()
    let data = try encoder.encode(encodable)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
