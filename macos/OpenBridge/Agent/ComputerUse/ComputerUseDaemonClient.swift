import AppKit
import Darwin
import Foundation
import OSLog

/// Talks to the OpenBridge Computer Use helper app
/// (OpenBridge.app/Contents/Helpers/OpenBridge Computer Use.app) over the Unix-domain
/// socket defined by `DaemonPaths` in the helper's CUShared module. Wire
/// protocol: 4-byte big-endian length + UTF-8 JSON payload for request and
/// response.
///
/// This client intentionally does not link the helper's Swift module — the
/// helper is a separate signed .app with its own code-signing identity, and
/// we only need the JSON envelope here. The on-wire struct mirrors
/// `CUShared.DaemonRequest` / `DaemonResponse`; keep the two in sync.
@MainActor
final class ComputerUseDaemonClient {
    static let shared = ComputerUseDaemonClient()

    enum Mode: String, Codable, Sendable {
        case foreground
        case background
    }

    enum ClientError: Error, CustomStringConvertible {
        case helperBundleNotFound([String])
        case helperInstallFailed(String)
        case helperLaunchFailed(String)
        case helperUnresponsive(TimeInterval)
        case transport(String)
        case daemonFailure(String)
        case decode(String)

        var description: String {
            switch self {
            case let .helperBundleNotFound(paths):
                "OpenBridge Computer Use helper app not found; searched: \(paths.joined(separator: ", "))"
            case let .helperInstallFailed(message):
                "failed to install OpenBridge Computer Use helper: \(message)"
            case let .helperLaunchFailed(message):
                "failed to launch OpenBridge Computer Use helper: \(message)"
            case let .helperUnresponsive(seconds):
                "OpenBridge Computer Use helper did not become responsive within \(String(format: "%.1f", seconds))s"
            case let .transport(message):
                "ComputerUse transport error: \(message)"
            case let .daemonFailure(message):
                "ComputerUse daemon error: \(message)"
            case let .decode(message):
                "ComputerUse decode error: \(message)"
            }
        }
    }

    private let logger = Logger(
        subsystem: Logger.loggingSubsystem,
        category: "ComputerUseDaemonClient"
    )

    /// Short TTL on the "daemon is alive" signal so hot paths (each tool
    /// dispatch, and the chat permission-footer poll) don't re-ping the
    /// socket on every call. Invalidated on any transport failure.
    private static let pingCacheTTL: TimeInterval = 1.0
    private var lastPingSuccess: Date?

    private init() {}

    // MARK: - High-level operations

