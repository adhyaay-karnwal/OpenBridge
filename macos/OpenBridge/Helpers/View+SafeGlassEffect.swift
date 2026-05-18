//
//  View+SafeGlassEffect.swift
//  OpenBridge
//
//  OpenBridge for GlassEffectKit with SettingsManager integration
//

@_exported import GlassEffectKit
import SwiftUI

// MARK: - SettingsManager Integration

/// Automatically injects glassMaterialMode from SettingsManager into the environment
struct GlassMaterialModeInjector: ViewModifier {
    @Environment(SettingsManager.self) private var settingsManager

    func body(content: Content) -> some View {
        let mode: GlassEffectKit.GlassMaterialMode = if settingsManager.useLegacyMacOS26UI {
            .legacy
        } else {
            switch settingsManager.glassMaterialMode {
            case .auto: .auto
            case .legacy: .legacy
            case .liquidGlass: .liquidGlass
            }
        }

        return content.glassMaterialMode(mode)
    }
}

extension View {
    /// Injects the glass material mode from SettingsManager into the environment.
    /// Apply this at app root level so all child views use the correct mode.
    func injectGlassMaterialMode() -> some View {
        modifier(GlassMaterialModeInjector())
    }
}

// MARK: - Chat Header Glass

enum ChatHeaderLiquidGlassStyle {
    static let tintOpacity: Double = 0.2
    static let liquidDividerOpacity: Double = 0.1
    static let legacyDividerOpacity: Double = 0.08
    static let liquidFocusedStrokeOpacity: Double = 0.18
    static let liquidStrokeOpacity: Double = 0.08
    static let legacyFocusedStrokeOpacity: Double = 0.2
    static let legacyStrokeOpacity: Double = 0.1

    static var nativeTintColor: Color {
        .white.opacity(tintOpacity)
    }

    static var fallbackMaterial: SafeGlassMaterial {
        .regular.tint(.white.opacity(tintOpacity))
    }

    static func dividerColor(usesLiquidGlass: Bool) -> Color {
        .white.opacity(usesLiquidGlass ? liquidDividerOpacity : legacyDividerOpacity)
    }

    static func strokeColor(isFocused: Bool, usesLiquidGlass: Bool) -> Color {
        if usesLiquidGlass {
            return .white.opacity(isFocused ? liquidFocusedStrokeOpacity : liquidStrokeOpacity)
        }

        return .white.opacity(isFocused ? legacyFocusedStrokeOpacity : legacyStrokeOpacity)
    }
}

enum ChatHeaderIconHoverStyle {
    static let hoverFillOpacity = 0.12
    static let compactHoverDiameter: CGFloat = 26
    static let standaloneHoverDiameter: CGFloat = 32

    static func fillOpacity(isHovered: Bool) -> Double {
        isHovered ? hoverFillOpacity : 0
    }
}

struct ChatHeaderIconHoverBackground: View {
    let isHovered: Bool
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color.primary.opacity(ChatHeaderIconHoverStyle.fillOpacity(isHovered: isHovered)))
            .frame(width: diameter, height: diameter)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .allowsHitTesting(false)
    }
}

private struct ChatHeaderLiquidGlassModifier<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape

    func body(content: Content) -> some View {
        content.safeGlassEffect(ChatHeaderLiquidGlassStyle.fallbackMaterial, in: shape)
    }
}

private struct ChatHeaderLiquidGlassChromeModifier<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape
    let usesLiquidGlass: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        if usesLiquidGlass {
            content
                .chatHeaderLiquidGlass(in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        ChatHeaderLiquidGlassStyle.strokeColor(
                            isFocused: isFocused,
                            usesLiquidGlass: true
                        )
                    )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        ChatHeaderLiquidGlassStyle.strokeColor(
                            isFocused: isFocused,
                            usesLiquidGlass: false
                        )
                    )
                }
        }
    }
}

extension View {
    func chatHeaderLiquidGlass(in shape: some InsettableShape) -> some View {
        modifier(ChatHeaderLiquidGlassModifier(shape: shape))
    }

    func chatHeaderLiquidGlassChrome(
        in shape: some InsettableShape,
        usesLiquidGlass: Bool,
        isFocused: Bool = false
    ) -> some View {
        modifier(
            ChatHeaderLiquidGlassChromeModifier(
                shape: shape,
                usesLiquidGlass: usesLiquidGlass,
                isFocused: isFocused
            )
        )
    }
}

// MARK: - Preview

