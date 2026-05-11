import AppKit
import Foundation
import NotchKit
import Observation
import SwiftUI

let notchBaseConfiguration = NotchConfiguration(
    screenSelectionPolicy: .builtInFirst,
    fallbackNotchSize: .init(width: 85, height: 31),
    showsFallbackNotchDebugOverlay: false,
    compactContentInsets: .init(top: 0, leading: 8, bottom: 0, trailing: 8),
    expandedPadding: .init(),
    backgroundSpacing: 15,
    topCornerRadiusRatio: 0.5,
    compactCornerRadius: 12,
    notifyingCornerRadius: 14,
    expandedCornerRadius: 32,
    notificationHeightBoost: 4,
    shadowPadding: .init(width: 64, height: 48),
    expandedEntranceBlurRadius: 80,
    expandedExitAnimationDuration: 0.27,
    compactHoverOutset: 3.5,
    notificationScale: .init(width: 1.03, height: 1.06),
    notificationHoldDuration: 0.2,
    collapseAnimationDuration: 0.35,
    animationConfiguration: .init(duration: 0.42, extraBounce: 0),
    compactHoverAnimationConfiguration: .init(
        response: 0.29,
        dampingFraction: 0.79,
        blendDuration: 0.11
    ),
    notificationIntroAnimationConfiguration: .init(
        response: 0.25,
        dampingFraction: 0.5,
        blendDuration: 0.1
    ),
    notificationResetAnimationConfiguration: .init(
        response: 0.35,
        dampingFraction: 0.6,
        blendDuration: 0.1
    ),
    maximumExpandedSize: notchExpandedSurfaceSize,
    minimumExpandedSize: notchExpandedSurfaceSize,
    hapticFeedbackEnabled: true,
    interactionOutset: 4
)

@MainActor
@Observable
final class NotchDebugConfigurationStore {
    struct SpringConfiguration: Codable {
        var response: Double
        var dampingFraction: Double
        var blendDuration: Double
    }

    struct SmoothConfiguration: Codable {
        var duration: Double
        var extraBounce: Double
    }

    struct InsetsConfiguration: Codable {
        var top: Double
        var leading: Double
        var bottom: Double
        var trailing: Double

        init(top: Double, leading: Double, bottom: Double, trailing: Double) {
            self.top = top
            self.leading = leading
            self.bottom = bottom
            self.trailing = trailing
        }

        init(_ insets: EdgeInsets) {
            self.init(
                top: Double(insets.top),
                leading: Double(insets.leading),
                bottom: Double(insets.bottom),
                trailing: Double(insets.trailing)
            )
        }

        var edgeInsets: EdgeInsets {
            .init(
                top: CGFloat(top),
                leading: CGFloat(leading),
                bottom: CGFloat(bottom),
                trailing: CGFloat(trailing)
            )
        }
    }

    struct SizeConfiguration: Codable {
        var width: Double
        var height: Double

        init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        init(_ size: CGSize) {
            self.init(width: Double(size.width), height: Double(size.height))
        }

        var cgSize: CGSize {
            .init(width: CGFloat(width), height: CGFloat(height))
        }
    }

    struct ExportPayload: Codable {
        var screenSelectionPolicy: String
        var fallbackNotchSize: SizeConfiguration
        var showsFallbackNotchDebugOverlay: Bool
        var compactSideWidth: Double
        var expandedSurfaceSize: SizeConfiguration
        var compactContentInsets: InsetsConfiguration
        var expandedPadding: InsetsConfiguration
        var backgroundSpacing: Double
        var topCornerRadiusRatio: Double
        var compactCornerRadius: Double
        var notifyingCornerRadius: Double
        var expandedCornerRadius: Double
        var notificationHeightBoost: Double
        var shadowPadding: SizeConfiguration
        var expandedEntranceBlurRadius: Double
        var expandedExitAnimationDuration: Double
        var compactHoverOutset: Double
        var notificationScale: SizeConfiguration
        var notificationHoldDuration: Double
        var collapseAnimationDuration: Double
        var interactionOutset: Double
        var mainAnimation: SmoothConfiguration
        var compactHoverAnimation: SpringConfiguration
        var notificationIntroAnimation: SpringConfiguration
        var notificationResetAnimation: SpringConfiguration
    }