    /// Idempotent: launches the helper app if it's not already running, then
    /// verifies the daemon identity. All socket IO is dispatched off the main
    /// actor so a stalled daemon cannot wedge OpenBridge's main thread (which
    /// would backpressure the local workspace WebSocket and trip its proxy
    /// write deadline).
    func ensureRunning(timeout: TimeInterval = 5.0) async throws {
        if let last = lastPingSuccess, Date().timeIntervalSince(last) < Self.pingCacheTTL {
            return
        }
        if await isExpectedDaemonAlive() {
            lastPingSuccess = Date()
            return
        }
        lastPingSuccess = nil
        try await launchHelperApp()

        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if await isExpectedDaemonAlive() {
                lastPingSuccess = Date()
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ClientError.helperUnresponsive(timeout)
    }

    /// Start a new session in the given mode. Returns the text from the
    /// daemon, which is a short "session started (mode=…)" confirmation.
    /// Fetch `modeHelp` right after for the full action prompt.
    @discardableResult
    func startSession(
        mode: Mode,
        apps: [String] = [],
        display: Int? = nil,
        observer: ObserverStartArgsWire? = nil
    ) async throws -> String {
        try await ensureRunning()
        let session = SessionControlWire(
            op: .start,
            mode: mode,
            foreground: mode == .foreground
                ? ForegroundStartArgsWire(apps: apps, display: display, observer: observer)
                : nil,
            background: mode == .background ? BackgroundStartArgsWire() : nil
        )
        return try await request(DaemonRequestWire(session: session))
    }

    @discardableResult
    func stopSession() async throws -> String {
        try await ensureRunning()
        return try await request(DaemonRequestWire(session: SessionControlWire(op: .stop)))
    }

    func modeHelp(_ mode: Mode) async throws -> String {
        try await ensureRunning()
        return try await request(DaemonRequestWire(control: "mode-help", mode: mode))
    }

    func sessionStatusJSON() async throws -> String {
        try await ensureRunning()
        return try await request(DaemonRequestWire(control: "session-status"))
    }

    struct PermissionsStatus: Sendable {
        struct Pane: Sendable {
            let name: String
            let granted: Bool
        }

        let bundlePath: String?
        let panes: [Pane]
        var allGranted: Bool {
            panes.allSatisfy(\.granted)
        }
    }

    /// Ask the daemon for its TCC status (accessibility + screen recording).
    /// Used to render a "missing permissions" hint in the mode picker before
    /// asking the user to approve a session start.
    func permissionsStatus() async throws -> PermissionsStatus {
        try await ensureRunning()
        let json = try await request(DaemonRequestWire(control: "permissions-status"))
        guard let data = json.data(using: .utf8) else {
            return PermissionsStatus(bundlePath: nil, panes: [])
        }
        struct Report: Decodable {
            struct PaneStatus: Decodable {
                let pane: String
                let granted: Bool
            }

            let bundlePath: String?
            let statuses: [PaneStatus]

            private enum CodingKeys: String, CodingKey {
                case bundlePath
                case statuses
            }
        }
        let report = try JSONDecoder().decode(Report.self, from: data)
        return PermissionsStatus(
            bundlePath: report.bundlePath,
            panes: report.statuses.map { PermissionsStatus.Pane(name: $0.pane, granted: $0.granted) }
        )
    }

    /// Forward a CLI-style action. The args array has the shape
    /// `[action, "--flag", "value", …]` and is parsed by the active mode's
    /// runtime inside the helper.
    func dispatchAction(_ args: [String]) async throws -> String {
        try await ensureRunning()
        return try await request(DaemonRequestWire(args: args))
    }

    /// Ask the daemon to pop the PermissionFlow unified authorization window.
    /// Non-blocking: the daemon returns as soon as the window is shown; the
    /// caller polls `permissionsStatus()` afterwards to detect grants.
    @discardableResult
    func openPermissionFlow() async throws -> String {
        try await ensureRunning()
        return try await request(DaemonRequestWire(control: "open-permission-flow"))
    }

    /// Best-effort synchronous shutdown used by OpenBridge's AppDelegate on
    /// termination. Does not launch the helper if it's not running; does
    /// not block on async waits. The daemon tears down its active session
    /// before exiting in response to this request.
    func requestShutdownSync() {
        let socketPath = Self.socketPath
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        _ = try? Self.sendSync(DaemonRequestWire(control: "shutdown"), socketPath: socketPath)
    }

    // MARK: - Wire protocol (mirror of CUShared.DaemonRequest/Response)

    nonisolated struct DaemonRequestWire: Encodable, Sendable {
        var args: [String]?
        var control: String?
        var session: SessionControlWire?
        var mode: Mode?
    }

    nonisolated struct DaemonResponseWire: Decodable, Sendable {
        var ok: Bool
        var text: String?
        var error: String?
    }

    nonisolated struct DaemonPermissionReportWire: Decodable, Sendable {
        var bundlePath: String?
    }

    nonisolated enum DaemonIdentityProbe: Sendable {
        case expected
        case unexpected(actualBundlePath: String?)
        case unavailable
    }

    nonisolated struct SessionControlWire: Codable, Sendable {
        // swiftlint:disable:next type_name
        enum Op: String, Codable, Sendable { case start, stop }
        var op: Op
        var mode: Mode?
        var foreground: ForegroundStartArgsWire?
        var background: BackgroundStartArgsWire?
    }

    nonisolated struct ForegroundStartArgsWire: Codable, Sendable {
        var apps: [String]
        var display: Int?
        /// Observer runtime config. Daemon uses
        /// this in observe mode for the per-intervention screen summary;
        /// absent → daemon falls back to env vars, which are typically
        /// empty since `NSWorkspace.openApplication` doesn't inherit
        /// shell env.
        var observer: ObserverStartArgsWire?
    }

    nonisolated struct ObserverStartArgsWire: Codable, Sendable {
        /// Path to OpenBridge's observer socket. When present, the daemon
        /// forwards every summary request through this socket instead
        /// of calling Gemini directly, so the local app handles the LLM call.
        var bridgeSocketPath: String?
        var captureIntervalMs: Int?
        var finalSummaryTimeoutMs: Int?
    }

    nonisolated struct BackgroundStartArgsWire: Codable, Sendable {}

    // MARK: - Transport

    private func request(_ wire: DaemonRequestWire) async throws -> String {
        let socketPath = Self.socketPath
        do {
            let text = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.sendSync(wire, socketPath: socketPath)
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            lastPingSuccess = Date()
            return text
        } catch {
            lastPingSuccess = nil
            throw error
        }
    }

    private func isExpectedDaemonAlive() async -> Bool {
        let socketPath = Self.socketPath
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        let expectedPath: String
        do {
            expectedPath = try Self.canonicalPath(Self.locateHelperBundleURL().path)
        } catch {
            return false
        }

        let probe = await probeDaemonIdentity(
            socketPath: socketPath,
            expectedBundlePath: expectedPath
        )
        switch probe {
        case .expected:
            return true
        case let .unexpected(actualPath):
            logger.warning(
                "discarding ComputerUse daemon from unexpected bundle \(actualPath ?? "unknown", privacy: .public); expected \(expectedPath, privacy: .public)"
            )
            await discardUnexpectedDaemon(socketPath: socketPath)
            return false
        case .unavailable:
            return false
        }
    }

    private func probeDaemonIdentity(
        socketPath: String,
        expectedBundlePath: String
    ) async -> DaemonIdentityProbe {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try Self.sendSync(
                        DaemonRequestWire(control: "permissions-status"),
                        socketPath: socketPath
                    )
                    guard let data = text.data(using: .utf8) else {
                        continuation.resume(returning: .unexpected(actualBundlePath: nil))
                        return
                    }
                    let report = try JSONDecoder().decode(DaemonPermissionReportWire.self, from: data)
                    guard let bundlePath = report.bundlePath else {
                        continuation.resume(returning: .unexpected(actualBundlePath: nil))
                        return
                    }
                    let actualPath = Self.canonicalPath(bundlePath)
                    if actualPath == expectedBundlePath {
                        continuation.resume(returning: .expected)
                    } else {
                        continuation.resume(returning: .unexpected(actualBundlePath: actualPath))
                    }
                } catch {
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }

    private func discardUnexpectedDaemon(socketPath: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                _ = try? Self.sendSync(DaemonRequestWire(control: "shutdown"), socketPath: socketPath)
                Self.removeRuntimeFiles(socketPath: socketPath)
                continuation.resume()
            }
        }
    }

    private nonisolated static func sendSync(_ wire: DaemonRequestWire, socketPath: String) throws -> String {
        let fd = try dial(socketPath: socketPath)
        defer { close(fd) }

        let payload = try JSONEncoder().encode(wire)
        try writeFrame(fd: fd, payload: payload)
        let response = try readFrame(fd: fd)
        let decoded: DaemonResponseWire
        do {
            decoded = try JSONDecoder().decode(DaemonResponseWire.self, from: response)
        } catch {
            throw ClientError.decode(String(describing: error))
        }
        if decoded.ok {
            return decoded.text ?? ""
        }
        throw ClientError.daemonFailure(decoded.error ?? "unknown daemon error")
    }

    // MARK: - Helper launch

    private func launchHelperApp() async throws {
        let bundleURL = try Self.locateHelperBundleURL()
        logger.info("launching ComputerUse helper at \(bundleURL.path, privacy: .public)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        // Do NOT set `hides = true`: that sends `[NSApp hide:]` to the daemon
        // at launch, leaving `NSApp.isHidden = true`. While the daemon is
        // `.accessory` so it has no dock icon / menu bar anyway, its
        // ColorfulBorder window then stays orderedOut by the OS the moment
        // we try to show it. `.accessory` + `activates = false` is already
        // enough to keep it out of focus without hiding it.

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: ClientError.helperLaunchFailed(String(describing: error)))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func locateHelperBundleURL() throws -> URL {
        let fm = FileManager.default

        if let override = ProcessInfo.processInfo.environment["BRIDGE_COMPUTER_USE_APP_PATH"],
           override.isEmpty == false
        {
            let url = URL(fileURLWithPath: override)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
            throw ClientError.helperBundleNotFound([url.path])
        }

        return try installBundledHelperIfNeeded()
    }

    private static func installBundledHelperIfNeeded() throws -> URL {
        let fm = FileManager.default
        let sourceCandidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenBridge Computer Use.app"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BridgeComputerUse.app"),
        ]
        var isDir: ObjCBool = false
        guard let sourceURL = sourceCandidates.first(where: { url in
            isDir = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }) else {
            throw ClientError.helperBundleNotFound(sourceCandidates.map(\.path))
        }

        let destinationURL = helperInstallDirectory
            .appendingPathComponent("BridgeComputerUse.app")
        if !helperInstallNeedsUpdate(source: sourceURL, destination: destinationURL) {
            return destinationURL
        }

        let temporaryURL = helperInstallDirectory
            .appendingPathComponent(".BridgeComputerUse.\(UUID().uuidString).app")
        do {
            try fm.createDirectory(
                at: helperInstallDirectory,
                withIntermediateDirectories: true
            )
            try? fm.removeItem(at: temporaryURL)
            try fm.copyItem(at: sourceURL, to: temporaryURL)

            if fm.fileExists(atPath: socketPath) {
                _ = try? sendSync(DaemonRequestWire(control: "shutdown"), socketPath: socketPath)
                removeRuntimeFiles(socketPath: socketPath)
            }
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            try? fm.removeItem(at: temporaryURL)
            throw ClientError.helperInstallFailed(String(describing: error))
        }
    }

    private nonisolated static var helperInstallDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("app.afk.openbridge", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
    }

    private static func helperInstallNeedsUpdate(source: URL, destination: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue else {
            return true
        }
        guard let sourceDate = helperExecutableModificationDate(source),
              let destinationDate = helperExecutableModificationDate(destination)
        else {
            return true
        }
        return sourceDate > destinationDate
    }

    private static func helperExecutableModificationDate(_ bundleURL: URL) -> Date? {
        let executableURL = bundleURL
            .appendingPathComponent("Contents/MacOS/BridgeComputerUseDaemon")
        let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path)
        return attributes?[.modificationDate] as? Date
    }

    private nonisolated static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private nonisolated static func removeRuntimeFiles(socketPath: String) {
        let socketURL = URL(fileURLWithPath: socketPath)
        try? FileManager.default.removeItem(at: socketURL)
        try? FileManager.default.removeItem(
            at: socketURL.deletingLastPathComponent().appendingPathComponent("daemon.pid")
        )
    }

    // MARK: - Socket path

    private nonisolated static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["CUEBOARD_COMPUTER_USE_RUNTIME_DIR"],
           override.isEmpty == false
        {
            return (override as NSString).appendingPathComponent("daemon.sock")
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("app.afk.openbridge", isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent("daemon.sock")
            .path
    }

    // MARK: - Framed JSON over UNIX socket

    private nonisolated static let maxPayload = 64 * 1024 * 1024

    /// Send/recv timeout for every daemon socket operation. Well above the
    /// expected per-call latency (<100ms for ping, sub-second for actions),
    /// low enough that a silently-hung daemon can't wedge a caller forever.
    /// Insurance; the main protection against main-actor stalls is that the
    /// transport is dispatched to a background queue.
    private nonisolated static let socketTimeoutSeconds: Int = 30

    private nonisolated static func dial(socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw ClientError.transport("socket() errno=\(errno)")
        }

        var timeout = timeval(
            tv_sec: __darwin_time_t(socketTimeoutSeconds),
            tv_usec: 0
        )
        _ = setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        _ = setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxPathLen else {
            close(fd)
            throw ClientError.transport("socket path too long: \(socketPath)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            let typed = buffer.bindMemory(to: CChar.self)
            for (offset, byte) in pathBytes.enumerated() {
                typed[offset] = CChar(bitPattern: byte)
            }
            typed[pathBytes.count] = 0
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, size)
            }
        }
        if result != 0 {
            let code = errno
            close(fd)
            throw ClientError.transport("connect() errno=\(code) path=\(socketPath)")
        }
        return fd
    }

    private nonisolated static func writeFrame(fd: Int32, payload: Data) throws {
        guard payload.count <= maxPayload else {
            throw ClientError.transport("payload too large: \(payload.count)")
        }
        var lengthBE = UInt32(payload.count).bigEndian
        try withUnsafeBytes(of: &lengthBE) { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
        try payload.withUnsafeBytes { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
    }

    private nonisolated static func readFrame(fd: Int32) throws -> Data {
        var header = Data(count: 4)
        try header.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        let length = Int(UInt32(bigEndian: header.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length >= 0, length <= maxPayload else {
            throw ClientError.transport("frame length out of range: \(length)")
        }
        var payload = Data(count: length)
        try payload.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        return payload
    }

    private nonisolated static func writeAll(fd: Int32, bytes: UnsafeRawBufferPointer) throws {
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
            if written == -1, errno == EINTR { continue }
            throw ClientError.transport("write errno=\(errno)")
        }
    }

    private nonisolated static func readAll(fd: Int32, into buffer: UnsafeMutableRawBufferPointer) throws {
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
                throw ClientError.transport("short read: expected=\(buffer.count) got=\(offset)")
            }
            if got == -1, errno == EINTR { continue }
            throw ClientError.transport("read errno=\(errno)")
        }
    }
}

