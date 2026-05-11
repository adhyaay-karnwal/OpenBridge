import AppKit
import QuartzCore
import SwiftUI

enum ComposerVoiceWaveformPhase: Sendable {
    case recording
    case transcribing
}

struct ComposerVoiceWaveformBarAnimation: Equatable, Sendable {
    let growthDuration: TimeInterval
    let growthDelay: TimeInterval

    static let `default` = ComposerVoiceWaveformBarAnimation(
        growthDuration: 0.65,
        growthDelay: 0.24
    )
}

private enum ComposerVoiceWaveformMetrics {
    static let height: CGFloat = 32
    static let horizontalPixelsPerSecond: CGFloat = 60

    static let standardVisibleWidth: CGFloat = 580
    static let compactVisibleWidth: CGFloat = 180

    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 3
    static let baselineHeight: CGFloat = 1.08
    static let maxActiveHeightRatio: CGFloat = 0.98
    static let baselineOpacity = 0.2
    static let levelShapingExponent = 0.76

    static let overscanBars = 3

    static let injectedPreviousLevelWeight = 0.38
    static let injectedLiveLevelWeight = 0.62
    static let previewPreviousLevelWeight = 0.30
    static let previewLiveLevelWeight = 0.70

    static var barStepWidth: CGFloat {
        barWidth + barGap
    }

    static func horizontalSpeed(displayScale: CGFloat) -> CGFloat {
        let effectiveScale = max(displayScale, 1)
        return horizontalPixelsPerSecond / effectiveScale
    }

    static func stepDuration(displayScale: CGFloat) -> TimeInterval {
        let horizontalSpeed = horizontalSpeed(displayScale: displayScale)
        guard horizontalSpeed > 0 else { return 0 }
        return TimeInterval(barStepWidth / horizontalSpeed)
    }
}

struct ComposerVoiceWaveformView: View {
    @Environment(\.displayScale) private var displayScale

    let phase: ComposerVoiceWaveformPhase
    let levels: [Double]
    let currentLevel: Double
    let layoutMode: ComposerLayoutMode
    let barAnimation: ComposerVoiceWaveformBarAnimation = .default

    @State private var animator = WaveformAnimator()
    @State private var displayLinkTimestamp: CFTimeInterval = 0

    private var preferredVisibleWidth: CGFloat {
        switch layoutMode {
        case .standard:
            ComposerVoiceWaveformMetrics.standardVisibleWidth
        case .compact:
            ComposerVoiceWaveformMetrics.compactVisibleWidth
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let renderWidth = min(max(geometry.size.width, 0), preferredVisibleWidth)

            Group {
                if phase == .recording {
                    waveformCanvas(renderWidth: renderWidth)
                        .background {
                            DisplayLinkDriver(timestamp: $displayLinkTimestamp)
                        }
                        .onChange(of: displayLinkTimestamp, initial: true) { _, timestamp in
                            animator.tick(
                                at: timestamp > 0 ? timestamp : CACurrentMediaTime(),
                                phase: phase,
                                inputLevels: levels,
                                currentLevel: currentLevel,
                                visibleWidth: renderWidth,
                                displayScale: displayScale
                            )
                        }
                } else {
                    waveformCanvas(renderWidth: renderWidth)
                        .onAppear {
                            updateAnimator(visibleWidth: renderWidth)
                        }
                        .onChange(of: levels, initial: true) { _, _ in
                            updateAnimator(visibleWidth: renderWidth)
                        }
                        .onChange(of: renderWidth) { _, _ in
                            updateAnimator(visibleWidth: renderWidth)
                        }
                        .onChange(of: phase) { _, _ in
                            updateAnimator(visibleWidth: renderWidth)
                        }
                }
            }
        }
        .frame(height: ComposerVoiceWaveformMetrics.height)
        .accessibilityHidden(true)
    }

    private func waveformCanvas(renderWidth: CGFloat) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            animator.render(
                in: context,
                size: size,
                foregroundColor: .primary,
                displayScale: displayScale,
                barAnimation: barAnimation
            )
        }
        .frame(width: renderWidth, height: ComposerVoiceWaveformMetrics.height, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .clipped()
    }

    private func updateAnimator(visibleWidth: CGFloat) {
        animator.tick(
            at: Date().timeIntervalSinceReferenceDate,
            phase: phase,
            inputLevels: levels,
            currentLevel: currentLevel,
            visibleWidth: visibleWidth,
            displayScale: displayScale
        )
    }
}

