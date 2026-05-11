import Darwin
import Dispatch
import Foundation
import OSLog

/// OpenBridge-side UNIX-domain socket server that the daemon's
/// `BridgeObserverSummaryService` connects to for observer summary
/// requests.
///
/// Why this exists: the daemon helper runs as a separate process and
/// does not have the user's app settings or local agent context.
/// Instead of shipping credentials across, OpenBridge hosts the LLM call
/// itself via the local observer executor.
/// in-app AI call, so the local agent flow and model choice stay consistent
/// with the rest
/// of the product.
///
/// Wire format is the same 4-byte big-endian length + UTF-8 JSON
/// framing the daemon's own socket uses. One request per connection.
@MainActor
final class ObserverBridgeServer {
    static let shared = ObserverBridgeServer()

    private let logger = Logger(subsystem: "app.afk.openbridge", category: "ObserverBridgeServer")

    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var started = false

    private init() {}

    /// Start listening at the shared socket path (same directory as
    /// `daemon.sock`). Idempotent: calling after `start` is a no-op.
    func start() {
        guard !started else { return }
        do {
            try startListener()
            started = true
            logger.info("observer bridge server listening at \(Self.socketPath, privacy: .public)")
        } catch {
            logger.error("observer bridge server failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        started = false
    }

    static var currentSocketPath: String {
        socketPath
    }

    // MARK: - Listener

    private func startListener() throws {
        try ensureRuntimeDirectory()
        let path = Self.socketPath

        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw ObserverServerError.io("socket() errno=\(errno)")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < maxPath else {
            close(fd)
            throw ObserverServerError.io("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            let typed = buffer.bindMemory(to: CChar.self)
            for (offset, byte) in pathBytes.enumerated() {
                typed[offset] = CChar(bitPattern: byte)
            }
            typed[pathBytes.count] = 0
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, size)
            }
        }
        if bindResult != 0 {
            let code = errno
            close(fd)
            throw ObserverServerError.io("bind() errno=\(code) path=\(path)")
        }
        chmod(path, 0o600)
        if Darwin.listen(fd, 16) != 0 {
            let code = errno
            close(fd)
            throw ObserverServerError.io("listen() errno=\(code)")
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.acceptPending()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        listenSource = source
    }

    private func acceptPending() {
        let fd = listenFD
        guard fd >= 0 else { return }
        let clientFD = Darwin.accept(fd, nil, nil)
        if clientFD < 0 {
            if errno != EAGAIN, errno != EWOULDBLOCK {
                logger.error("accept() errno=\(errno)")
            }
            return
        }
        // Hand off to a background queue — reading/writing on the
        // accept queue (main) would block the app's event loop while
        // The local observer executor returns a lightweight summary.
        DispatchQueue.global(qos: .userInitiated).async {
            Self.handleClient(fd: clientFD)
        }
    }

    // MARK: - Per-client (nonisolated — runs on bg queue)

    private nonisolated static func handleClient(fd: Int32) {
        defer { close(fd) }
        let response: ObserverResponseWire
        do {
            let payload = try readFrame(fd: fd)
            let request = try JSONDecoder().decode(ObserverRequestWire.self, from: payload)
            let text = try runOnMainActor { @MainActor in
                try await ObserverBridgeExecutor.execute(request)
            }
            response = ObserverResponseWire(ok: true, text: text, error: nil)
        } catch {
            let message = String(describing: error)
            response = ObserverResponseWire(ok: false, text: nil, error: message)
        }
        if let data = try? JSONEncoder().encode(response) {
            try? writeFrame(fd: fd, payload: data)
        }
    }

    /// Synchronously bridge a background-thread caller back to the
    /// MainActor so MainActor-isolated APIs.
    /// `SettingsManager`) can run. Returns after the main-actor Task
    /// completes; `try await` inside the closure propagates errors.
    private nonisolated static func runOnMainActor<R: Sendable>(
        _ body: @escaping @Sendable @MainActor () async throws -> R
    ) throws -> R {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<R>()
        Task { @MainActor in
            do {
                try await box.set(.success(body()))
            } catch {
                box.set(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        switch box.value {
        case let .success(value): return value
        case let .failure(err): throw err
        case .none:
            throw ObserverServerError.io("main-actor bridge returned no result")
        }
    }

    // MARK: - Paths

    private static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["CUEBOARD_COMPUTER_USE_RUNTIME_DIR"],
           !override.isEmpty
        {
            return (override as NSString).appendingPathComponent("observer.sock")
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("app.afk.openbridge", isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent("observer.sock")
            .path
    }

    private func ensureRuntimeDirectory() throws {
        let dir = (Self.socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Framed JSON helpers

    nonisolated static let maxPayload = 64 * 1024 * 1024

    private nonisolated static func readFrame(fd: Int32) throws -> Data {
        var header = Data(count: 4)
        try header.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        let length = Int(UInt32(bigEndian: header.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length >= 0, length <= maxPayload else {
            throw ObserverServerError.io("frame length out of range: \(length)")
        }
        var payload = Data(count: length)
        try payload.withUnsafeMutableBytes { buffer in
            try readAll(fd: fd, into: buffer)
        }
        return payload
    }

    private nonisolated static func writeFrame(fd: Int32, payload: Data) throws {
        guard payload.count <= maxPayload else {
            throw ObserverServerError.io("payload too large: \(payload.count)")
        }
        var lengthBE = UInt32(payload.count).bigEndian
        try withUnsafeBytes(of: &lengthBE) { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
        try payload.withUnsafeBytes { buffer in
            try writeAll(fd: fd, bytes: buffer)
        }
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
            throw ObserverServerError.io("write errno=\(errno)")
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
                throw ObserverServerError.io("short read: expected=\(buffer.count) got=\(offset)")
            }
            if got == -1, errno == EINTR { continue }
            throw ObserverServerError.io("read errno=\(errno)")
        }
    }
}

enum ObserverServerError: Error, CustomStringConvertible {
    case io(String)

    var description: String {
        switch self {
        case let .io(msg): msg
        }
    }
}

/// Thread-safe one-shot result holder for `runOnMainActor`. Avoids the
/// "captured var" warning when using a plain `Result` local in a
/// closure; the semaphore guarantees the read happens-after the write.
private final nonisolated class ResultBox<Value>: @unchecked Sendable {
    private(set) var value: Result<Value, Error>?
    func set(_ v: Result<Value, Error>) {
        value = v
    }
}

// MARK: - Wire types (mirror `CUShared.ObserverBridgeRequest`)

nonisolated struct ObserverRequestWire: Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case round, final }
    nonisolated struct TimelineEntry: Codable, Sendable {
        nonisolated enum EntryType: String, Codable, Sendable { case summary, capture }
        let type: EntryType
        let timestampMs: Double
        let text: String?
        let frameBase64: String?
        let frameMimeType: String?
        let displayIndex: Int
        let sequence: Int
    }

    let kind: Kind
    let roundIndex: Int
    let sessionStartedAt: Double
    let timeline: [TimelineEntry]
}

nonisolated struct ObserverResponseWire: Codable, Sendable {
    let ok: Bool
    let text: String?
    let error: String?
}