    static let shared = NotchDebugConfigurationStore()

    private let defaults: ExportPayload

    var screenSelectionPolicy: NotchConfiguration.ScreenSelectionPolicy
    var fallbackNotchWidth: Double
    var fallbackNotchHeight: Double
    var showsFallbackNotchDebugOverlay: Bool
    var compactSideWidth: Double
    var expandedSurfaceWidth: Double
    var expandedSurfaceHeight: Double

    var compactInsetTop: Double
    var compactInsetLeading: Double
    var compactInsetBottom: Double
    var compactInsetTrailing: Double

    var expandedPaddingTop: Double
    var expandedPaddingLeading: Double
    var expandedPaddingBottom: Double
    var expandedPaddingTrailing: Double

    var backgroundSpacing: Double
    var topCornerRadiusRatio: Double
    var compactCornerRadius: Double
    var notifyingCornerRadius: Double
    var expandedCornerRadius: Double
    var notificationHeightBoost: Double
    var shadowPaddingWidth: Double
    var shadowPaddingHeight: Double
    var expandedEntranceBlurRadius: Double
    var expandedExitAnimationDuration: Double
    var compactHoverOutset: Double
    var notificationScaleWidth: Double
    var notificationScaleHeight: Double
    var notificationHoldDuration: Double
    var collapseAnimationDuration: Double
    var interactionOutset: Double

    var mainAnimationDuration: Double
    var mainAnimationExtraBounce: Double

    var compactHoverSpringResponse: Double
    var compactHoverSpringDampingFraction: Double
    var compactHoverSpringBlendDuration: Double

    var notificationIntroSpringResponse: Double
    var notificationIntroSpringDampingFraction: Double
    var notificationIntroSpringBlendDuration: Double

    var notificationResetSpringResponse: Double
    var notificationResetSpringDampingFraction: Double
    var notificationResetSpringBlendDuration: Double

