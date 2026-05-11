import SwiftUI

enum IndeterminateStyle {
    case ring
    case rays
}

struct CircularProgressStyle: ProgressViewStyle {
    var color: Color = .white
    var trackOpacity: Double = 0.3
    var lineWidth: CGFloat = 2
    var size: CGFloat = 16
    var indeterminateStyle: IndeterminateStyle = .ring

    func makeBody(configuration: Configuration) -> some View {
        if let fraction = configuration.fractionCompleted {
            // Determinate mode: show progress
            DeterminateCircle(
                fraction: fraction,
                color: color,
                trackOpacity: trackOpacity,
                lineWidth: lineWidth,
                size: size
            )
        } else {
            // Indeterminate mode
            switch indeterminateStyle {
            case .ring:
                IndeterminateRing(
                    color: color,
                    lineWidth: lineWidth,
                    size: size
                )
            case .rays:
                IndeterminateRays(
                    color: color,
                    size: size
                )
            }
        }
    }
}

// MARK: - Determinate Circle

private struct DeterminateCircle: View {
    let fraction: Double
    let color: Color
    let trackOpacity: Double
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(trackOpacity), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Indeterminate Ring

private struct IndeterminateRing: View {
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color.opacity(0), color]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Indeterminate Rays

private struct IndeterminateRays: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.08) % 8
            Image(systemName: "rays")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
                .mask {
                    AngularGradient(
                        gradient: Gradient(colors: [color, color.opacity(0.1)]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    )
                }
                .rotationEffect(.degrees(Double(step) * 45), anchor: .center)
                .drawingGroup()
        }
        .frame(width: size, height: size)
    }
}
