import CUShared
import Foundation

// MARK: - Help text

let usage = """
usage:
  ComputerUse start --mode <foreground|background> [mode-specific flags…]
  ComputerUse stop                 # end the active session; daemon keeps running
  ComputerUse stop --daemon        # stop the active session AND terminate the daemon
  ComputerUse status               # daemon + active mode info (JSON)
  ComputerUse permissions [status] # open authorization window / report TCC
  ComputerUse recover [--discard]  # restore apps hidden by a crashed foreground session
  ComputerUse <action> [flags…]    # action forwarded to the active session

start --mode foreground options:
  --display <N>                    target display (defaults to main)
  [apps…]                          trailing positional names of apps to keep visible
                                   (all other apps are hidden, restored on stop)

start --mode background options:
  (none)

actions are mode-specific — run `ComputerUse <action> --help` after `start`
to see the active mode's full action list.
"""

// MARK: - Argument parsing

let arguments = Array(CommandLine.arguments.dropFirst())

guard let first = arguments.first else {
    fputs("\(usage)\n", stderr)
    exit(1)
}

switch first {
case "--help", "-h":
    print(usage)
    exit(0)

case "start":
    handleStart(args: Array(arguments.dropFirst()))

case "stop":
    handleStop(args: Array(arguments.dropFirst()))

case "status":
    handleStatus()

case "recover":
    handleRecover(args: Array(arguments.dropFirst()))

default:
    handleAction(args: arguments)
}

// MARK: - Subcommand handlers

func handleStart(args: [String]) {
    guard let mode = parseMode(from: args) else {
        fputs("[ERROR] start: missing or invalid --mode <foreground|background>\n", stderr)
        exit(1)
    }

    let session: SessionControl
    switch mode {
    case .foreground:
        let parsed = parseForegroundStart(args: args)
        session = SessionControl(op: .start, mode: .foreground, foreground: parsed)
    case .background:
        session = SessionControl(op: .start, mode: .background, background: BackgroundStartArgs())
    }

    do {
        try ensureDaemonRunning()
        let response = try DaemonClient.sendWithRetry(DaemonRequest(session: session))
        emit(response)
    } catch {
        fputs("[ERROR] \(error)\n", stderr)
        exit(1)
    }
}

func handleStop(args: [String]) {
    let killDaemon = args.contains("--daemon")

    do {
        if DaemonClient.isDaemonAlive() {
            // Always end the session first so overlays / app isolation are
            // restored even when the user is also asking to terminate the
            // daemon process. Print the response text but do NOT exit yet
            // if we still need to kill the daemon process below.
            let stopResp = try DaemonClient.send(.stopSession())
            if stopResp.ok {
                if let text = stopResp.text, text.isEmpty == false {
                    print(text)
                }
            } else {
                fputs("[ERROR] \(stopResp.error ?? "stop failed")\n", stderr)
                if killDaemon == false {
                    exit(1)
                }
            }
        } else if killDaemon == false {
            print("daemon is not running; nothing to stop")
            exit(0)
        }

        if killDaemon {
            let killResp = try DaemonLifecycle.killDaemon()
            print(killResp)
        }
        exit(0)
    } catch {
        fputs("[ERROR] \(error)\n", stderr)
        exit(1)
    }
}

func handleStatus() {
    if DaemonClient.isDaemonAlive() == false {
        print(#"{"daemon":"stopped"}"#)
        exit(0)
    }
    do {
        let response = try DaemonClient.send(.sessionStatus())
        emit(response)
    } catch {
        fputs("[ERROR] \(error)\n", stderr)
        exit(1)
    }
}

func handleRecover(args: [String]) {
    guard AppIsolationRecovery.hasSnapshot() else {
        print("no orphan snapshot present")
        exit(0)
    }
    if args.contains("--discard") {
        AppIsolationRecovery.discardSnapshot()
        print("discarded orphan snapshot")
        exit(0)
    }
    let summary = MainActor.assumeIsolated {
        AppIsolationRecovery.applyRecovery()
    }
    print(summary)
    exit(0)
}

func handleAction(args: [String]) {
    do {
        try ensureDaemonRunning()
        let response = try DaemonClient.sendWithRetry(.action(args))
        emit(response)
    } catch {
        fputs("[ERROR] \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Helpers

func ensureDaemonRunning() throws {
    if DaemonClient.isDaemonAlive() == false {
        _ = try DaemonLifecycle.startIfNeeded()
    }
}

func emit(_ response: DaemonResponse) {
    if response.ok {
        if let text = response.text, text.isEmpty == false {
            print(text)
        }
        exit(0)
    } else {
        fputs("[ERROR] \(response.error ?? "unknown error")\n", stderr)
        exit(1)
    }
}

func parseMode(from args: [String]) -> ModeKind? {
    guard let index = args.firstIndex(of: "--mode") else { return nil }
    let valueIndex = args.index(after: index)
    guard valueIndex < args.endIndex else { return nil }
    return ModeKind(rawValue: args[valueIndex])
}

func parseForegroundStart(args: [String]) -> ForegroundStartArgs {
    var display: Int?
    var apps: [String] = []

    var iterator = args.makeIterator()
    while let token = iterator.next() {
        switch token {
        case "--mode":
            _ = iterator.next() // already consumed by parseMode
        case "--display":
            if let raw = iterator.next(), let value = Int(raw) {
                display = value
            }
        case "--help", "-h":
            // Help is handled per-mode at the daemon, but we surface a
            // local hint so an agent can discover the shape without the
            // daemon running.
            print("""
            ComputerUse start --mode foreground [--display N] [apps…]

            apps        trailing positional list. Whatever you list stays
                        visible; everything else is hidden until `stop`
                        restores them.
            --display N target display (defaults to main).
            """)
            exit(0)
        default:
            // Anything else is treated as a trailing app name positional.
            apps.append(token)
        }
    }

    return ForegroundStartArgs(apps: apps, display: display)
}