    private init(
        configuration: NotchConfiguration = notchBaseConfiguration,
        compactSideWidth: CGFloat = notchCompactSideWidth,
        expandedSurfaceSize: CGSize = notchExpandedSurfaceSize
    ) {
        let payload = ExportPayload(
            screenSelectionPolicy: Self.string(for: configuration.screenSelectionPolicy),
            fallbackNotchSize: .init(configuration.fallbackNotchSize),
            showsFallbackNotchDebugOverlay: configuration.showsFallbackNotchDebugOverlay,
            compactSideWidth: Double(compactSideWidth),
            expandedSurfaceSize: .init(expandedSurfaceSize),
            compactContentInsets: .init(configuration.compactContentInsets),
            expandedPadding: .init(configuration.expandedPadding),
            backgroundSpacing: Double(configuration.backgroundSpacing),
            topCornerRadiusRatio: Double(configuration.topCornerRadiusRatio),
            compactCornerRadius: Double(configuration.compactCornerRadius),
            notifyingCornerRadius: Double(configuration.notifyingCornerRadius),
            expandedCornerRadius: Double(configuration.expandedCornerRadius),
            notificationHeightBoost: Double(configuration.notificationHeightBoost),
            shadowPadding: .init(configuration.shadowPadding),
            expandedEntranceBlurRadius: Double(configuration.expandedEntranceBlurRadius),
            expandedExitAnimationDuration: configuration.expandedExitAnimationDuration,
            compactHoverOutset: Double(configuration.compactHoverOutset),
            notificationScale: .init(configuration.notificationScale),
            notificationHoldDuration: configuration.notificationHoldDuration,
            collapseAnimationDuration: configuration.collapseAnimationDuration,
            interactionOutset: Double(configuration.interactionOutset),
            mainAnimation: .init(
                duration: configuration.animationConfiguration.duration,
                extraBounce: configuration.animationConfiguration.extraBounce
            ),
            compactHoverAnimation: .init(
                response: configuration.compactHoverAnimationConfiguration.response,
                dampingFraction: configuration.compactHoverAnimationConfiguration.dampingFraction,
                blendDuration: configuration.compactHoverAnimationConfiguration.blendDuration
            ),
            notificationIntroAnimation: .init(
                response: configuration.notificationIntroAnimationConfiguration.response,
                dampingFraction: configuration.notificationIntroAnimationConfiguration.dampingFraction,
                blendDuration: configuration.notificationIntroAnimationConfiguration.blendDuration
            ),
            notificationResetAnimation: .init(
                response: configuration.notificationResetAnimationConfiguration.response,
                dampingFraction: configuration.notificationResetAnimationConfiguration.dampingFraction,
                blendDuration: configuration.notificationResetAnimationConfiguration.blendDuration
            )
        )

        defaults = payload

        screenSelectionPolicy = configuration.screenSelectionPolicy
        fallbackNotchWidth = payload.fallbackNotchSize.width
        fallbackNotchHeight = payload.fallbackNotchSize.height
        showsFallbackNotchDebugOverlay = payload.showsFallbackNotchDebugOverlay
        self.compactSideWidth = payload.compactSideWidth
        expandedSurfaceWidth = payload.expandedSurfaceSize.width
        expandedSurfaceHeight = payload.expandedSurfaceSize.height

        compactInsetTop = payload.compactContentInsets.top
        compactInsetLeading = payload.compactContentInsets.leading
        compactInsetBottom = payload.compactContentInsets.bottom
        compactInsetTrailing = payload.compactContentInsets.trailing

        expandedPaddingTop = payload.expandedPadding.top
        expandedPaddingLeading = payload.expandedPadding.leading
        expandedPaddingBottom = payload.expandedPadding.bottom
        expandedPaddingTrailing = payload.expandedPadding.trailing

        backgroundSpacing = payload.backgroundSpacing
        topCornerRadiusRatio = payload.topCornerRadiusRatio
        compactCornerRadius = payload.compactCornerRadius
        notifyingCornerRadius = payload.notifyingCornerRadius
        expandedCornerRadius = payload.expandedCornerRadius
        notificationHeightBoost = payload.notificationHeightBoost
        shadowPaddingWidth = payload.shadowPadding.width
        shadowPaddingHeight = payload.shadowPadding.height
        expandedEntranceBlurRadius = payload.expandedEntranceBlurRadius
        expandedExitAnimationDuration = payload.expandedExitAnimationDuration
        compactHoverOutset = payload.compactHoverOutset
        notificationScaleWidth = payload.notificationScale.width
        notificationScaleHeight = payload.notificationScale.height
        notificationHoldDuration = payload.notificationHoldDuration
        collapseAnimationDuration = payload.collapseAnimationDuration
        interactionOutset = payload.interactionOutset

        mainAnimationDuration = payload.mainAnimation.duration
        mainAnimationExtraBounce = payload.mainAnimation.extraBounce

        compactHoverSpringResponse = payload.compactHoverAnimation.response
        compactHoverSpringDampingFraction = payload.compactHoverAnimation.dampingFraction
        compactHoverSpringBlendDuration = payload.compactHoverAnimation.blendDuration

        notificationIntroSpringResponse = payload.notificationIntroAnimation.response
        notificationIntroSpringDampingFraction = payload.notificationIntroAnimation.dampingFraction
        notificationIntroSpringBlendDuration = payload.notificationIntroAnimation.blendDuration

        notificationResetSpringResponse = payload.notificationResetAnimation.response
        notificationResetSpringDampingFraction = payload.notificationResetAnimation.dampingFraction
        notificationResetSpringBlendDuration = payload.notificationResetAnimation.blendDuration
    }

    var resolvedCompactSideWidth: CGFloat {
        CGFloat(max(0, compactSideWidth))
    }

    var resolvedExpandedSurfaceSize: CGSize {
        .init(
            width: CGFloat(max(0, expandedSurfaceWidth)),
            height: CGFloat(max(0, expandedSurfaceHeight))
        )
    }

