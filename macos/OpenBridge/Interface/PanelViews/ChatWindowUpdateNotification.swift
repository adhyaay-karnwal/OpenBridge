import AppKit
import SwiftUI
import WindowNotificationKit

@MainActor
final class ChatWindowNotificationController {
    static let shared = ChatWindowNotificationController()

    let center = WindowNotificationCenter()

    private let installableUpdateNotificationID = UUID(uuidString: "94C42D70-C1D7-4D5B-8380-941A3F8ED6A1")!
    private let debugUpdateNotificationID = UUID(uuidString: "6A18A182-88A8-4E56-A105-A6B0E29C5BA3")!

    private init() {}

    func presentInstallableUpdateNotification(
        onInstall: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        center.present(id: installableUpdateNotificationID) { context in
            ChatWindowUpdateNotificationCard(
                title: String(localized: "A new version is available."),
                actionTitle: String(localized: "Install update"),
                context: context,
                onAction: onInstall,
                onClose: onDismiss
            )
        }

        NotchCenter.shared.presentNotification(
            id: installableUpdateNotificationID.uuidString,
            symbolName: "arrow.down.circle.fill",
            tint: Color(hex: "F3A03B"),
            title: String(localized: "A new version is available."),
            message: String(localized: "Install the latest update from the notch."),
            actionTitle: String(localized: "Install update"),
            action: { [weak self] in
                onInstall()
                self?.dismissInstallableUpdateNotification(syncNotch: false)
            },
            onDismiss: { [weak self] in
                onDismiss()
                self?.dismissInstallableUpdateNotification(syncNotch: false)
            }
        )
    }

    func dismissInstallableUpdateNotification() {
        dismissInstallableUpdateNotification(syncNotch: true)
    }

    private func dismissInstallableUpdateNotification(syncNotch: Bool) {
        center.dismiss(installableUpdateNotificationID)
        if syncNotch {
            NotchCenter.shared.dismissNotification(id: installableUpdateNotificationID.uuidString)
        }
    }

    func presentDebugUpdateNotification(onInstall: @escaping () -> Void) {
        center.present(id: debugUpdateNotificationID) { [weak self] context in
            ChatWindowUpdateNotificationCard(
                title: String(localized: "A new version is available."),
                actionTitle: String(localized: "Install update"),
                context: context,
                onAction: {
                    onInstall()
                    self?.dismissDebugUpdateNotification()
                },
                onClose: { [weak self] in
                    self?.dismissDebugUpdateNotification()
                }
            )
        }

        NotchCenter.shared.presentNotification(
            id: debugUpdateNotificationID.uuidString,
            symbolName: "ladybug.fill",
            tint: Color(hex: "F3A03B"),
            title: String(localized: "A new debug build is available."),
            message: String(localized: "Install the latest debug update from the notch."),
            actionTitle: String(localized: "Install update"),
            action: { [weak self] in
                onInstall()
                self?.dismissDebugUpdateNotification(syncNotch: false)
            },
            onDismiss: { [weak self] in
                self?.dismissDebugUpdateNotification(syncNotch: false)
            }
        )
    }

    func dismissDebugUpdateNotification() {
        dismissDebugUpdateNotification(syncNotch: true)
    }

    private func dismissDebugUpdateNotification(syncNotch: Bool) {
        center.dismiss(debugUpdateNotificationID)
        if syncNotch {
            NotchCenter.shared.dismissNotification(id: debugUpdateNotificationID.uuidString)
        }
    }
}

private enum ChatWindowUpdateNotificationStyle {
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let interItemSpacing: CGFloat = 18
    static let controlSpacing: CGFloat = 8
    static let actionCornerRadius: CGFloat = 8
    static let actionHeight: CGFloat = 22
    static let actionHorizontalPadding: CGFloat = 8
    static let actionHoverAnimationDuration: TimeInterval = 0.18
    static let actionHDRExposure: CGFloat = 4.2
    static let actionFillColor = Color(hex: "F3A03B")
    static let actionForegroundColor = Color.white

