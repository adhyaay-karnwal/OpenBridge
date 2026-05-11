import SwiftUI

public enum WindowNotificationDisplayMode: Sendable {
    case collapsed
    case expanded
}

public struct WindowNotificationCardContext {
    public let index: Int
    public let displayMode: WindowNotificationDisplayMode
    public let canDismiss: Bool

    private let dismissAction: (() -> Void)?
    private let automaticExpansionSuspensionAction: ((Bool) -> Void)?

    public init(
        index: Int,
        displayMode: WindowNotificationDisplayMode,
        canDismiss: Bool = false,
        dismissAction: (() -> Void)? = nil,
        automaticExpansionSuspensionAction: ((Bool) -> Void)? = nil
    ) {
        self.index = index
        self.displayMode = displayMode
        self.canDismiss = canDismiss
        self.dismissAction = dismissAction
        self.automaticExpansionSuspensionAction = automaticExpansionSuspensionAction
    }

    public var isFrontmost: Bool {
        index == 0
    }

    public var isExpanded: Bool {
        displayMode == .expanded
    }

    public func dismiss() {
        dismissAction?()
    }

    public func setAutomaticExpansionSuspended(_ isSuspended: Bool) {
        automaticExpansionSuspensionAction?(isSuspended)
    }
}

public struct WindowNotificationStackConfiguration {
    public enum ExpansionBehavior: String, CaseIterable, Sendable {
        case hover
        case collapsed
        case expanded
    }

    public var expansionBehavior: ExpansionBehavior
    public var expandsOnHover: Bool
    public var maximumWidth: CGFloat
    public var maximumExpandedCards: Int?
    public var maximumCollapsedCards: Int
    public var allowsExpandedScrolling: Bool
    public var hoverExpansionDelay: Duration
    public var collapsedPeek: CGFloat
    public var collapsedScaleStep: CGFloat
    public var minimumCollapsedScale: CGFloat
    public var collapsedMaskOverflowInsets: EdgeInsets
    public var contentBottomInset: CGFloat
    public var expandedSpacing: CGFloat
    public var offset: CGSize
    public var overlayInsets: EdgeInsets
    public var animation: Animation

    public init(
        expansionBehavior: ExpansionBehavior = .hover,
        expandsOnHover: Bool = true,
        maximumWidth: CGFloat = 420,
        maximumExpandedCards: Int? = nil,
        maximumCollapsedCards: Int = 4,
        allowsExpandedScrolling: Bool = true,
        hoverExpansionDelay: Duration = .milliseconds(50),
        collapsedPeek: CGFloat = 14,
        collapsedScaleStep: CGFloat = 0.05,
        minimumCollapsedScale: CGFloat = 0.84,
        collapsedMaskOverflowInsets: EdgeInsets = EdgeInsets(top: 18, leading: 28, bottom: 26, trailing: 28),
        contentBottomInset: CGFloat = 18,
        expandedSpacing: CGFloat = 12,
        offset: CGSize = .zero,
        overlayInsets: EdgeInsets = EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20),
        animation: Animation = .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)
    ) {
        self.expansionBehavior = expansionBehavior
        self.expandsOnHover = expandsOnHover
        self.maximumWidth = maximumWidth
        self.maximumExpandedCards = maximumExpandedCards
        self.maximumCollapsedCards = maximumCollapsedCards
        self.allowsExpandedScrolling = allowsExpandedScrolling
        self.hoverExpansionDelay = hoverExpansionDelay
        self.collapsedPeek = collapsedPeek
        self.collapsedScaleStep = collapsedScaleStep
        self.minimumCollapsedScale = minimumCollapsedScale
        self.collapsedMaskOverflowInsets = collapsedMaskOverflowInsets
        self.contentBottomInset = contentBottomInset
        self.expandedSpacing = expandedSpacing
        self.offset = offset
        self.overlayInsets = overlayInsets
        self.animation = animation
    }

    public static var sonner: Self {
        Self()
    }
}
