import Foundation

enum LocalEnvironmentPermissionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`
    case fullAccess

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .default:
            String(localized: "Default permission")
        case .fullAccess:
            String(localized: "Full Access")
        }
    }

    var systemImage: String {
        switch self {
        case .default:
            "hand.raised"
        case .fullAccess:
            "exclamationmark.shield"
        }
    }
}