    static func tintColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color(hex: "F3A03B").opacity(0.35)
        default: Color(hex: "FFD6A0").opacity(0.33)
        }
    }

    static func actionStrokeColor(isHovered: Bool, for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.34 : 0.2)
        }

        return Color.white.opacity(isHovered ? 0.26 : 0.14)
    }

    static func actionShadowColor(isHovered: Bool, for colorScheme: ColorScheme) -> Color {
        let opacity = if colorScheme == .dark {
            isHovered ? 0.5 : 0.22
        } else {
            isHovered ? 0.34 : 0.14
        }

        return actionFillColor.opacity(opacity)
    }

    static func actionTextShadowColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color.black.opacity(0.24)
        default: Color(hex: "FFFFFF").opacity(0.46)
        }
    }

    static func strokeColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color.white.opacity(0.1)
        default: Color.black.opacity(0.08)
        }
    }

    static func shadowColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color.black.opacity(0.16)
        default: Color.black.opacity(0.08)
        }
    }

    static func titleColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color.white.opacity(0.96)
        default: Color.black.opacity(0.82)
        }
    }

    static func closeColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark: Color.white.opacity(0.9)
        default: Color.black.opacity(0.62)
        }
    }
}

private struct ChatWindowUpdateNotificationCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let title: String
    let actionTitle: String
    let context: WindowNotificationCardContext
    let onAction: () -> Void
    let onClose: () -> Void

    private let backgroundShape = RoundedRectangle(
        cornerRadius: ChatWindowUpdateNotificationStyle.cornerRadius,
        style: .continuous
    )

    var body: some View {
        HStack(spacing: ChatWindowUpdateNotificationStyle.interItemSpacing) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ChatWindowUpdateNotificationStyle.titleColor(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ChatWindowUpdateNotificationStyle.controlSpacing) {
                ChatWindowUpdateNotificationActionButton(
                    title: actionTitle,
                    isHighlighted: isHovered,
                    action: onAction
                )

                if context.canDismiss {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ChatWindowUpdateNotificationStyle.closeColor(for: colorScheme))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, ChatWindowUpdateNotificationStyle.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .safeGlassEffect(
            .ultraThick.tint(ChatWindowUpdateNotificationStyle.tintColor(for: colorScheme)),
            in: backgroundShape
        )
        .overlay {
            backgroundShape
                .strokeBorder(ChatWindowUpdateNotificationStyle.strokeColor(for: colorScheme))
                .allowsHitTesting(false)
        }
        .overlay {
            ChatWindowUpdateNotificationHoverTracker(isHovered: $isHovered)
                .accessibilityHidden(true)
        }
        .shadow(
            color: ChatWindowUpdateNotificationStyle.shadowColor(for: colorScheme),
            radius: 16,
            x: 0,
            y: 8
        )
        .onDisappear {
            isHovered = false
        }
    }
}

private struct ChatWindowUpdateNotificationHoverTracker: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context _: Context) -> ChatWindowUpdateNotificationHoverTrackingView {
        let view = ChatWindowUpdateNotificationHoverTrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ChatWindowUpdateNotificationHoverTrackingView, context _: Context) {
        configure(nsView)
        nsView.refreshHoverState()
    }

    private func configure(_ nsView: ChatWindowUpdateNotificationHoverTrackingView) {
        let isHovered = _isHovered
        nsView.onHoverChange = { hovering in
            guard isHovered.wrappedValue != hovering else { return }
            isHovered.wrappedValue = hovering
        }
    }
}

private final class ChatWindowUpdateNotificationHoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            onHoverChange?(isHovered)
        }
    }

    override func layout() {
        super.layout()
        refreshHoverState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        refreshHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        refreshHoverState()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    func refreshHoverState() {
        guard let window else {
            isHovered = false
            return
        }

        let locationInWindow = window.mouseLocationOutsideOfEventStream
        let locationInView = convert(locationInWindow, from: nil)
        isHovered = bounds.contains(locationInView)
    }
}

private struct ChatWindowUpdateNotificationActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isHighlighted: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(
        cornerRadius: ChatWindowUpdateNotificationStyle.actionCornerRadius,
        style: .continuous
    )

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isHighlighted ? hdrTextColor : ChatWindowUpdateNotificationStyle.actionForegroundColor)
                .lineLimit(1)
                .shadow(
                    color: isHighlighted
                        ? hdrTextColor.opacity(0.32)
                        : ChatWindowUpdateNotificationStyle.actionTextShadowColor(for: colorScheme),
                    radius: isHighlighted ? 4 : 1,
                    x: 0,
                    y: isHighlighted ? 0 : 1
                )
                .padding(.horizontal, ChatWindowUpdateNotificationStyle.actionHorizontalPadding)
                .frame(height: ChatWindowUpdateNotificationStyle.actionHeight)
                .background {
                    shape
                        .fill(ChatWindowUpdateNotificationStyle.actionFillColor)
                        .overlay {
                            if #available(macOS 15.0, *) {
                                ChatWindowUpdateNotificationMeshHighlight(
                                    isActive: isHighlighted,
                                    cornerRadius: ChatWindowUpdateNotificationStyle.actionCornerRadius,
                                    baseColor: ChatWindowUpdateNotificationStyle.actionFillColor
                                )
                            } else {
                                shape
                                    .fill(hdrHighlightColor)
                                    .blendMode(.plusLighter)
                                    .opacity(isHighlighted ? 1 : 0)
                            }
                        }
                        .overlay {
                            shape.strokeBorder(
                                ChatWindowUpdateNotificationStyle.actionStrokeColor(
                                    isHovered: isHighlighted,
                                    for: colorScheme
                                )
                            )
                        }
                }
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .allowedDynamicRange(preferredDynamicRange)
        .shadow(
            color: ChatWindowUpdateNotificationStyle.actionShadowColor(
                isHovered: isHighlighted,
                for: colorScheme
            ),
            radius: isHighlighted ? 14 : 8,
            x: 0,
            y: isHighlighted ? 6 : 4
        )
        .animation(.easeInOut(duration: ChatWindowUpdateNotificationStyle.actionHoverAnimationDuration), value: isHighlighted)
    }

    private var preferredDynamicRange: Image.DynamicRange? {
        if #available(macOS 26.0, *), NSApp?.applicationShouldSuppressHighDynamicRangeContent == true {
            return .standard
        }

        return .high
    }

    private var hdrHighlightColor: Color {
        hdrColor(
            fallback: ChatWindowUpdateNotificationStyle.actionFillColor,
            red: 243.0 / 255.0,
            green: 160.0 / 255.0,
            blue: 59.0 / 255.0,
            exposure: ChatWindowUpdateNotificationStyle.actionHDRExposure
        )
    }

    private var hdrTextColor: Color {
        hdrColor(
            fallback: .white,
            red: 1,
            green: 1,
            blue: 1,
            exposure: 4.8
        )
    }

    private func hdrColor(
        fallback: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        exposure: CGFloat
    ) -> Color {
        guard #available(macOS 26.0, *), NSApp?.applicationShouldSuppressHighDynamicRangeContent != true else {
            return fallback
        }

        return Color(
            nsColor: NSColor(
                red: red,
                green: green,
                blue: blue,
                alpha: 1,
                linearExposure: exposure
            )
        )
    }
}