private struct DisplayLinkDriver: NSViewRepresentable {
    @Binding var timestamp: CFTimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator(timestamp: $timestamp)
    }

    func makeNSView(context: Context) -> DriverView {
        let view = DriverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DriverView, context: Context) {
        context.coordinator.timestamp = $timestamp
        nsView.coordinator = context.coordinator
        nsView.updateDisplayLink()
    }

    static func dismantleNSView(_ nsView: DriverView, coordinator _: Coordinator) {
        nsView.stopDisplayLink()
    }

    final class Coordinator: NSObject {
        var timestamp: Binding<CFTimeInterval>

        init(timestamp: Binding<CFTimeInterval>) {
            self.timestamp = timestamp
        }

        @objc
        func handleDisplayLink(_ sender: CADisplayLink) {
            timestamp.wrappedValue = sender.targetTimestamp > 0 ? sender.targetTimestamp : sender.timestamp
        }
    }

    final class DriverView: NSView {
        weak var coordinator: Coordinator?
        private var displayLink: CADisplayLink?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateDisplayLink()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            updateDisplayLink()
        }

        override func viewDidHide() {
            super.viewDidHide()
            updateDisplayLink()
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            updateDisplayLink()
        }

        func updateDisplayLink() {
            guard window != nil, superview != nil, !isHidden, let coordinator else {
                stopDisplayLink()
                return
            }

            guard displayLink == nil else { return }

            let link = displayLink(target: coordinator, selector: #selector(Coordinator.handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}

private final class WaveformAnimator {
    private struct Bar {
        let level: Double
        let insertedAt: TimeInterval
    }

    private var bars: [Bar] = []

    private var latestLevel = 0.0
    private var phase: ComposerVoiceWaveformPhase = .recording
    private var currentTime: TimeInterval = 0

    private var lastFrameTime: TimeInterval?
    private var elapsedSinceStep: TimeInterval = 0

    private var lastInputCount = 0
    private var bufferBarCount = 0
    private var shiftProgress: CGFloat = 0
    private var previewInsertedAt: TimeInterval?

    func tick(
        at currentTime: TimeInterval,
        phase: ComposerVoiceWaveformPhase,
        inputLevels: [Double],
        currentLevel: Double,
        visibleWidth: CGFloat,
        displayScale: CGFloat
    ) {
        self.currentTime = currentTime
        latestLevel = currentLevel

        let nextVisibleBarCount = Self.visibleBarCount(for: visibleWidth)
        let nextBufferBarCount = max(0, nextVisibleBarCount + ComposerVoiceWaveformMetrics.overscanBars)

        let inputReset = inputLevels.count < lastInputCount
        let widthChanged = nextBufferBarCount != bufferBarCount
        let phaseChanged = phase != self.phase
        let needsSeed = bars.isEmpty || inputReset || widthChanged || (phaseChanged && phase == .recording)

        self.phase = phase
        lastInputCount = inputLevels.count
        bufferBarCount = nextBufferBarCount

        if needsSeed {
            seedBars(from: inputLevels, count: nextBufferBarCount, at: currentTime)
            elapsedSinceStep = 0
            shiftProgress = 0
            lastFrameTime = currentTime
            previewInsertedAt = currentTime
        }

        guard phase == .recording, nextVisibleBarCount > 0 else {
            lastFrameTime = currentTime
            shiftProgress = 0
            previewInsertedAt = nil
            return
        }

        let frameDelta = min(max(currentTime - (lastFrameTime ?? currentTime), 0), 0.048)
        lastFrameTime = currentTime

        let stepDuration = ComposerVoiceWaveformMetrics.stepDuration(displayScale: displayScale)
        guard stepDuration > 0 else {
            shiftProgress = 0
            return
        }

        elapsedSinceStep += frameDelta

        while elapsedSinceStep >= stepDuration {
            elapsedSinceStep -= stepDuration

            let previousLevel = bars.last?.level ?? 0
            let injectedLevel =
                previousLevel * ComposerVoiceWaveformMetrics.injectedPreviousLevelWeight
                    + latestLevel * ComposerVoiceWaveformMetrics.injectedLiveLevelWeight

            appendBar(level: injectedLevel, at: currentTime)
            previewInsertedAt = currentTime
        }

        if previewInsertedAt == nil {
            previewInsertedAt = currentTime
        }

        shiftProgress = CGFloat(elapsedSinceStep / stepDuration)
    }

    func render(
        in context: GraphicsContext,
        size: CGSize,
        foregroundColor: Color,
        displayScale: CGFloat,
        barAnimation: ComposerVoiceWaveformBarAnimation
    ) {
        guard size.width > 0, size.height > 0, bufferBarCount > 0 else { return }

        let effectiveDisplayScale = max(displayScale, 1)
        let barStepWidth = ComposerVoiceWaveformMetrics.barStepWidth
        let baselineHeight = ComposerVoiceWaveformMetrics.baselineHeight
        let centerY = size.height / 2
        let shiftDistance = shiftProgress * barStepWidth
        let overscanWidth = CGFloat(ComposerVoiceWaveformMetrics.overscanBars) * barStepWidth

        var renderedBars = bars
        if phase == .recording {
            let previewLevel =
                (bars.last?.level ?? 0) * ComposerVoiceWaveformMetrics.previewPreviousLevelWeight
                    + latestLevel * ComposerVoiceWaveformMetrics.previewLiveLevelWeight
            renderedBars.append(
                Bar(
                    level: previewLevel,
                    insertedAt: previewInsertedAt ?? currentTime
                )
            )
        }

        var baselinePath = Path()
        var activePath = Path()
        let barCornerSize = CGSize(
            width: ComposerVoiceWaveformMetrics.barWidth / 2,
            height: ComposerVoiceWaveformMetrics.barWidth / 2
        )

        for (index, bar) in renderedBars.enumerated() {
            let rawX = CGFloat(index) * barStepWidth + ComposerVoiceWaveformMetrics.barWidth / 2 - shiftDistance
            guard rawX >= -overscanWidth, rawX <= size.width + overscanWidth else { continue }

            let x = Self.pixelAligned(rawX, scale: effectiveDisplayScale)
            baselinePath.addRoundedRect(
                in: Self.barRect(
                    centerX: x,
                    centerY: centerY,
                    height: baselineHeight,
                    displayScale: effectiveDisplayScale
                ),
                cornerSize: barCornerSize
            )

            let shapedLevel = Self.shapedLevel(from: bar.level)
            let fullHeight =
                baselineHeight
                    + shapedLevel * (size.height - baselineHeight) * ComposerVoiceWaveformMetrics.maxActiveHeightRatio

            guard fullHeight > baselineHeight else { continue }

            let animatedHeight = animatedBarHeight(
                fullHeight: fullHeight,
                insertedAt: bar.insertedAt,
                barAnimation: barAnimation
            )
            guard animatedHeight > baselineHeight else { continue }

            activePath.addRoundedRect(
                in: Self.barRect(
                    centerX: x,
                    centerY: centerY,
                    height: animatedHeight,
                    displayScale: effectiveDisplayScale
                ),
                cornerSize: barCornerSize
            )
        }

        context.fill(
            baselinePath,
            with: .color(
                foregroundColor.opacity(ComposerVoiceWaveformMetrics.baselineOpacity)
            )
        )
        context.fill(activePath, with: .color(foregroundColor))
    }

    private func appendBar(level: Double, at currentTime: TimeInterval) {
        guard bufferBarCount > 0 else { return }

        bars.append(
            Bar(
                level: max(0, min(level, 1)),
                insertedAt: currentTime
            )
        )

        if bars.count > bufferBarCount {
            bars.removeFirst(bars.count - bufferBarCount)
        }
    }

    private func seedBars(from inputLevels: [Double], count: Int, at currentTime: TimeInterval) {
        guard count > 0 else {
            bars.removeAll(keepingCapacity: true)
            return
        }

        let sampledLevels = Self.resampledLevels(from: inputLevels, targetCount: count)

        bars.removeAll(keepingCapacity: true)
        bars.reserveCapacity(count)

        let paddingCount = max(0, count - sampledLevels.count)
        if paddingCount > 0 {
            for _ in 0 ..< paddingCount {
                bars.append(Bar(level: 0, insertedAt: currentTime))
            }
        }

        for level in sampledLevels {
            bars.append(
                Bar(
                    level: max(0, min(level, 1)),
                    insertedAt: currentTime
                )
            )
        }
    }

    private func animatedBarHeight(
        fullHeight: CGFloat,
        insertedAt: TimeInterval,
        barAnimation: ComposerVoiceWaveformBarAnimation
    ) -> CGFloat {
        let baselineHeight = ComposerVoiceWaveformMetrics.baselineHeight
        let progress = growthProgress(insertedAt: insertedAt, barAnimation: barAnimation)
        let startScale = min(1, baselineHeight / fullHeight)
        let scale = startScale + (1 - startScale) * progress
        return fullHeight * scale
    }

    private func growthProgress(
        insertedAt: TimeInterval,
        barAnimation: ComposerVoiceWaveformBarAnimation
    ) -> CGFloat {
        let elapsed = max(0, currentTime - insertedAt - barAnimation.growthDelay)
        guard barAnimation.growthDuration > 0 else { return 1 }

        let normalized = min(elapsed / barAnimation.growthDuration, 1)
        return Self.easeOut(normalized)
    }

    private static func visibleBarCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return max(
            1,
            Int(floor((width + ComposerVoiceWaveformMetrics.barGap) / ComposerVoiceWaveformMetrics.barStepWidth))
        )
    }

    private static func resampledLevels(from inputLevels: [Double], targetCount: Int) -> [Double] {
        guard targetCount > 0, !inputLevels.isEmpty else { return [] }

        if inputLevels.count <= targetCount {
            return inputLevels
        }

        let inputCount = Double(inputLevels.count)
        let outputCount = Double(targetCount)

        return (0 ..< targetCount).map { index in
            let lowerBound = Int(Double(index) * inputCount / outputCount)
            let upperBound = min(Int(Double(index + 1) * inputCount / outputCount), inputLevels.count)

            var peak = 0.0
            for sampleIndex in lowerBound ..< max(lowerBound + 1, upperBound) {
                peak = max(peak, inputLevels[sampleIndex])
            }
            return peak
        }
    }

    private static func shapedLevel(from level: Double) -> CGFloat {
        let clampedLevel = min(max(level, 0), 1)
        return min(pow(CGFloat(clampedLevel), ComposerVoiceWaveformMetrics.levelShapingExponent), 1)
    }

    private static func easeOut(_ progress: TimeInterval) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 3))
    }

    private static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let effectiveScale = max(scale, 1)
        return (value * effectiveScale).rounded() / effectiveScale
    }

    private static func barRect(
        centerX: CGFloat,
        centerY: CGFloat,
        height: CGFloat,
        displayScale: CGFloat
    ) -> CGRect {
        let effectiveScale = max(displayScale, 1)
        let snappedHeight = max(1 / effectiveScale, (height * effectiveScale).rounded() / effectiveScale)
        let originX = pixelAligned(centerX - ComposerVoiceWaveformMetrics.barWidth / 2, scale: effectiveScale)
        let originY = pixelAligned(centerY - snappedHeight / 2, scale: effectiveScale)
        return CGRect(
            x: originX,
            y: originY,
            width: ComposerVoiceWaveformMetrics.barWidth,
            height: snappedHeight
        )
    }
}

