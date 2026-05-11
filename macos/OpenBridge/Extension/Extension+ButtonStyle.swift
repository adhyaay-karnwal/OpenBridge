import SwiftUI

struct PillButtonStyle: ButtonStyle {
    enum Variant {
        case outlined
        case primary
    }

    let variant: Variant
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if variant == .outlined {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini: 6
        case .small: 8
        case .regular: 12
        case .large: 16
        case .extraLarge: 20
        @unknown default: 12
        }
    }

    private var verticalPadding: CGFloat {
        switch controlSize {
        case .mini: 2
        case .small: 4
        case .regular: 4
        case .large: 8
        case .extraLarge: 10
        @unknown default: 6
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .outlined:
            isPressed ? Color.primary.opacity(0.05) : .clear
        case .primary:
            Color.accentColor.opacity(isPressed ? 0.78 : 1)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .outlined:
            .primary
        case .primary:
            .white
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillOutlined: PillButtonStyle {
        .init(variant: .outlined)
    }

    static var pillPrimary: PillButtonStyle {
        .init(variant: .primary)
    }
}

#Preview("Pill Button Examples") {
    ZStack {
        Button("A Button") { print("Tapped") }
            .buttonStyle(.pillOutlined)
            .padding()

        Button("A Button") { print("Tapped") }
            .buttonStyle(.bordered)
            .padding()
    }

    Button("A Button") { print("Tapped") }
        .buttonStyle(.pillOutlined)
        .padding()

    Button("A Button") { print("Tapped") }
        .buttonStyle(.bordered)
        .padding()
}