@available(macOS 15.0, *)
private struct ChatWindowUpdateNotificationMeshHighlight: View {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool
    let cornerRadius: CGFloat
    let baseColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate * 1.5

            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(at: time),
                colors: meshColors(at: time),
                background: baseColor,
                smoothsColors: true,
                colorSpace: .device
            )
            .scaleEffect(1.16)
            .saturation(colorScheme == .dark ? 1.1 : 1.02)
            .opacity(isActive ? (colorScheme == .dark ? 1 : 0.88) : 0)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                style: FillStyle(antialiased: true)
            )
            .allowedDynamicRange(preferredDynamicRange)
        }
        .allowsHitTesting(false)
    }

    private var preferredDynamicRange: Image.DynamicRange? {
        if #available(macOS 26.0, *), NSApp?.applicationShouldSuppressHighDynamicRangeContent == true {
            return .standard
        }

        return .high
    }

    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        [
            point(0, 0),
            point(
                0.5 + drift(time, frequency: 0.88, phase: 0.2, amplitude: 0.055),
                0.03 + drift(time, frequency: 1.26, phase: 1.4, amplitude: 0.025)
            ),
            point(1, 0),
            point(
                0.03 + drift(time, frequency: 1.02, phase: 2.2, amplitude: 0.03),
                0.5 + drift(time, frequency: 1.14, phase: 0.8, amplitude: 0.07)
            ),
            point(
                0.5 + drift(time, frequency: 0.96, phase: 1.7, amplitude: 0.095),
                0.5 + drift(time, frequency: 1.21, phase: 2.9, amplitude: 0.12)
            ),
            point(
                0.97 + drift(time, frequency: 1.08, phase: 3.8, amplitude: 0.03),
                0.46 + drift(time, frequency: 1.24, phase: 1.9, amplitude: 0.07)
            ),
            point(0, 1),
            point(
                0.52 + drift(time, frequency: 0.82, phase: 4.7, amplitude: 0.06),
                0.97 + drift(time, frequency: 1.01, phase: 0.6, amplitude: 0.025)
            ),
            point(1, 1),
        ]
    }

    private func meshColors(at time: TimeInterval) -> [Color] {
        if colorScheme == .dark {
            return darkMeshColors(at: time)
        }

        return lightMeshColors(at: time)
    }

    private func darkMeshColors(at time: TimeInterval) -> [Color] {
        let centerPulse = pulse(time, frequency: 2.1, phase: 0.7)
        let edgePulse = pulse(time, frequency: 2.8, phase: 2.6)
        let amberPulse = pulse(time, frequency: 2.4, phase: 1.3)
        let emberPulse = pulse(time, frequency: 1.9, phase: 4.4)
        let centerExposure = 2.1 + (centerPulse * 2.8)
        let edgeExposure = 1.15 + (edgePulse * 2.0)

        return [
            warmColor(
                red: 0.66 + (emberPulse * 0.09),
                green: 0.28 + (emberPulse * 0.1),
                blue: 0.07 + (emberPulse * 0.03)
            ),
            warmColor(
                red: 0.82 + (amberPulse * 0.14),
                green: 0.44 + (amberPulse * 0.16),
                blue: 0.12 + (amberPulse * 0.05)
            ),
            warmColor(
                red: 0.72 + (emberPulse * 0.1),
                green: 0.34 + (emberPulse * 0.11),
                blue: 0.08 + (emberPulse * 0.04)
            ),
            warmColor(
                red: 0.76 + (amberPulse * 0.12),
                green: 0.37 + (amberPulse * 0.13),
                blue: 0.1 + (amberPulse * 0.04)
            ),
            warmColor(
                red: 243.0 / 255.0,
                green: 160.0 / 255.0,
                blue: 59.0 / 255.0,
                exposure: centerExposure
            ),
            warmColor(
                red: 0.86 + (amberPulse * 0.12),
                green: 0.53 + (amberPulse * 0.15),
                blue: 0.16 + (amberPulse * 0.07)
            ),
            warmColor(
                red: 0.62 + (emberPulse * 0.08),
                green: 0.26 + (emberPulse * 0.08),
                blue: 0.06 + (emberPulse * 0.03)
            ),
            warmColor(
                red: 0.74 + (amberPulse * 0.11),
                green: 0.38 + (amberPulse * 0.14),
                blue: 0.1 + (amberPulse * 0.04)
            ),
            warmColor(
                red: 0.95 + (edgePulse * 0.05),
                green: 0.66 + (edgePulse * 0.12),
                blue: 0.22 + (edgePulse * 0.08),
                exposure: edgeExposure
            ),
        ]
    }

    private func lightMeshColors(at time: TimeInterval) -> [Color] {
        let centerPulse = pulse(time, frequency: 2.1, phase: 0.7)
        let edgePulse = pulse(time, frequency: 2.8, phase: 2.6)
        let amberPulse = pulse(time, frequency: 2.4, phase: 1.3)
        let emberPulse = pulse(time, frequency: 1.9, phase: 4.4)
        let centerExposure = 1.4 + (centerPulse * 1.8)
        let edgeExposure = 1.0 + (edgePulse * 0.9)

        return [
            warmColor(
                red: 255.0 / 255.0 + (emberPulse * 0.05),
                green: 201.0 / 255.0 + (emberPulse * 0.06),
                blue: 76.0 / 255.0 + (emberPulse * 0.03)
            ),
            warmColor(
                red: 255.0 / 255.0 + (amberPulse * 0.06),
                green: 231.0 / 255.0 + (amberPulse * 0.09),
                blue: 181.0 / 255.0 + (amberPulse * 0.05)
            ),
            warmColor(
                red: 255.0 / 255.0 + (emberPulse * 0.05),
                green: 178.0 / 255.0 + (emberPulse * 0.07),
                blue: 0.0 / 255.0 + (emberPulse * 0.03)
            ),
            warmColor(
                red: 255.0 / 255.0 + (amberPulse * 0.06),
                green: 218.0 / 255.0 + (amberPulse * 0.08),
                blue: 9.0 / 255.0 + (amberPulse * 0.04)
            ),
            warmColor(
                red: 243.0 / 255.0,
                green: 160.0 / 255.0,
                blue: 59.0 / 255.0,
                exposure: centerExposure
            ),
            warmColor(
                red: 0.95 + (amberPulse * 0.04),
                green: 0.71 + (amberPulse * 0.08),
                blue: 0.25 + (amberPulse * 0.05)
            ),
            warmColor(
                red: 255.0 / 255.0 + (emberPulse * 0.05),
                green: 218.0 / 255.0 + (emberPulse * 0.06),
                blue: 0.0 / 255.0 + (emberPulse * 0.03),
                exposure: edgeExposure
            ),
            warmColor(
                red: 0.89 + (amberPulse * 0.06),
                green: 0.56 + (amberPulse * 0.08),
                blue: 0.17 + (amberPulse * 0.04)
            ),
            warmColor(
                red: 0.97 + (edgePulse * 0.03),
                green: 0.74 + (edgePulse * 0.08),
                blue: 0.28 + (edgePulse * 0.05),
                exposure: edgeExposure
            ),
        ]
    }

    private func point(_ x: Double, _ y: Double) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(min(max(x, 0), 1)),
            Float(min(max(y, 0), 1))
        )
    }

    private func drift(
        _ time: TimeInterval,
        frequency: Double,
        phase: Double,
        amplitude: Double
    ) -> Double {
        let primary = sin((time * frequency) + phase) * amplitude
        let secondary = sin((time * frequency * 1.73) + (phase * 1.37)) * amplitude * 0.42
        return primary + secondary
    }

    private func pulse(
        _ time: TimeInterval,
        frequency: Double,
        phase: Double
    ) -> CGFloat {
        CGFloat((sin((time * frequency) + phase) * 0.5) + 0.5)
    }

    private func warmColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        exposure: CGFloat = 1
    ) -> Color {
        let fallback = Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )

        guard exposure > 1 else {
            return fallback
        }

        guard #available(macOS 26.0, *), NSApp?.applicationShouldSuppressHighDynamicRangeContent != true else {
            return fallback
        }

        return Color(
            nsColor: NSColor(
                red: red,
                green: green,
                blue: blue,
                alpha: 1,
                linearExposure: exposure
            )
        )
    }
}