// MARK: - CLI-arg encoding

extension ComputerUseDaemonClient {
    /// Turn an `{action, args}` JSON object into the `[action, --flag, value]`
    /// argv the daemon's CLI parser expects. Booleans collapse to flag-only,
    /// numbers/strings take a trailing value token.
    static func encodeActionArgs(action: String, args: [String: JSONValue]) -> [String] {
        // swiftlint:disable:previous cyclomatic_complexity
        var out: [String] = [action]
        // Stable ordering so failures reproduce deterministically in logs.
        for key in args.keys.sorted() {
            guard let value = args[key] else { continue }
            let flag = "--" + key.replacingOccurrences(of: "_", with: "-")
            switch value {
            case .null:
                continue
            case let .bool(bool):
                if bool { out.append(flag) }
            case let .string(string):
                out.append(flag)
                out.append(string)
            case let .int(int):
                out.append(flag)
                out.append(String(int))
            case let .double(double):
                out.append(flag)
                out.append(String(double))
            case let .array(items):
                for item in items {
                    out.append(flag)
                    out.append(jsonScalarToString(item))
                }
            case .object:
                // Nested objects aren't representable as CLI args — callers
                // must flatten before passing.
                continue
            }
        }
        return out
    }

    private static func jsonScalarToString(_ value: JSONValue) -> String {
        switch value {
        case let .string(s): s
        case let .int(v): String(v)
        case let .double(v): String(v)
        case let .bool(v): v ? "true" : "false"
        case .null: ""
        case .array, .object: ""
        }
    }
}