#Preview("Glass Effect Styles") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach([
                ("Clear", SafeGlassMaterial.clear),
                ("Ultra Thin", SafeGlassMaterial.ultraThin),
                ("Thin", SafeGlassMaterial.thin),
                ("Regular", SafeGlassMaterial.regular),
                ("Thick", SafeGlassMaterial.thick),
                ("Ultra Thick", SafeGlassMaterial.ultraThick),
                ("Chrome", SafeGlassMaterial.chrome),
            ], id: \.0) { name, material in
                Text(name)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .safeGlassEffect(material)
            }

            Text("Circle Shape")
                .font(.title2)
                .frame(width: 150, height: 150)
                .safeGlassEffect(.regular.tint(.blue), in: Circle())

            Text("Rectangle")
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
                .safeGlassEffect(.clear.tint(.green), in: RoundedRectangle(cornerRadius: 20))

            Text("Ellipse")
                .font(.title2)
                .frame(width: 200, height: 100)
                .safeGlassEffect(.chrome.tint(.purple), in: Ellipse())

            Text("Custom Corner Radius")
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
                .safeGlassEffect(
                    .regular.tint(.orange),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .padding()
    }
    .background(
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#Preview("Button Examples with Shapes") {
    VStack(spacing: 20) {
        Button("Primary Action") {
            print("Tapped")
        }
        .padding()
        .safeGlassEffect(.regular.tint(.blue))

        Button("Secondary Action") {
            print("Tapped")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .safeGlassEffect(
            .thin.tint(.gray),
            in: RoundedRectangle(cornerRadius: 12)
        )

        Button(action: { print("Tapped") }) {
            Image(systemName: "plus")
                .font(.title)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
        }
        .safeGlassEffect(
            .thick.tint(.green),
            in: Circle()
        )

        Button("Custom Shape") {
            print("Tapped")
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .safeGlassEffect(
            .clear.tint(.red, opacity: 0.2),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )

        Button("Disabled") {
            print("Tapped")
        }
        .padding()
        .safeGlassEffect(
            .regular,
            in: Capsule(),
            isEnabled: false
        )
        .disabled(true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        Image(systemName: "photo")
            .resizable()
            .scaledToFill()
            .opacity(0.3)
    )
}

#Preview("Shape Gallery") {
    struct ShapeGalleryView: View {
        @State private var isEnabled = true

        var body: some View {
            ScrollView {
                VStack(spacing: 30) {
                    TintedToggle("Glass Effect Enabled", isOn: $isEnabled)
                        .padding()
                        .safeGlassEffect(
                            .ultraThin.tint(.blue),
                            in: Capsule(),
                            isEnabled: isEnabled
                        )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        VStack {
                            Image(systemName: "star.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)
                                .frame(width: 100, height: 100)
                                .safeGlassEffect(
                                    .regular.tint(.yellow, opacity: 0.2),
                                    in: Circle()
                                )
                            Text("Circle")
                                .font(.caption)
                        }

                        VStack {
                            Image(systemName: "heart.fill")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                                .frame(width: 120, height: 80)
                                .safeGlassEffect(
                                    .thin.tint(.red, opacity: 0.2),
                                    in: Ellipse()
                                )
                            Text("Ellipse")
                                .font(.caption)
                        }

                        VStack {
                            Image(systemName: "square.grid.2x2")
                                .font(.largeTitle)
                                .foregroundColor(.green)
                                .frame(width: 100, height: 100)
                                .safeGlassEffect(
                                    .clear.tint(.green, opacity: 0.2),
                                    in: Rectangle()
                                )
                            Text("Rectangle")
                                .font(.caption)
                        }

                        VStack {
                            Image(systemName: "app.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                                .frame(width: 100, height: 100)
                                .safeGlassEffect(
                                    .regular.tint(.blue, opacity: 0.2),
                                    in: RoundedRectangle(cornerRadius: 20)
                                )
                            Text("Rounded")
                                .font(.caption)
                        }

                        VStack {
                            Image(systemName: "iphone")
                                .font(.largeTitle)
                                .foregroundColor(.purple)
                                .frame(width: 100, height: 100)
                                .safeGlassEffect(
                                    .chrome.tint(.purple, opacity: 0.2),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                            Text("Continuous")
                                .font(.caption)
                        }

                        VStack {
                            Image(systemName: "pills.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                                .frame(width: 120, height: 60)
                                .safeGlassEffect(
                                    .thick.tint(.orange, opacity: 0.2),
                                    in: Capsule()
                                )
                            Text("Capsule")
                                .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .background(
                LinearGradient(
                    colors: [.indigo, .purple, .pink],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    return ShapeGalleryView()
        .environment(SettingsManager.shared)
}
