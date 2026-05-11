import AppKit
import Darwin
import Foundation

public enum DaemonLifecycleError: Error, CustomStringConvertible {
    case alreadyRunning(pid: Int?)
    case notRunning
    case daemonSpawnFailed(String)
    case daemonUnresponsive(Double)
    case bundleNotFound([String])

    public var description: String {
        switch self {
        case let .alreadyRunning(pid):
            if let pid {
                return "daemon is already running (pid=\(pid))"
            }
            return "daemon is already running"
        case .notRunning:
            return "daemon is not running"
        case let .daemonSpawnFailed(message):
            return "daemon failed to start: \(message)"
        case let .daemonUnresponsive(seconds):
            return "daemon did not become responsive within \(String(format: "%.1f", seconds))s"
        case let .bundleNotFound(paths):
            return "OpenBridge Computer Use.app not found; searched: \(paths.joined(separator: ", "))"
        }
    }
}

public enum DaemonLifecycle {
    /// Start the daemon app if it isn't already running.
    public static func start() throws -> String {
        if DaemonClient.isDaemonAlive() {
            throw DaemonLifecycleError.alreadyRunning(pid: readPidFile())
        }
        return try launch()
    }

    /// Idempotent variant used by the CLI dispatch path: no-op if alive,
    /// launch otherwise. Returns the human-readable status message.
    @discardableResult
    public static func startIfNeeded() throws -> String {
        if DaemonClient.isDaemonAlive() {
            return status()
        }
        return try launch()
    }

    /// Tear down the daemon process. Used only by `stop --daemon`; routine
    /// `stop` calls `stopSession()` instead so the daemon stays alive.
    public static func killDaemon() throws -> String {
        guard DaemonClient.isDaemonAlive() else {
            throw DaemonLifecycleError.notRunning
        }

        _ = try? DaemonClient.send(.shutdown())

        let deadline = Date(timeIntervalSinceNow: 5.0)
        while Date() < deadline {
            if DaemonClient.isDaemonAlive() == false {
                return "daemon stopped"
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if let pid = readPidFile(), pid > 0 {
            _ = kill(pid_t(pid), SIGTERM)
        }
        return "daemon stop requested (did not confirm within deadline)"
    }

    public static func status() -> String {
        if DaemonClient.isDaemonAlive() {
            let pid = readPidFile().map { "\($0)" } ?? "unknown"
            return "daemon is running (pid=\(pid))"
        }
        return "daemon is not running"
    }

    /// Resolve OpenBridge Computer Use.app. Callers use this to hand a concrete URL
    /// to PermissionFlow's `suggestedAppURLs`.
    public static func locateBundleURL() throws -> URL {
        let candidates = candidateBundleURLs()
        for url in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        throw DaemonLifecycleError.bundleNotFound(candidates.map(\.path))
    }

    // MARK: - Internal

    private static func launch() throws -> String {
        try DaemonPaths.ensureRuntimeDirectory()
        try? FileManager.default.removeItem(at: DaemonPaths.socketURL)
        try? FileManager.default.removeItem(at: DaemonPaths.pidFileURL)

        let bundleURL = try locateBundleURL()
        try runSynchronously { completion in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            config.createsNewApplicationInstance = false
            config.hides = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
                completion(error)
            }
        }

        let timeout = 5.0
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if DaemonClient.isDaemonAlive() {
                let pid = readPidFile().map { "\($0)" } ?? "unknown"
                return "daemon started (pid=\(pid))"
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw DaemonLifecycleError.daemonUnresponsive(timeout)
    }

    /// Bridges NSWorkspace's async completion into the sync Lifecycle API.
    private static func runSynchronously(
        _ body: (@escaping @Sendable (Error?) -> Void) -> Void
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ErrorBox()
        body { error in
            box.error = error
            semaphore.signal()
        }
        semaphore.wait()
        if let error = box.error {
            throw DaemonLifecycleError.daemonSpawnFailed(String(describing: error))
        }
    }

    private static func candidateBundleURLs() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        if let override = ProcessInfo.processInfo.environment["BRIDGE_COMPUTER_USE_APP_PATH"],
           override.isEmpty == false
        {
            urls.append(URL(fileURLWithPath: override))
        }

        // When running inside OpenBridge.app, the helper ships at
        // OpenBridge.app/Contents/Helpers/OpenBridge Computer Use.app. Prefer that over
        // any globally installed copy so we pick up the co-signed build.
        let mainBundle = Bundle.main.bundleURL
        urls.append(mainBundle.appendingPathComponent("Contents/Helpers/OpenBridge Computer Use.app"))
        urls.append(mainBundle.appendingPathComponent("Contents/Helpers/BridgeComputerUse.app"))

        let home = fm.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent("Applications/OpenBridge Computer Use.app"))
        urls.append(home.appendingPathComponent("Applications/BridgeComputerUse.app"))
        urls.append(URL(fileURLWithPath: "/Applications/OpenBridge Computer Use.app"))
        urls.append(URL(fileURLWithPath: "/Applications/BridgeComputerUse.app"))

        // Developer flow: picks up a freshly-bundled app sitting next to the repo.
        if let repoRoot = findRepoRoot() {
            urls.append(repoRoot.appendingPathComponent(".build/apps/OpenBridge Computer Use.app"))
            urls.append(repoRoot.appendingPathComponent(".build/apps/BridgeComputerUse.app"))
        }

        return urls
    }

    private static func findRepoRoot() -> URL? {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath).standardizedFileURL
        for _ in 0 ..< 8 {
            if fm.fileExists(atPath: cursor.appendingPathComponent("Package.swift").path) {
                return cursor
            }
            if cursor.path == "/" {
                break
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    static func readPidFile() -> Int? {
        guard
            let data = try? Data(contentsOf: DaemonPaths.pidFileURL),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}
