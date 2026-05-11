//
//  SafeGlassEffect.swift
//  GlassEffectKit
//
//  iOS 18+ compatible glass effect that uses native glassEffect on iOS 26+
//

import SwiftUI

// MARK: - Glass Effect Material

/// Material type that provides glass effect for iOS 18+
public struct SafeGlassMaterial: Sendable {
    public enum Style: Sendable {
        case clear
        case ultraThin
        case thin
        case regular
        case thick
        case ultraThick
        case chrome

        @available(iOS 15.0, macOS 12.0, *)
        var regularMaterial: Material {
            switch self {
            case .clear, .ultraThin:
                .ultraThinMaterial
            case .thin:
                .thinMaterial
            case .regular:
                .regularMaterial
            case .thick:
                .thickMaterial
            case .ultraThick:
                .ultraThickMaterial
            case .chrome:
                .regularMaterial
            }
        }

        var opacity: Double {
            switch self {
            case .clear: 0.05
            case .ultraThin: 0.15
            case .thin: 0.25
            case .regular: 0.35
            case .thick: 0.45
            case .ultraThick: 0.55
            case .chrome: 0.65
            }
        }

        var blurRadius: CGFloat {
            switch self {
            case .clear: 8
            case .ultraThin: 12
            case .thin: 16
            case .regular: 20
            case .thick: 24
            case .ultraThick: 30
            case .chrome: 10
            }
        }

        @available(iOS 26.0, macOS 26.0, *)
        var nativeGlassStyle: Any {
            switch self {
            case .clear, .ultraThin:
                Glass.clear
            case .thin, .regular, .thick, .ultraThick, .chrome:
                Glass.regular
            }
        }
    }

    public let style: Style
    public var tintColor: Color?
    public var tintOpacity: Double

    public init(style: Style, tintColor: Color? = nil, tintOpacity: Double = 0.3) {
        self.style = style
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
    }

    // MARK: - Factory Methods

    public static var clear: SafeGlassMaterial {
        SafeGlassMaterial(style: .clear)
    }

    public static var ultraThin: SafeGlassMaterial {
        SafeGlassMaterial(style: .ultraThin)
    }

    public static var thin: SafeGlassMaterial {
        SafeGlassMaterial(style: .thin)
    }

    public static var regular: SafeGlassMaterial {
        SafeGlassMaterial(style: .regular)
    }

    public static var thick: SafeGlassMaterial {
        SafeGlassMaterial(style: .thick)
    }

    public static var ultraThick: SafeGlassMaterial {
        SafeGlassMaterial(style: .ultraThick)
    }

    public static var chrome: SafeGlassMaterial {
        SafeGlassMaterial(style: .chrome)
    }

    // MARK: - Modifiers

    public func tint(_ color: Color, opacity: Double = 0.3) -> SafeGlassMaterial {
        SafeGlassMaterial(style: style, tintColor: color, tintOpacity: opacity)
    }
}

// MARK: - Safe Glass Effect View Modifier

struct SafeGlassEffectModifier<S: Shape>: ViewModifier {
    let material: SafeGlassMaterial
    let shape: S
    let isEnabled: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.glassMaterialMode) private var glassMaterialMode

    func body(content: Content) -> some View {
        let useNativeGlass = shouldUseNativeGlass()

        if useNativeGlass {
            if #available(iOS 26.0, macOS 26.0, *) {
                content
                    .background {
                        Color.clear
                            .safeNativeGlassEffect(material, in: shape, isEnabled: isEnabled)
                    }
                    .clipShape(shape)
            } else {
                fallbackContent(content)
            }
        } else {
            fallbackContent(content)
        }
    }

    private func fallbackContent(_ content: Content) -> some View {
        content
            .background(
                FallbackGlassEffectView(material: material)
                    .clipShape(shape)
            )
            .clipShape(shape)
    }

    private func shouldUseNativeGlass() -> Bool {
        switch glassMaterialMode {
        case .auto:
            if #available(iOS 26.0, macOS 26.0, *) {
                return true
            }
            return false
        case .legacy:
            return false
        case .liquidGlass:
            if #available(iOS 26.0, macOS 26.0, *) {
                return true
            }
            return false
        }
    }
}

// MARK: - Native Glass Effect Wrapper

@available(iOS 26.0, macOS 26.0, *)
extension View {
    @ViewBuilder
    func safeNativeGlassEffect(_ material: SafeGlassMaterial, in shape: some Shape, isEnabled: Bool) -> some View {
        if !isEnabled {
            glassEffect(Glass.identity, in: shape)
        } else if let tintColor = material.tintColor {
            let resolvedTintColor = tintColor.opacity(material.tintOpacity)
            switch material.style {
            case .clear, .ultraThin:
                glassEffect(Glass.clear.tint(resolvedTintColor), in: shape)
            case .thin, .regular, .thick, .ultraThick, .chrome:
                glassEffect(Glass.regular.tint(resolvedTintColor), in: shape)
            }
        } else {
            switch material.style {
            case .clear, .ultraThin:
                glassEffect(Glass.clear, in: shape)
            case .thin, .regular, .thick, .ultraThick, .chrome:
                glassEffect(Glass.regular, in: shape)
            }
        }
    }
}

// MARK: - Fallback Glass Effect Implementation

struct FallbackGlassEffectView: View {
    let material: SafeGlassMaterial
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            if #available(iOS 15.0, macOS 12.0, *) {
                Color.clear
                    .background(material.style.regularMaterial)
            } else {
                Color.clear
                    .background(.ultraThinMaterial)
            }

            if let tintColor = material.tintColor {
                tintColor
                    .opacity(material.tintOpacity)
                    .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
            }

            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.05),
                    Color.clear,
                    Color.black.opacity(0.05),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.5)

            if material.style == .chrome {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.4),
                        Color.clear,
                        Color.white.opacity(0.2),
                        Color.clear,
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Public View Extension

public extension View {
    /// Applies a glass effect that works on iOS 18+ and uses native glassEffect on iOS 26+
    func safeGlassEffect(
        _ material: SafeGlassMaterial = .regular,
        in shape: some Shape,
        isEnabled: Bool = true
    ) -> some View {
        modifier(SafeGlassEffectModifier(
            material: material,
            shape: shape,
            isEnabled: isEnabled
        ))
    }

    /// Applies a glass effect with default Capsule shape
    func safeGlassEffect(_ material: SafeGlassMaterial = .regular) -> some View {
        safeGlassEffect(material, in: Capsule())
    }

    /// Convenience method for clear glass with tint and custom shape
    func safeGlassEffect(
        tint: Color,
        opacity: Double = 0.3,
        in shape: some Shape
    ) -> some View {
        safeGlassEffect(.clear.tint(tint, opacity: opacity), in: shape)
    }

    /// Convenience method for clear glass with tint (default Capsule shape)
    func safeGlassEffect(tint: Color, opacity: Double = 0.3) -> some View {
        safeGlassEffect(.clear.tint(tint, opacity: opacity), in: Capsule())
    }
}
