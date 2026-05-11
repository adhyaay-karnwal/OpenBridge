//
//  GlassMaterialMode.swift
//  GlassEffectKit
//

import SwiftUI

// MARK: - Glass Material Mode

/// Controls which glass rendering mode to use
public enum GlassMaterialMode: String, CaseIterable, Codable, Sendable {
    /// Auto-detect based on OS version (Liquid Glass on macOS 26+, fallback on older)
    case auto
    /// Force use legacy material (pre-macOS 26 style)
    case legacy
    /// Force use Liquid Glass (macOS 26+ style, requires macOS 26)
    case liquidGlass

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .legacy: "Legacy"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

public extension EnvironmentValues {
    /// The glass material rendering mode
    @Entry var glassMaterialMode: GlassMaterialMode = .auto
}

public extension View {
    /// Sets the glass material mode for this view and its descendants
    func glassMaterialMode(_ mode: GlassMaterialMode) -> some View {
        environment(\.glassMaterialMode, mode)
    }
}