    var configuration: NotchConfiguration {
        NotchConfiguration(
            screenSelectionPolicy: screenSelectionPolicy,
            fallbackNotchSize: .init(width: CGFloat(fallbackNotchWidth), height: CGFloat(fallbackNotchHeight)),
            showsFallbackNotchDebugOverlay: showsFallbackNotchDebugOverlay,
            compactContentInsets: exportPayload.compactContentInsets.edgeInsets,
            expandedPadding: .init(),
            backgroundSpacing: CGFloat(backgroundSpacing),
            topCornerRadiusRatio: CGFloat(topCornerRadiusRatio),
            compactCornerRadius: CGFloat(compactCornerRadius),
            notifyingCornerRadius: CGFloat(notifyingCornerRadius),
            expandedCornerRadius: CGFloat(expandedCornerRadius),
            notificationHeightBoost: CGFloat(notificationHeightBoost),
            shadowPadding: .init(width: CGFloat(shadowPaddingWidth), height: CGFloat(shadowPaddingHeight)),
            expandedEntranceBlurRadius: CGFloat(expandedEntranceBlurRadius),
            expandedExitAnimationDuration: expandedExitAnimationDuration,
            compactHoverOutset: CGFloat(compactHoverOutset),
            notificationScale: .init(width: CGFloat(notificationScaleWidth), height: CGFloat(notificationScaleHeight)),
            notificationHoldDuration: notificationHoldDuration,
            collapseAnimationDuration: collapseAnimationDuration,
            animationConfiguration: .init(
                duration: mainAnimationDuration,
                extraBounce: mainAnimationExtraBounce
            ),
            compactHoverAnimationConfiguration: .init(
                response: compactHoverSpringResponse,
                dampingFraction: compactHoverSpringDampingFraction,
                blendDuration: compactHoverSpringBlendDuration
            ),
            notificationIntroAnimationConfiguration: .init(
                response: notificationIntroSpringResponse,
                dampingFraction: notificationIntroSpringDampingFraction,
                blendDuration: notificationIntroSpringBlendDuration
            ),
            notificationResetAnimationConfiguration: .init(
                response: notificationResetSpringResponse,
                dampingFraction: notificationResetSpringDampingFraction,
                blendDuration: notificationResetSpringBlendDuration
            ),
            maximumExpandedSize: resolvedExpandedSurfaceSize,
            minimumExpandedSize: resolvedExpandedSurfaceSize,
            hapticFeedbackEnabled: notchBaseConfiguration.hapticFeedbackEnabled,
            interactionOutset: CGFloat(interactionOutset)
        )
    }

    var exportString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(exportPayload),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    func reset() {
        screenSelectionPolicy = Self.policy(for: defaults.screenSelectionPolicy)
        fallbackNotchWidth = defaults.fallbackNotchSize.width
        fallbackNotchHeight = defaults.fallbackNotchSize.height
        showsFallbackNotchDebugOverlay = defaults.showsFallbackNotchDebugOverlay
        compactSideWidth = defaults.compactSideWidth
        expandedSurfaceWidth = defaults.expandedSurfaceSize.width
        expandedSurfaceHeight = defaults.expandedSurfaceSize.height

        compactInsetTop = defaults.compactContentInsets.top
        compactInsetLeading = defaults.compactContentInsets.leading
        compactInsetBottom = defaults.compactContentInsets.bottom
        compactInsetTrailing = defaults.compactContentInsets.trailing

        expandedPaddingTop = defaults.expandedPadding.top
        expandedPaddingLeading = defaults.expandedPadding.leading
        expandedPaddingBottom = defaults.expandedPadding.bottom
        expandedPaddingTrailing = defaults.expandedPadding.trailing

        backgroundSpacing = defaults.backgroundSpacing
        topCornerRadiusRatio = defaults.topCornerRadiusRatio
        compactCornerRadius = defaults.compactCornerRadius
        notifyingCornerRadius = defaults.notifyingCornerRadius
        expandedCornerRadius = defaults.expandedCornerRadius
        notificationHeightBoost = defaults.notificationHeightBoost
        shadowPaddingWidth = defaults.shadowPadding.width
        shadowPaddingHeight = defaults.shadowPadding.height
        expandedEntranceBlurRadius = defaults.expandedEntranceBlurRadius
        expandedExitAnimationDuration = defaults.expandedExitAnimationDuration
        compactHoverOutset = defaults.compactHoverOutset
        notificationScaleWidth = defaults.notificationScale.width
        notificationScaleHeight = defaults.notificationScale.height
        notificationHoldDuration = defaults.notificationHoldDuration
        collapseAnimationDuration = defaults.collapseAnimationDuration
        interactionOutset = defaults.interactionOutset

        mainAnimationDuration = defaults.mainAnimation.duration
        mainAnimationExtraBounce = defaults.mainAnimation.extraBounce

        compactHoverSpringResponse = defaults.compactHoverAnimation.response
        compactHoverSpringDampingFraction = defaults.compactHoverAnimation.dampingFraction
        compactHoverSpringBlendDuration = defaults.compactHoverAnimation.blendDuration

        notificationIntroSpringResponse = defaults.notificationIntroAnimation.response
        notificationIntroSpringDampingFraction = defaults.notificationIntroAnimation.dampingFraction
        notificationIntroSpringBlendDuration = defaults.notificationIntroAnimation.blendDuration

        notificationResetSpringResponse = defaults.notificationResetAnimation.response
        notificationResetSpringDampingFraction = defaults.notificationResetAnimation.dampingFraction
        notificationResetSpringBlendDuration = defaults.notificationResetAnimation.blendDuration
    }

