import Darwin
import Dispatch
import Foundation

/// Hook the daemon process injects to handle action / session requests.
/// `DaemonServer` only knows how to read framed JSON, parse the envelope,
/// and respond with `DaemonResponse`. Everything mode-specific (session
/// lifecycle, action dispatch) is fulfilled by the host through this
/// protocol so neither layer has to depend on the other's symbols.
@MainActor
public protocol DaemonRequestHandler: AnyObject {
    func handle(action args: [String]) async -> DaemonResponse
    func handle(session control: SessionControl) async -> DaemonResponse
    func sessionStatusJSON() -> String
    func helpText(for mode: ModeKind) -> String?
    /// Return a JSON-encoded `PermissionStatusReport`. Hosts decode and
    /// surface the statuses so the user sees missing TCC grants before
    /// approving a session start.
    func permissionsStatusJSON() -> String
    /// Pop the unified authorization UI (PermissionFlow). Non-blocking:
    /// the window is opened by the daemon's AppKit main actor and the
    /// caller returns immediately; callers poll `permissionsStatusJSON`
    /// afterwards to watch grants land.
    func openPermissionFlow() -> String
}

/// Unix-domain-socket listener. Runs on the main dispatch queue so that
/// request handlers can call into @MainActor code (AppKit overlay + AX APIs)
/// without hopping threads.
@MainActor
public final class DaemonServer {
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var shutdownHandler: (@MainActor () -> Void)?
    private weak var handler: DaemonRequestHandler?

    public init(handler: DaemonRequestHandler) {
        self.handler = handler
    }

    public func start(onShutdown: @escaping @MainActor () -> Void) throws {
        try DaemonPaths.ensureRuntimeDirectory()
        let socketPath = DaemonPaths.socketURL.path

        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw DaemonWireError.socketCreate(errno)
        }
        listenFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxPath else {
            close(fd)
            throw DaemonWireError.socketBind(ENAMETOOLONG, path: socketPath)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            let typed = buffer.bindMemory(to: CChar.self)
            for (offset, byte) in pathBytes.enumerated() {
                typed[offset] = CChar(bitPattern: byte)
            }
            typed[pathBytes.count] = 0
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, size)
            }
        }
        if bindResult != 0 {
            let code = errno
            close(fd)
            throw DaemonWireError.socketBind(code, path: socketPath)
        }

        _ = chmod(socketPath, 0o600)

        if listen(fd, 8) != 0 {
            let code = errno
            close(fd)
            throw DaemonWireError.socketListen(code)
        }

        shutdownHandler = onShutdown
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.acceptIncoming()
            }
        }
        source.resume()
        listenSource = source

        writePidFile()
    }

    public func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(at: DaemonPaths.socketURL)
        try? FileManager.default.removeItem(at: DaemonPaths.pidFileURL)
    }

    @MainActor
    private func acceptIncoming() {
        var addr = sockaddr_un()
        var length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.accept(listenFD, sockaddrPtr, &length)
            }
        }
        guard clientFD >= 0 else {
            return
        }

        // Hand off to a Task so async handlers (mode runtimes) can do their
        // work without blocking the accept loop. The Task owns the FD
        // lifetime.
        Task { @MainActor [weak self] in
            defer { close(clientFD) }

            let response: DaemonResponse
            do {
                let payload = try DaemonWire.readFrame(fd: clientFD)
                let request = try DaemonWire.decode(DaemonRequest.self, from: payload)
                response = await (self?.handle(request: request) ?? .failure("server torn down"))
            } catch {
                response = .failure("\(error)")
            }

            do {
                let data = try DaemonWire.encode(response)
                try DaemonWire.writeFrame(fd: clientFD, payload: data)
            } catch {
                // best-effort; client will see EOF and treat as failure
            }
        }
    }

    @MainActor
    private func handle(request: DaemonRequest) async -> DaemonResponse {
        if let control = request.control {
            switch control {
            case "ping":
                return .success("pong")
            case "shutdown":
                let handler = shutdownHandler
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        handler?()
                    }
                }
                return .success("shutting down")
            case "session-status":
                guard let handler else { return .failure("no request handler installed") }
                return .success(handler.sessionStatusJSON())
            case "mode-help":
                guard let mode = request.mode else {
                    return .failure("mode-help: missing mode")
                }
                guard let handler else { return .failure("no request handler installed") }
                if let text = handler.helpText(for: mode) {
                    return .success(text)
                }
                return .failure("mode-help: no help registered for mode=\(mode.rawValue)")
            case "permissions-status":
                guard let handler else { return .failure("no request handler installed") }
                return .success(handler.permissionsStatusJSON())
            case "open-permission-flow":
                guard let handler else { return .failure("no request handler installed") }
                return .success(handler.openPermissionFlow())
            default:
                return .failure("unknown control: \(control)")
            }
        }

        if let session = request.session {
            guard let handler else { return .failure("no request handler installed") }
            return await handler.handle(session: session)
        }

        guard let args = request.args else {
            return .failure("request missing args")
        }
        guard let handler else { return .failure("no request handler installed") }
        return await handler.handle(action: args)
    }

    private func writePidFile() {
        let pid = getpid()
        let data = "\(pid)\n".data(using: .utf8)
        try? data?.write(to: DaemonPaths.pidFileURL, options: .atomic)
    }
}
