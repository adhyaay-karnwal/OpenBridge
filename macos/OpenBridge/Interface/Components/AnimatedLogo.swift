//
//  AnimationLogo.swift
//
//  Created by CatsJuice on 2026/1/15.
//
import SwiftUI

// MARK: - Custom Shape for SVG Path

private struct AnimatedLogoPath: Shape {
    func path(in rect: CGRect) -> Path {
        // Original SVG viewBox dimensions (derived from path bounds)
        let originalWidth: CGFloat = 46.3748 - 2 + 15 // Add stroke padding
        let originalHeight: CGFloat = 41.5024 - 1.57601 + 4

        // Calculate scale to fit in rect while maintaining aspect ratio
        let scaleX = rect.width / originalWidth
        let scaleY = rect.height / originalHeight
        let scale = min(scaleX, scaleY)

        // Center offset
        let offsetX = (rect.width - originalWidth * scale) / 2
        let offsetY = (rect.height - originalHeight * scale) / 2

        var path = Path()

        /// Transform helper
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        // SVG Path: M2 38.0024 C... (converted to SwiftUI Path)
        path.move(to: point(2, 38.0024))

        path.addCurve(
            to: point(17.8751, 23.5757),
            control1: point(20, 39.5024),
            control2: point(18.5001, 27.0024)
        )

        path.addCurve(
            to: point(19.3751, 9.57581),
            control1: point(17.2501, 20.1489),
            control2: point(16.3751, 15.5759)
        )

        path.addCurve(
            to: point(29.8751, 2.07601),
            control1: point(22.3751, 3.57569),
            control2: point(26.8752, 1.57601)
        )

        path.addCurve(
            to: point(32.8751, 10.0757),
            control1: point(32.8749, 2.57601),
            control2: point(34.3751, 5.57569)
        )

        path.addCurve(
            to: point(24.3751, 18.5757),
            control1: point(31.3751, 14.5757),
            control2: point(24.6318, 18.401)
        )

        path.addCurve(
            to: point(37.8751, 18.0757),
            control1: point(24.1184, 18.7504),
            control2: point(32.8751, 14.504)
        )

        path.addCurve(
            to: point(40.0001, 27.0024),
            control1: point(41.9723, 21.0024),
            control2: point(40.5002, 25.0024)
        )

        path.addCurve(
            to: point(33.5001, 35.0024),
            control1: point(39.5, 29.0024),
            control2: point(37.2562, 32.6549)
        )

        path.addCurve(
            to: point(18.0001, 36.5024),
            control1: point(29.744, 37.35),
            control2: point(19.8183, 41.5024)
        )

        path.addCurve(
            to: point(32.0001, 26.5024),
            control1: point(16.1819, 31.5024),
            control2: point(25.5001, 27.0024)
        )

        path.addCurve(
            to: point(46.3748, 30.0757),
            control1: point(38.5001, 26.0024),
            control2: point(42.2497, 26.1489)
        )

        path.addCurve(
            to: point(45.5, 39.5024),
            control1: point(50.5, 34.0024),
            control2: point(47.3748, 38.0024)
        )

        return path
    }
}

// MARK: - Animation Logo Configuration

struct AnimatedLogoConfig {
    // MARK: - Phase 1: Enter Animation

    var enterDrawFrom: CGFloat = 0
    var enterDrawTo: CGFloat = 0.78
    var enterDrawDuration: Double = 2.0
    var enterDrawCurve: Animation = .easeOut

    var enterMoveFrom: CGFloat = 0
    var enterMoveTo: CGFloat = 0.15
    var enterMoveDuration: Double = 1.45
    var enterMoveCurve: Animation = .easeInOut

    // MARK: - Phase 2: Wait/Delay

    var waitDuration: Double = 1.0

    // MARK: - Phase 3: Exit Animation

    var exitDrawTo: CGFloat = 0
    var exitDrawDuration: Double = 1.0
    var exitDrawCurve: Animation = .easeIn

    var exitMoveTo: CGFloat = 1.2
    var exitMoveDuration: Double = 1.0
    var exitMoveCurve: Animation = .easeIn

    // MARK: - Appearance

    var strokeColor: Color = .primary
    var strokeWidth: CGFloat = 10
    var lineCap: CGLineCap = .round

    // MARK: - Playback Control

    var autoPlay: Bool = true
    var loop: Bool = true
    var loopInterval: Double = 0.5

    // MARK: - Computed: Max duration for phase transitions

    var enterMaxDuration: Double {
        max(enterDrawDuration, enterMoveDuration)
    }

    var exitMaxDuration: Double {
        max(exitDrawDuration, exitMoveDuration)
    }

    var totalAnimationDuration: Double {
        enterMaxDuration + waitDuration + exitMaxDuration
    }

    static let `default` = AnimatedLogoConfig()
}

// MARK: - Animation Logo View

struct AnimatedLogo: View {
    /// Configuration
    var config: AnimatedLogoConfig

    // Animation state
    @State private var drawAmount: CGFloat = 0
    @State private var moveAmount: CGFloat = 0
    @State private var animationPhase: AnimationPhase = .idle
    @State private var loopTimer: Timer?