    @discardableResult
    func copyExportToPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(exportString, forType: .string)
    }

    private var exportPayload: ExportPayload {
        ExportPayload(
            screenSelectionPolicy: Self.string(for: screenSelectionPolicy),
            fallbackNotchSize: .init(width: fallbackNotchWidth, height: fallbackNotchHeight),
            showsFallbackNotchDebugOverlay: showsFallbackNotchDebugOverlay,
            compactSideWidth: compactSideWidth,
            expandedSurfaceSize: .init(width: expandedSurfaceWidth, height: expandedSurfaceHeight),
            compactContentInsets: .init(
                top: compactInsetTop,
                leading: compactInsetLeading,
                bottom: compactInsetBottom,
                trailing: compactInsetTrailing
            ),
            expandedPadding: .init(
                top: expandedPaddingTop,
                leading: expandedPaddingLeading,
                bottom: expandedPaddingBottom,
                trailing: expandedPaddingTrailing
            ),
            backgroundSpacing: backgroundSpacing,
            topCornerRadiusRatio: topCornerRadiusRatio,
            compactCornerRadius: compactCornerRadius,
            notifyingCornerRadius: notifyingCornerRadius,
            expandedCornerRadius: expandedCornerRadius,
            notificationHeightBoost: notificationHeightBoost,
            shadowPadding: .init(width: shadowPaddingWidth, height: shadowPaddingHeight),
            expandedEntranceBlurRadius: expandedEntranceBlurRadius,
            expandedExitAnimationDuration: expandedExitAnimationDuration,
            compactHoverOutset: compactHoverOutset,
            notificationScale: .init(width: notificationScaleWidth, height: notificationScaleHeight),
            notificationHoldDuration: notificationHoldDuration,
            collapseAnimationDuration: collapseAnimationDuration,
            interactionOutset: interactionOutset,
            mainAnimation: .init(duration: mainAnimationDuration, extraBounce: mainAnimationExtraBounce),
            compactHoverAnimation: .init(
                response: compactHoverSpringResponse,
                dampingFraction: compactHoverSpringDampingFraction,
                blendDuration: compactHoverSpringBlendDuration
            ),
            notificationIntroAnimation: .init(
                response: notificationIntroSpringResponse,
                dampingFraction: notificationIntroSpringDampingFraction,
                blendDuration: notificationIntroSpringBlendDuration
            ),
            notificationResetAnimation: .init(
                response: notificationResetSpringResponse,
                dampingFraction: notificationResetSpringDampingFraction,
                blendDuration: notificationResetSpringBlendDuration
            )
        )
    }

    private static func string(for policy: NotchConfiguration.ScreenSelectionPolicy) -> String {
        switch policy {
        case .builtInFirst:
            "builtInFirst"
        case .screenUnderPointer:
            "screenUnderPointer"
        case .mainScreen:
            "mainScreen"
        }
    }

    private static func policy(for rawValue: String) -> NotchConfiguration.ScreenSelectionPolicy {
        switch rawValue {
        case "screenUnderPointer":
            .screenUnderPointer
        case "mainScreen":
            .mainScreen
        default:
            .builtInFirst
        }
    }
}
