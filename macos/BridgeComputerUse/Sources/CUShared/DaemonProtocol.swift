import Foundation

public struct DaemonRequest: Codable {
    public var args: [String]?
    public var control: String?
    public var session: SessionControl?
    public var mode: ModeKind?

    public init(
        args: [String]? = nil,
        control: String? = nil,
        session: SessionControl? = nil,
        mode: ModeKind? = nil
    ) {
        self.args = args
        self.control = control
        self.session = session
        self.mode = mode
    }

    public static func action(_ args: [String]) -> DaemonRequest {
        DaemonRequest(args: args)
    }

    public static func ping() -> DaemonRequest {
        DaemonRequest(control: "ping")
    }

    public static func shutdown() -> DaemonRequest {
        DaemonRequest(control: "shutdown")
    }

    public static func sessionStatus() -> DaemonRequest {
        DaemonRequest(control: "session-status")
    }

    /// Retrieve the full action-level help text for a given mode. Used by
    /// OpenBridge.app to hand the agent a complete action+args reference after
    /// `start` succeeds.
    public static func modeHelp(_ mode: ModeKind) -> DaemonRequest {
        DaemonRequest(control: "mode-help", mode: mode)
    }

    /// Fetch the current TCC status for the panes the daemon needs
    /// (accessibility + screen recording). Hosts use this to pre-flight the
    /// mode picker UI so the user sees which permissions are missing before
    /// approving the start.
    public static func permissionsStatus() -> DaemonRequest {
        DaemonRequest(control: "permissions-status")
    }

    /// Pop the PermissionFlow unified authorization window. Non-blocking —
    /// the daemon opens the window and returns immediately; callers poll
    /// `permissions-status` afterwards to watch grants land.
    public static func openPermissionFlow() -> DaemonRequest {
        DaemonRequest(control: "open-permission-flow")
    }

    public static func startSession(
        mode: ModeKind,
        foreground: ForegroundStartArgs? = nil,
        background: BackgroundStartArgs? = nil
    ) -> DaemonRequest {
        DaemonRequest(session: SessionControl(
            op: .start,
            mode: mode,
            foreground: foreground,
            background: background
        ))
    }

    public static func stopSession() -> DaemonRequest {
        DaemonRequest(session: SessionControl(op: .stop))
    }
}

public struct DaemonResponse: Codable {
    public var ok: Bool
    public var text: String?
    public var error: String?

    public init(ok: Bool, text: String? = nil, error: String? = nil) {
        self.ok = ok
        self.text = text
        self.error = error
    }

    public static func success(_ text: String) -> DaemonResponse {
        DaemonResponse(ok: true, text: text, error: nil)
    }

    public static func failure(_ error: String) -> DaemonResponse {
        DaemonResponse(ok: false, text: nil, error: error)
    }
}

public enum ModeKind: String, Codable, Sendable, CaseIterable {
    case foreground
    case background
}

public struct SessionControl: Codable, Sendable {
    public enum Op: String, Codable, Sendable { case start, stop }

    public var op: Op
    public var mode: ModeKind?
    public var foreground: ForegroundStartArgs?
    public var background: BackgroundStartArgs?

    public init(
        op: Op,
        mode: ModeKind? = nil,
        foreground: ForegroundStartArgs? = nil,
        background: BackgroundStartArgs? = nil
    ) {
        self.op = op
        self.mode = mode
        self.foreground = foreground
        self.background = background
    }
}

public struct ForegroundStartArgs: Codable, Sendable {
    public var apps: [String]
    public var display: Int?
    /// Optional observer config. OpenBridge passes this so observe-mode summaries
    /// route back through the local host app instead of a daemon-side model
    /// client.
    public var observer: ObserverStartArgs?

    public init(
        apps: [String] = [],
        display: Int? = nil,
        observer: ObserverStartArgs? = nil
    ) {
        self.apps = apps
        self.display = display
        self.observer = observer
    }
}

