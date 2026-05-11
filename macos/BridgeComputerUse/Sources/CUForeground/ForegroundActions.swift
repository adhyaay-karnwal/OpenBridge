import Foundation

/// Action set exposed by `start --mode foreground`. Slim port — enough to
/// exercise the architecture end-to-end (cursor animation + colorful
/// border + CGEvent posts). Per the plan, additional foreground-only
/// actions (mouse-down/up, hold-key, drag, zoom, focus, list-applications,
/// list-windows, thinking, log) land in follow-up steps once the legacy
/// runtime port (WindowManager, DimmedWorkspaceManager, HUD, Observer,
/// InterventionDetector, RecoveryMonitor, SystemCursorHider) is complete.
public enum ForegroundCommand: Equatable {
    case click(x: Double, y: Double, button: MouseButton, count: Int)
    case mouseDown(x: Double, y: Double, button: MouseButton)
    case mouseUp(x: Double, y: Double, button: MouseButton)
    case mouseMove(x: Double, y: Double)
    case drag(fromX: Double, fromY: Double, toX: Double, toY: Double, button: MouseButton)
    case typeText(text: String)
    case pressKey(combo: String)
    case holdKey(combo: String, seconds: Double)
    case scroll(x: Double, y: Double, direction: ScrollDirection, amount: Int)
    case wait(seconds: Double)
    case screenshot
    case screenSize
    case cursorPosition
    case listApplications
    case listWindows
    case focus(app: String)
    case zoom(x1: Double, y1: Double, x2: Double, y2: Double)
    case thinking(text: String)

    public enum MouseButton: String, Equatable, Sendable {
        case left, right, middle
    }

    public enum ScrollDirection: String, Equatable, Sendable {
        case up, down, left, right
    }
}

public enum ForegroundCLIError: Error, CustomStringConvertible, Equatable {
    case helpRequested(String)
    case missingSubcommand
    case unknownSubcommand(String)
    case missingValue(String)
    case invalidValue(flag: String, value: String)

    public var description: String {
        switch self {
        case let .helpRequested(text):
            text
        case .missingSubcommand:
            "missing action; pass --help to list available actions"
        case let .unknownSubcommand(cmd):
            "unknown action: \(cmd)"
        case let .missingValue(flag):
            "missing value for \(flag)"
        case let .invalidValue(flag, value):
            "invalid value for \(flag): \(value)"
        }
    }
}
