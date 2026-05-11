import SwiftUI

struct ThinkingHighlightText: View {
    let text: String
    var font: Font
    var baseColor: Color = .white.opacity(0.6)
    var highlightColor: Color = .white.opacity(0.96)
    var lineLimit: Int = 1
    var alignment: Alignment = .leading

    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(baseColor)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .overlay {
                GeometryReader { proxy in
                    Text(text)
                        .font(font)
                        .foregroundStyle(highlightColor)
                        .lineLimit(lineLimit)
                        .truncationMode(.tail)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: alignment
                        )
                        .mask(alignment: alignment) {
                            highlightSweep(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                        }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .clipped()
            }
            .onAppear {
                startHighlightAnimation()
            }
            .onChange(of: text) { _, _ in
                startHighlightAnimation()
            }
    }

    private func highlightSweep(width: CGFloat, height: CGFloat) -> some View {
        let sweepWidth = max(96, width * 0.72)
        let travel = width + sweepWidth * 2

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: highlightColor.opacity(0.08), location: 0.18),
                .init(color: highlightColor.opacity(0.9), location: 0.5),
                .init(color: highlightColor.opacity(0.08), location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: sweepWidth, height: max(1, height))
        .blur(radius: 5)
        .offset(x: phase * travel - sweepWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func startHighlightAnimation() {
        phase = 0
        withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}
