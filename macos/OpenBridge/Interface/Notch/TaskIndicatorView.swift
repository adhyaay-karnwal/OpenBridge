import SwiftUI

struct NotchActivityLeadingSlotView: View {
    let state: NotchViewModel.CompactState
    let availableWidth: CGFloat

    var body: some View {
        content
            .frame(width: availableWidth, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case let .running(text, _):
            HStack(spacing: 10) {
                AnimatedLogo(config: runningLogoConfig)
                    .frame(width: 20, height: 18)

                ThinkingHighlightText(
                    text: text,
                    font: .system(size: 12, weight: .semibold, design: .rounded),
                    baseColor: .white.opacity(0.58),
                    highlightColor: .white.opacity(0.98)
                )
            }
        case .alert:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "F2A23D"))
        case let .status(type, _):
            statusIcon(for: type)
        }
    }

    @ViewBuilder
    private func statusIcon(for type: TaskViewModel.LiveInfoType) -> some View {
        switch type {
        case .running:
            AnimatedLogo(config: runningLogoConfig)
                .frame(width: 18, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
        case .others:
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var runningLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .white
        config.strokeWidth = 1.4
        config.enterDrawDuration = 1.2
        config.enterMoveDuration = 1.2
        config.waitDuration = 0.3
        config.exitDrawDuration = 0.75
        config.exitMoveDuration = 0.75
        config.loopInterval = 0.15
        return config
    }
}

struct NotchActivityTrailingSlotView: View {
    let count: Int
    let availableWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            RollingNumberText(number: count)
        }
        .frame(width: availableWidth, alignment: .trailing)
    }
}

private struct RollingNumberText: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .monospacedDigit()
            .fixedSize()
            .id(number)
            .transition(.asymmetric(
                insertion: .blurFromBottom,
                removal: .blurToTop
            ))
            .animation(.spring(duration: 0.35), value: number)
    }
}

private struct BlurTransitionModifier: ViewModifier {
    let blur: CGFloat
    let offsetY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .offset(y: offsetY)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var blurToTop: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(blur: 4, offsetY: -12, opacity: 0),
            identity: BlurTransitionModifier(blur: 0, offsetY: 0, opacity: 1)
        )
    }

    static var blurFromBottom: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(blur: 4, offsetY: 12, opacity: 0),
            identity: BlurTransitionModifier(blur: 0, offsetY: 0, opacity: 1)
        )
    }
}
