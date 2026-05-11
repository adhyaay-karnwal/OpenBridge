//
//  Appearance.swift
//  OpenBridge
//
//  Created by qaq on 18/12/2025.
//

import Cocoa
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case light
    case dark
    case system

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .light:
            String(localized: "Light")
        case .dark:
            String(localized: "Dark")
        case .system:
            String(localized: "System")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .system:
            nil
        }
    }
}
