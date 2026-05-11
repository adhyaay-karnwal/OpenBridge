import SwiftUI

enum ChatMainWindowHeaderMetrics {
    static let actionInset: CGFloat = 12
    static let buttonHeight: CGFloat = 36
    static let backdropVisibleHeight = actionInset + buttonHeight
    static let leadingMaskFadeWidth: CGFloat = 20
}

private enum ChatMainWindowBackdropStyle {
    static let mask = BackdropBlurMaskStyle(
        heightMultiplier: 1,
        topOffsetMultiplier: 0,
        layers: [
            .init(transitionPoint: 0.78, blurRadius: 1),
            .init(transitionPoint: 0.54, blurRadius: 3),
            .init(transitionPoint: 0.28, blurRadius: 8),
            .init(transitionPoint: 0.00, blurRadius: 20),
        ]
    )
}

struct ChatMainWindowTopBackdrop: View {
    let height: CGFloat
    let showsMask: Bool

    private var visibleMaskHeight: CGFloat {
        ChatMainWindowHeaderMetrics.backdropVisibleHeight
    }

    private var backdropHeight: CGFloat {
        max(height, ChatMainWindowBackdropStyle.mask.height(for: visibleMaskHeight))
    }

    var body: some View {
        if height > 0 {
            ZStack(alignment: .top) {
                if showsMask {
                    BackdropBlurMaskView(
                        baseSize: visibleMaskHeight,
                        style: ChatMainWindowBackdropStyle.mask
                    )
                    .mask {
                        ChatMainWindowLeadingMaskFade(
                            fadeWidth: ChatMainWindowHeaderMetrics.leadingMaskFadeWidth
                        )
                    }
                    .offset(y: -height)
                }

                ChatMainWindowDragArea(height: height)
                    .offset(y: -height)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: backdropHeight,
                alignment: .top
            )
            .accessibilityHidden(true)
        }
    }
}

private struct ChatMainWindowLeadingMaskFade: View {
    let fadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let resolvedWidth = max(proxy.size.width, 0)
            let resolvedFadeWidth = min(fadeWidth, resolvedWidth)
            let fadeEnd = resolvedWidth > 0 ? resolvedFadeWidth / resolvedWidth : 1

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: fadeEnd),
                    .init(color: .white, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
