//
//  Color+hex.swift
//  OpenBridge
//
//  Created by Hwang on 11/12/25.
//

import SwiftUI
#if os(macOS)
    import AppKit
#endif

extension Color {
    /// Initialize Color from a hexadecimal string
    /// - Parameter hex: Hexadecimal color string, supports the following formats:
    ///   - "RGB" (12-bit): "F0A"
    ///   - "RRGGBB" (24-bit): "FFB8B8"
    ///   - "RRGGBBAA" (32-bit): "FFB8B8FF"
    ///   - Optional "#" prefix: "#FFB8B8"
    /// - Parameter opacity: Optional opacity (0.0 - 1.0), overrides alpha value from hex string if provided
    nonisolated init(hex: String, opacity: Double? = nil) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RRGGBB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // RRGGBBAA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (255, 0, 0, 255) // 默认红色，用于标识错误
        }

        let finalOpacity = opacity ?? Double(a) / 255.0

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: finalOpacity
        )
    }

    /// Convert the color into an uppercase hexadecimal string.
    /// - Parameter includeAlpha: Whether to include the alpha channel in the result.
    /// - Returns: Hexadecimal string (RRGGBBAA by default) or nil when conversion fails.
    func toHexString(includeAlpha: Bool = true) -> String? {
        #if os(macOS)
            var resolvedColor: NSColor?

            // Use the current effective appearance to resolve dynamic colors correctly
            // This ensures colors like .blue, .primary, .accentColor are resolved
            // based on the current light/dark mode
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                let nsColor = NSColor(self)
                resolvedColor = nsColor.usingColorSpace(.sRGB)
            }

            guard let converted = resolvedColor else { return nil }

            let r = Int(round(converted.redComponent * 255))
            let g = Int(round(converted.greenComponent * 255))
            let b = Int(round(converted.blueComponent * 255))
            let a = Int(round(converted.alphaComponent * 255))

            if includeAlpha {
                return String(format: "%02X%02X%02X%02X", r, g, b, a)
            } else {
                return String(format: "%02X%02X%02X", r, g, b)
            }
        #else
            return nil
        #endif
    }

    /// Sanitize a hexadecimal string for color usage.
    /// - Parameter hex: Input string that may contain non-hex characters or prefixes.
    /// - Returns: Uppercased sanitized string with lengths 3, 6, or 8; otherwise nil.
    static func normalizeHexString(_ hex: String) -> String? {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        switch sanitized.count {
        case 3, 6, 8:
            return sanitized.uppercased()
        default:
            return nil
        }
    }
}