public struct ObserverStartArgs: Codable, Sendable {
    /// Filesystem path to a UNIX-domain socket where OpenBridge (the host
    /// app) accepts observer summary requests. The daemon connects to
    /// this socket per-round and delegates summary work to OpenBridge.
    public var bridgeSocketPath: String?
    public var captureIntervalMs: Int?
    public var finalSummaryTimeoutMs: Int?

    public init(
        bridgeSocketPath: String? = nil,
        captureIntervalMs: Int? = nil,
        finalSummaryTimeoutMs: Int? = nil
    ) {
        self.bridgeSocketPath = bridgeSocketPath
        self.captureIntervalMs = captureIntervalMs
        self.finalSummaryTimeoutMs = finalSummaryTimeoutMs
    }
}

/// Framed JSON exchanged between the daemon's `ObserverBridgeBackend`
/// and OpenBridge's `ObserverBridgeServer`. One request per socket
/// connection; wire framing is the same 4-byte big-endian length +
/// UTF-8 JSON the main daemon socket uses (`DaemonWire`).
public struct ObserverBridgeRequest: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case round
        case final
    }

    public var kind: Kind
    /// Monotonic round counter the daemon assigns, handy for logging.
    public var roundIndex: Int
    /// Epoch-ms at session start — lets OpenBridge render the same
    /// "<elapsed>s screen #N:" timeline the legacy observer uses.
    public var sessionStartedAt: Double
    public var timeline: [ObserverBridgeTimelineEntry]

    public init(
        kind: Kind,
        roundIndex: Int,
        sessionStartedAt: Double,
        timeline: [ObserverBridgeTimelineEntry]
    ) {
        self.kind = kind
        self.roundIndex = roundIndex
        self.sessionStartedAt = sessionStartedAt
        self.timeline = timeline
    }
}

public struct ObserverBridgeTimelineEntry: Codable, Sendable {
    public enum EntryType: String, Codable, Sendable {
        case summary
        case capture
    }

    public var type: EntryType
    public var timestampMs: Double
    /// Populated when `type == .summary` — the prior round's summary text.
    public var text: String?
    /// Populated when `type == .capture` — base64 PNG/JPEG bytes.
    public var frameBase64: String?
    public var frameMimeType: String?
    public var displayIndex: Int
    public var sequence: Int

    public init(
        type: EntryType,
        timestampMs: Double,
        text: String? = nil,
        frameBase64: String? = nil,
        frameMimeType: String? = nil,
        displayIndex: Int = 1,
        sequence: Int = 0
    ) {
        self.type = type
        self.timestampMs = timestampMs
        self.text = text
        self.frameBase64 = frameBase64
        self.frameMimeType = frameMimeType
        self.displayIndex = displayIndex
        self.sequence = sequence
    }
}

public struct ObserverBridgeResponse: Codable, Sendable {
    public var ok: Bool
    public var text: String?
    public var error: String?

    public init(ok: Bool, text: String? = nil, error: String? = nil) {
        self.ok = ok
        self.text = text
        self.error = error
    }

    public static func success(_ text: String) -> ObserverBridgeResponse {
        ObserverBridgeResponse(ok: true, text: text, error: nil)
    }

    public static func failure(_ error: String) -> ObserverBridgeResponse {
        ObserverBridgeResponse(ok: false, text: nil, error: error)
    }
}

public struct BackgroundStartArgs: Codable, Sendable {
    public init() {}
}

public enum DaemonPaths {
    /// Runtime directory for the daemon socket / pid file. Override via
    /// `CUEBOARD_COMPUTER_USE_RUNTIME_DIR` when callers need to pin the path
    /// (tests, sandboxed hosts).
    public static var runtimeDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CUEBOARD_COMPUTER_USE_RUNTIME_DIR"],
           override.isEmpty == false
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("app.afk.openbridge", isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
    }

    public static var socketURL: URL {
        runtimeDirectory.appendingPathComponent("daemon.sock")
    }

