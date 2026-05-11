//
//  SystemAccentColor.swift
//  OpenBridge
//
//  Created by qaq on 18/12/2025.
//

import Cocoa
import SwiftUI

enum SystemAccentColor: String, CaseIterable, Identifiable, Codable {
    case `default`
    case system
    case blue
    case green
    case indigo
    case orange
    case pink
    case purple
    case red
    // TODO: custom

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .default: String(localized: "Default")
        case .system: String(localized: "System")
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .indigo: String(localized: "Indigo")
        case .orange: String(localized: "Orange")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .red: String(localized: "Red")
        }
    }

    var color: Color {
        switch self {
        case .default: .primary
        case .system: .accentColor
        case .blue: .blue
        case .green: .green
        case .indigo: .indigo
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        }
    }

    var foregroundColor: Color {
        switch self {
        case .default: Color(NSColor.windowBackgroundColor)
        default: .white
        }
    }
}
