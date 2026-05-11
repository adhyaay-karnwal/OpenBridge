import Foundation

struct BridgeAutomationRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

struct BridgeAutomationWindowSummary: Codable {
    let window: String
    let title: String
    let isVisible: Bool
    let frame: BridgeAutomationRect
    let scale: Double
    let kind: String
    let windowNumber: Int
}

struct BridgeAutomationWindowListPayload: Codable {
    let windows: [BridgeAutomationWindowSummary]
    let notch: BridgeAutomationWindowSummary?
    let transient: [BridgeAutomationWindowSummary]
}

struct BridgeAutomationCaptureResult: Codable {
    let window: String
    let path: String
    let width: Int
    let height: Int
    let scale: Double
    let frame: BridgeAutomationRect
}

struct BridgeAutomationPointClickResult: Codable {
    let window: String
    let x: Double
    let y: Double
    let performed: Bool
    let route: String
    let elementId: String?
}

struct BridgeAutomationScrollResult: Codable {
    let window: String
    let x: Double
    let y: Double
    let deltaX: Double
    let deltaY: Double
    let performed: Bool
    let route: String
}

struct BridgeAutomationTypeResult: Codable {
    let window: String
    let textLength: Int
    let performed: Bool
    let route: String
}

struct BridgeAutomationPressKeyResult: Codable {
    let window: String
    let key: String
    let modifiers: [String]
    let performed: Bool
    let route: String
}

struct BridgeAutomationChatAttachmentResult: Codable {
    let window: String
    let path: String
    let filename: String
    let contentType: String?
    let attachmentType: String
    let performed: Bool
    let route: String
}

struct BridgeAutomationChatSendResult: Codable {
    let window: String
    let textLength: Int
    let performed: Bool
    let route: String
}

struct BridgeAutomationFilePickerSelectResult: Codable {
    let pathCount: Int
    let performed: Bool
    let route: String
    let requestMessage: String?
    let paths: [String]
}

struct BridgeAutomationFilePickerCancelResult: Codable {
    let performed: Bool
    let route: String
    let requestMessage: String?
}

extension Windows.Kind {
    init?(automationName: String) {
        switch automationName {
        case "chat":
            self = .chat
        case "backgroundTasks":
            self = .backgroundTasks
        case "settings":
            self = .settings
        default:
            return nil
        }
    }

    var automationName: String {
        switch self {
        case .chat:
            "chat"
        case .backgroundTasks:
            "backgroundTasks"
        case .settings:
            "settings"
        }
    }

    static var automationNames: [String] {
        allCases.map(\.automationName)
    }
}
