import AppKit
import Darwin
import Foundation

/// Daemon process entry point. Blocks until shutdown.
public enum DaemonMain {
    /// `handler` fulfils action and session-control requests.
    /// `cleanup` runs on shutdown (signal or `shutdown` control message)
    /// before the server tears down its socket.
    public static func run(
        handler: @MainActor () -> DaemonRequestHandler,
        cleanup: @escaping @MainActor @Sendable () -> Void = {}
    ) -> Never {
        installSignalHandlers()
        _ = Darwin.setsid()

        MainActor.assumeIsolated {
            runOnMain(handler: handler(), cleanup: cleanup)
        }

        exit(0)
    }

    @MainActor
    private static func runOnMain(
        handler: DaemonRequestHandler,
        cleanup: @escaping @MainActor @Sendable () -> Void
    ) {
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)

        let server = DaemonServer(handler: handler)

        do {
            try server.start {
                cleanup()
                server.stop()
                exit(0)
            }
        } catch {
            fputs("[daemon] failed to start server: \(error)\n", stderr)
            exit(1)
        }

        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler {
            MainActor.assumeIsolated {
                cleanup()
                server.stop()
                exit(0)
            }
        }
        term.resume()

        let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        int.setEventHandler {
            MainActor.assumeIsolated {
                cleanup()
                server.stop()
                exit(0)
            }
        }
        int.resume()

        app.run()
    }

    private static func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        // Ignore default SIGTERM/SIGINT so that dispatch sources can handle them.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
    }
}