private struct ComposerVoiceWaveformPreviewCard: View {
    let title: String
    let content: AnyView

    init(title: String, @ViewBuilder content: () -> some View) {
        self.title = title
        self.content = AnyView(content())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ComposerVoiceWaveformPreviewSimulationView: View {
    @Environment(\.displayScale) private var displayScale

    let layoutMode: ComposerLayoutMode

    @State private var levels = Self.seedLevels()
    @State private var currentLevel = Self.seedLevels().last ?? 0
    @State private var hasStarted = false

    private var previewWidth: CGFloat {
        switch layoutMode {
        case .standard:
            ComposerVoiceWaveformMetrics.standardVisibleWidth
        case .compact:
            ComposerVoiceWaveformMetrics.compactVisibleWidth
        }
    }

    var body: some View {
        ComposerVoiceWaveformView(
            phase: .recording,
            levels: levels,
            currentLevel: currentLevel,
            layoutMode: layoutMode
        )
        .frame(width: previewWidth)
        .task {
            guard !hasStarted else { return }
            hasStarted = true

            var step = levels.count
            let stepDuration = ComposerVoiceWaveformMetrics.stepDuration(displayScale: displayScale)
            var simulatedDuration = TimeInterval(levels.count) * stepDuration
            var lastCommittedSampleTime = simulatedDuration
            var pendingPeak = currentLevel

            while !Task.isCancelled {
                let nextLevel = Self.simulatedLevel(step: step)
                currentLevel = nextLevel
                pendingPeak = max(pendingPeak, nextLevel)
                simulatedDuration += 0.03

                if simulatedDuration - lastCommittedSampleTime >= stepDuration {
                    levels.append(pendingPeak)
                    if levels.count > 240 {
                        levels.removeFirst(levels.count - 240)
                    }
                    lastCommittedSampleTime = simulatedDuration
                    pendingPeak = 0
                }

                step += 1

                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private static func seedLevels() -> [Double] {
        (0 ..< 48).map(simulatedLevel(step:))
    }

    private static func simulatedLevel(step: Int) -> Double {
        let t = Double(step) * 0.14
        let lowBand = (sin(t * 1.1) + 1) * 0.17
        let midBand = (sin(t * 2.7 + 0.8) + 1) * 0.13
        let shimmer = (sin(t * 6.2 + 1.4) + 1) * 0.05
        let pulse = step.isMultiple(of: 17) ? 0.24 : 0
        let value = 0.04 + lowBand + midBand + shimmer + pulse
        return min(max(value, 0.02), 1)
    }
}

private struct ComposerVoiceWaveformPreviewFrozenView: View {
    let phase: ComposerVoiceWaveformPhase
    let layoutMode: ComposerLayoutMode
    let levels: [Double]

    private var previewWidth: CGFloat {
        switch layoutMode {
        case .standard:
            ComposerVoiceWaveformMetrics.standardVisibleWidth
        case .compact:
            ComposerVoiceWaveformMetrics.compactVisibleWidth
        }
    }

    var body: some View {
        ComposerVoiceWaveformView(
            phase: phase,
            levels: levels,
            currentLevel: levels.last ?? 0,
            layoutMode: layoutMode
        )
        .frame(width: previewWidth)
    }
}

#Preview("Composer Voice Waveform") {
    let transcribingSnapshot: [Double] = [
        0.04, 0.08, 0.18, 0.32, 0.22, 0.48, 0.28, 0.14, 0.06, 0.11,
        0.20, 0.36, 0.58, 0.40, 0.24, 0.09, 0.05, 0.15, 0.27, 0.44,
        0.34, 0.19, 0.10, 0.07, 0.16, 0.30, 0.52, 0.41, 0.25, 0.12,
        0.06, 0.10, 0.22, 0.39, 0.60, 0.47, 0.29, 0.13, 0.08, 0.18,
    ]

    VStack(alignment: .leading, spacing: 20) {
        ComposerVoiceWaveformPreviewCard(
            title: "Recording · Standard · Simulated Input"
        ) {
            ComposerVoiceWaveformPreviewSimulationView(layoutMode: .standard)
        }

        ComposerVoiceWaveformPreviewCard(
            title: "Transcribing · Standard"
        ) {
            ComposerVoiceWaveformPreviewFrozenView(
                phase: .transcribing,
                layoutMode: .standard,
                levels: transcribingSnapshot
            )
        }

        ComposerVoiceWaveformPreviewCard(
            title: "Recording · Compact · Simulated Input"
        ) {
            ComposerVoiceWaveformPreviewSimulationView(layoutMode: .compact)
        }
    }
    .padding(24)
    .background(Color(red: 0.14, green: 0.14, blue: 0.15))
    .preferredColorScheme(.dark)
}
