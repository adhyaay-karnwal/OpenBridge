import Foundation

/// Configuration for a draft quote row displayed above the composer input.
public struct DraftQuoteBadge {
    public let text: String
    public let onActivate: () -> Void
    public let onDismiss: () -> Void
    public let badgeAccessibilityID: String?
    public let dismissAccessibilityID: String?

    public init(
        text: String,
        onActivate: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        badgeAccessibilityID: String? = nil,
        dismissAccessibilityID: String? = nil
    ) {
        self.text = text
        self.onActivate = onActivate
        self.onDismiss = onDismiss
        self.badgeAccessibilityID = badgeAccessibilityID
        self.dismissAccessibilityID = dismissAccessibilityID
    }
}
