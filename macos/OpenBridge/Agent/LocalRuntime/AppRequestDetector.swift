import Foundation

/// Client-side capabilities that the agent can request by prepending an
/// `<app-request type="…" />` tag to the start of its streaming response.
///
/// Supports app-level capability requests emitted by local agent skills.
enum AppRequestKind: String {
    case location
}

enum AppRequestDetector {
    /// Detect an `<app-request type="…" />` tag at the start of the given
    /// streaming text. Returns the parsed kind, or `nil` if the text does not
    /// begin with a recognized tag.
    static func detect(in text: String) -> AppRequestKind? {
        let pattern = /\s*<app-request\s+type="([^"]+)"\s*\/>/
        guard let match = text.prefixMatch(of: pattern) else {
            return nil
        }
        return AppRequestKind(rawValue: String(match.1))
    }
}