    /// UNIX socket where OpenBridge listens for observer summary requests
    /// forwarded by the daemon. OpenBridge owns the server end; the daemon
    /// connects to it only when `ObserverStartArgs.bridgeSocketPath` is
    /// set on a foreground session start.
    public static var observerSocketURL: URL {
        runtimeDirectory.appendingPathComponent("observer.sock")
    }

    public static var pidFileURL: URL {
        runtimeDirectory.appendingPathComponent("daemon.pid")
    }

    public static func ensureRuntimeDirectory() throws {
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
    }
}

public enum DaemonWireError: Error, CustomStringConvertible {
    case socketCreate(Int32)
    case socketBind(Int32, path: String)
    case socketListen(Int32)
    case socketConnect(Int32, path: String)
    case socketAccept(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case incompleteRead(expected: Int, got: Int)
    case payloadTooLarge(Int)
    case encodeFailed(String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case let .socketCreate(code):
            "socket() failed errno=\(code)"
        case let .socketBind(code, path):
            "bind() failed errno=\(code) path=\(path)"
        case let .socketListen(code):
            "listen() failed errno=\(code)"
        case let .socketConnect(code, path):
            "connect() failed errno=\(code) path=\(path)"
        case let .socketAccept(code):
            "accept() failed errno=\(code)"
        case let .writeFailed(code):
            "write failed errno=\(code)"
        case let .readFailed(code):
            "read failed errno=\(code)"
        case let .incompleteRead(expected, got):
            "incomplete read expected=\(expected) got=\(got)"
        case let .payloadTooLarge(n):
            "payload too large: \(n) bytes"
        case let .encodeFailed(message):
            "encode failed: \(message)"
        case let .decodeFailed(message):
            "decode failed: \(message)"
        }
    }
}

/// Read/write framed JSON messages over a file descriptor.
/// Frame: 4-byte big-endian length + UTF-8 JSON payload.
public enum DaemonWire {
    public static let maxPayload = 64 * 1024 * 1024

    public static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw DaemonWireError.encodeFailed(String(describing: error))
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DaemonWireError.decodeFailed(String(describing: error))
        }
    }

    public static func writeFrame(fd: Int32, payload: Data) throws {
        guard payload.count <= maxPayload else {
            throw DaemonWireError.payloadTooLarge(payload.count)
        }

        var lengthBE = UInt32(payload.count).bigEndian
        try withUnsafeBytes(of: &lengthBE) { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
        try payload.withUnsafeBytes { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
    }

    public static func readFrame(fd: Int32) throws -> Data {
        var header = Data(count: 4)
        try header.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        let length = Int(UInt32(bigEndian: header.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length >= 0, length <= maxPayload else {
            throw DaemonWireError.payloadTooLarge(length)
        }

        var payload = Data(count: length)
        try payload.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        return payload
    }

    private static func writeAll(fd: Int32, bytes: UnsafeRawBufferPointer) throws {
        var remaining = bytes.count
        var offset = 0
        while remaining > 0 {
            let written = Darwin.write(
                fd,
                bytes.baseAddress!.advanced(by: offset),
                remaining
            )
            if written > 0 {
                offset += written
                remaining -= written
                continue
            }
            if written == -1, errno == EINTR {
                continue
            }
            throw DaemonWireError.writeFailed(errno)
        }
    }

    private static func readAll(fd: Int32, into buffer: UnsafeMutableRawBufferPointer) throws {
        var remaining = buffer.count
        var offset = 0
        while remaining > 0 {
            let got = Darwin.read(
                fd,
                buffer.baseAddress!.advanced(by: offset),
                remaining
            )
            if got > 0 {
                offset += got
                remaining -= got
                continue
            }
            if got == 0 {
                throw DaemonWireError.incompleteRead(
                    expected: buffer.count,
                    got: offset
                )
            }
            if got == -1, errno == EINTR {
                continue
            }
            throw DaemonWireError.readFailed(errno)
        }
    }
}