@MainActor
final class ComputerUseSessionRegistry {
    static let shared = ComputerUseSessionRegistry()

    struct StartToken: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let sessionID: String?
    }

    private struct PendingStart {
        let sessionID: String?
        var isCancelled: Bool
    }

    private let logger = Logger(
        subsystem: Logger.loggingSubsystem,
        category: "ComputerUseSessionRegistry"
    )
    private var pendingStarts: [UUID: PendingStart] = [:]
    private var activeSessionID: String?
    private var activeMode: ComputerUseDaemonClient.Mode?
    private var hasUnscopedActiveSession = false

    private init() {}

    var currentMode: ComputerUseDaemonClient.Mode? {
        activeMode
    }

    func beginStart(sessionID: String?) -> StartToken {
        let token = StartToken(id: UUID(), sessionID: Self.normalizedSessionID(sessionID))
        pendingStarts[token.id] = PendingStart(sessionID: token.sessionID, isCancelled: false)
        return token
    }

    func finishStart(_ token: StartToken) {
        pendingStarts[token.id] = nil
    }

    func shouldContinueStart(_ token: StartToken) -> Bool {
        guard let pending = pendingStarts[token.id],
              pending.sessionID == token.sessionID
        else {
            return false
        }
        return !pending.isCancelled
    }

    func markStarted(_ token: StartToken, mode: ComputerUseDaemonClient.Mode) -> Bool {
        guard shouldContinueStart(token) else {
            finishStart(token)
            return false
        }
        finishStart(token)
        activeMode = mode
        if let sessionID = token.sessionID {
            activeSessionID = sessionID
            hasUnscopedActiveSession = false
        } else {
            activeSessionID = nil
            hasUnscopedActiveSession = true
        }
        return true
    }

    func isActive(_ token: StartToken) -> Bool {
        if let sessionID = token.sessionID {
            return activeSessionID == sessionID
        }
        return hasUnscopedActiveSession
    }

    func noteStopped(sessionID _: String?) {
        activeSessionID = nil
        activeMode = nil
        hasUnscopedActiveSession = false
    }

    func stopIfActive(sessionID: String) async {
        guard let normalizedSessionID = Self.normalizedSessionID(sessionID) else { return }

        var cancelledPendingCount = 0
        for (tokenID, pending) in pendingStarts where pending.sessionID == normalizedSessionID {
            pendingStarts[tokenID] = PendingStart(sessionID: pending.sessionID, isCancelled: true)
            cancelledPendingCount += 1
        }
        if cancelledPendingCount > 0 {
            logger.info(
                "cancelled \(cancelledPendingCount) pending ComputerUse start request(s) for session \(normalizedSessionID, privacy: .public)"
            )
        }

        let shouldStopDaemon = activeSessionID == normalizedSessionID ||
            (activeSessionID == nil && hasUnscopedActiveSession)
        guard shouldStopDaemon else { return }

        activeSessionID = nil
        activeMode = nil
        hasUnscopedActiveSession = false
        do {
            let text = try await ComputerUseDaemonClient.shared.stopSession()
            logger.info(
                "stopped ComputerUse for session \(normalizedSessionID, privacy: .public): \(text, privacy: .public)"
            )
        } catch {
            logger.warning(
                "failed to stop ComputerUse for session \(normalizedSessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func normalizedSessionID(_ sessionID: String?) -> String? {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
