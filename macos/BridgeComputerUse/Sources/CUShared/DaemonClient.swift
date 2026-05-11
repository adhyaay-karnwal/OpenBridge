import Darwin
import Foundation

public enum DaemonClient {
    public static func send(_ request: DaemonRequest) throws -> DaemonResponse {
        let fd = try dial(socketPath: DaemonPaths.socketURL.path)
        defer { close(fd) }

        let payload = try DaemonWire.encode(request)
        try DaemonWire.writeFrame(fd: fd, payload: payload)
        let responseData = try DaemonWire.readFrame(fd: fd)
        return try DaemonWire.decode(DaemonResponse.self, from: responseData)
    }

    public static func isDaemonAlive() -> Bool {
        guard FileManager.default.fileExists(atPath: DaemonPaths.socketURL.path) else {
            return false
        }
        do {
            let response = try send(.ping())
            return response.ok
        } catch {
            return false
        }
    }

    /// Retries transient connect failures (ENOENT, ECONNREFUSED) so that
    /// macOS-triggered daemon restarts (e.g. TCC toggle) are invisible to
    /// callers. On exhaust, the last error is rethrown.
    public static func sendWithRetry(
        _ request: DaemonRequest,
        timeout: TimeInterval = 5.0
    ) throws -> DaemonResponse {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var lastError: Error?
        var delay: useconds_t = 40000 // 40ms
        while Date() < deadline {
            do {
                return try send(request)
            } catch let error as DaemonWireError {
                if case let .socketConnect(code, _) = error,
                   code == ENOENT || code == ECONNREFUSED || code == ECONNRESET
                {
                    lastError = error
                    usleep(delay)
                    delay = min(delay &* 2, 250_000)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? DaemonWireError.socketConnect(ETIMEDOUT, path: DaemonPaths.socketURL.path)
    }

    static func dial(socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw DaemonWireError.socketCreate(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxPathLen else {
            close(fd)
            throw DaemonWireError.socketConnect(ENAMETOOLONG, path: socketPath)
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
            throw DaemonWireError.socketConnect(code, path: socketPath)
        }

        return fd
    }
}
