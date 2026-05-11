//
//  ActiveCommandBadge.swift
//  ComposerEditor
//

import AppKit

/// Configuration for an active command badge displayed inside the composer.
public struct ActiveCommandBadge {
    public let icon: NSImage?
    public let name: String
    public let subtitle: String?
    public let onDismiss: () -> Void
    public let badgeAccessibilityID: String?
    public let dismissAccessibilityID: String?

    public init(
        icon: NSImage? = nil,
        name: String,
        subtitle: String? = nil,
        onDismiss: @escaping () -> Void,
        badgeAccessibilityID: String? = nil,
        dismissAccessibilityID: String? = nil
    ) {
        self.icon = icon
        self.name = name
        self.subtitle = subtitle
        self.onDismiss = onDismiss
        self.badgeAccessibilityID = badgeAccessibilityID
        self.dismissAccessibilityID = dismissAccessibilityID
    }
}