#Preview("Chat Update Notification") {
    ChatWindowUpdateNotificationPreviewScene()
        .frame(width: 760, height: 340)
        .padding(24)
}

#Preview("Chat Update Notification Light") {
    ChatWindowUpdateNotificationPreviewScene()
        .frame(width: 760, height: 340)
        .padding(24)
        .preferredColorScheme(.light)
}

private struct ChatWindowUpdateNotificationPreviewScene: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(windowFillColor)

            VStack(spacing: 0) {
                previewHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ChatWindowUpdateNotificationCard(
                    title: "A new version is available.",
                    actionTitle: "Install update",
                    context: WindowNotificationCardContext(
                        index: 0,
                        displayMode: .collapsed,
                        canDismiss: true
                    ),
                    onAction: {},
                    onClose: {}
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(contentPlaceholderColor)
                    .frame(height: 120)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
                .allowsHitTesting(false)
        }
    }

    private var windowFillColor: Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.08, green: 0.08, blue: 0.09)
        default:
            Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    private var contentPlaceholderColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.08)
        }
    }

    private var previewHeader: some View {
        HStack {
            Circle()
                .fill(headerChromeColor)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(headerSymbolColor)
                        .allowsHitTesting(false)
                }

            Spacer()

            Text("Check Anthropic news")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(headerTitleColor)

            Spacer()

            Capsule()
                .fill(headerCapsuleColor)
                .frame(width: 136, height: 42)
                .overlay {
                    HStack(spacing: 18) {
                        Image(systemName: "plus")
                        Image(systemName: "clock.arrow.circlepath")
                        Image(systemName: "ellipsis")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(headerSymbolColor)
                    .allowsHitTesting(false)
                }
        }
    }

    private var headerChromeColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.14)
        default:
            Color.black.opacity(0.08)
        }
    }

    private var headerCapsuleColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.12)
        default:
            Color.black.opacity(0.06)
        }
    }

    private var headerSymbolColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.88)
        default:
            Color.black.opacity(0.72)
        }
    }

    private var headerTitleColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.7)
        default:
            Color.black.opacity(0.56)
        }
    }
}
