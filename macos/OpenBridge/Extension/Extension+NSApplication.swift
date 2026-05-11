import AppKit

extension NSApplication {
    func restart() {
        // restart caller
        let bundlePath = Bundle.main.bundlePath
        let command = "/bin/sleep 2; /usr/bin/open -a '\(bundlePath)'"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        do {
            try task.run()
        } catch {
            Logger.updater.error("failed to restart app \(error.localizedDescription)")
        }

        // termination fallback if failed to terminate gracefully
        Thread {
            sleep(1)
            assertionFailure("application took too long to terminate")
            exit(0)
        }.start()

        // terminate safely
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.terminateImmediately = true
        } else {
            assertionFailure()
        }
        NSApp.terminate(nil)
    }
}