    enum AnimationPhase {
        case idle
        case entering
        case waiting
        case exiting
        case completed
    }

    // MARK: - Initializer

    /// Initialize with a configuration object
    init(config: AnimatedLogoConfig = .default) {
        self.config = config
    }

    // MARK: - Body

    var body: some View {
        AnimatedLogoPath()
            .trim(from: moveAmount, to: moveAmount + drawAmount)
            .stroke(
                config.strokeColor,
                style: StrokeStyle(
                    lineWidth: config.strokeWidth,
                    lineCap: config.lineCap,
                    lineJoin: .round
                )
            )
            .onAppear {
                if config.autoPlay {
                    Task { @MainActor in
                        startAnimation()
                    }
                } else {
                    // When autoPlay is disabled, show the waiting state directly
                    showWaitingState()
                }
            }
            .onDisappear {
                stopLoop()
            }
    }

    // MARK: - Animation Control

    /// Show the waiting state directly (no animation)
    private func showWaitingState() {
        drawAmount = config.enterDrawTo
        moveAmount = config.enterMoveTo
        animationPhase = .waiting
    }

    /// Start the animation sequence
    @MainActor
    private func startAnimation() {
        // Reset to initial state
        drawAmount = config.enterDrawFrom
        moveAmount = config.enterMoveFrom

        // Phase 1: Enter (draw and move animate independently)
        animationPhase = .entering
        withAnimation(config.enterDrawCurve.speed(1.0 / config.enterDrawDuration)) {
            drawAmount = config.enterDrawTo
        }
        withAnimation(config.enterMoveCurve.speed(1.0 / config.enterMoveDuration)) {
            moveAmount = config.enterMoveTo
        }

        // Phase 2: Wait (scheduled after the longer enter animation completes)
        DispatchQueue.main.asyncAfter(deadline: .now() + config.enterMaxDuration) {
            animationPhase = .waiting

            // If loop is disabled, stop at waiting state
            if !config.loop {
                return
            }
        }

        // Only continue to exit animation if loop is enabled
        guard config.loop else { return }

        // Phase 3: Exit (scheduled after enter + wait)
        let exitDelay = config.enterMaxDuration + config.waitDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay) {
            animationPhase = .exiting
            withAnimation(config.exitDrawCurve.speed(1.0 / config.exitDrawDuration)) {
                drawAmount = config.exitDrawTo
            }
            withAnimation(config.exitMoveCurve.speed(1.0 / config.exitMoveDuration)) {
                moveAmount = config.exitMoveTo
            }
        }

        // Completed (scheduled after all phases)
        let totalDuration = config.totalAnimationDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            animationPhase = .completed

            // Schedule next loop
            scheduleNextLoop()
        }
    }

    /// Schedule the next loop iteration
    private func scheduleNextLoop() {
        loopTimer?.invalidate()
        loopTimer = Timer.scheduledTimer(withTimeInterval: config.loopInterval, repeats: false) { _ in
            Task { @MainActor in
                startAnimation()
            }
        }
    }

    /// Stop the loop
    private func stopLoop() {
        loopTimer?.invalidate()
        loopTimer = nil
    }

    /// Reset animation to initial state
    private func resetAnimation() {
        stopLoop()
        withAnimation(.easeOut(duration: 0.3)) {
            drawAmount = 0
            moveAmount = 0
        }
        animationPhase = .idle
    }
}

// MARK: - Preview

#Preview("Default - Loop") {
    AnimatedLogo()
        .frame(width: 200, height: 100)
        .padding()
}

#Preview("No Loop - Enter Only") {
    // Animation plays once: idle -> entering -> waiting (stops here)
    let config = AnimatedLogoConfig(
        strokeColor: .blue,
        strokeWidth: 8,
        autoPlay: true,
        loop: false
    )
    return AnimatedLogo(config: config)
        .frame(width: 200, height: 100)
        .padding()
}

#Preview("Static - No Animation") {
    // No animation, directly shows the waiting state
    let config = AnimatedLogoConfig(
        strokeColor: .purple,
        strokeWidth: 10,
        autoPlay: false
    )
    return AnimatedLogo(config: config)
        .frame(width: 200, height: 100)
        .padding()
}

#Preview("Full Config") {
    let customConfig = AnimatedLogoConfig(
        enterDrawFrom: 0,
        enterDrawTo: 0.8,
        enterDrawDuration: 0.8,
        enterDrawCurve: .easeOut,
        enterMoveFrom: 0,
        enterMoveTo: 0.1,
        enterMoveDuration: 0.6,
        enterMoveCurve: .easeOut,
        waitDuration: 2.0,
        exitDrawTo: 0,
        exitDrawDuration: 0.6,
        exitDrawCurve: .easeIn,
        exitMoveTo: 1.0,
        exitMoveDuration: 0.8,
        exitMoveCurve: .easeIn,
        strokeColor: .orange,
        strokeWidth: 15,
        lineCap: .round,
        autoPlay: true,
        loop: true,
        loopInterval: 1.5
    )

    return AnimatedLogo(config: customConfig)
        .frame(width: 300, height: 150)
        .padding()
}
