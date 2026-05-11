//
//  AppIcon.swift
//  OpenBridge
//
//  Created by qaq on 18/12/2025.
//

import Cocoa
import SwiftUI

enum AppIcon: String, CaseIterable, Identifiable, Codable {
    case `default`
    #if DEBUG
        case appIconDev
    #endif

    case appIconBLUEBLOCK
    case appIconMERCURY

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .default: String(localized: "Default")
        #if DEBUG
            case .appIconDev: String(localized: "Developer")
        #endif
        case .appIconBLUEBLOCK: String(localized: "Blue Lock")
        case .appIconMERCURY: String(localized: "Mercury")
        }
    }

    var image: NSImage {
        let read: NSImage? = switch self {
        case .default: .init(named: "AppIcon")
        #if DEBUG
            case .appIconDev: .init(named: "AppIconDev")
        #endif
        case .appIconBLUEBLOCK: .init(named: "AppIconBLUEBLOCK")
        case .appIconMERCURY: .init(named: "AppIconMERCURY")
        }
        return read ?? .appLogo
    }

    var placeholderColors: [Color] {
        switch self {
        case .default:
            []
        #if DEBUG
            case .appIconDev:
                []
        #endif
        case .appIconBLUEBLOCK:
            []
        case .appIconMERCURY:
            []
        }
    }

    func apply() {
        let bundlePath = Bundle.main.bundleURL.path
        let customIcon: NSImage? = self == .default ? nil : image
        if !NSWorkspace.shared.setIcon(customIcon, forFile: bundlePath, options: []) {
            Logger.app.error("Failed to set bundle icon for \(bundlePath)")
        }
        NSApp.applicationIconImage = nil
        NSApp.applicationIconImage = image
    }

    #if DEBUG
        static func validateAll() {
            for eachCase in allCases {
                assert(eachCase.image != .appLogo)
            }
            Logger.app.info("\(allCases.count) alternative image asset has been validated!")
        }
    #endif
}
