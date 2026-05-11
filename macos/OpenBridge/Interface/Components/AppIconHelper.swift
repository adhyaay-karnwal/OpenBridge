//
//  AppIconHelper.swift
//  OpenBridgeInterface
//
//  Created by OpenBridge on 2025/01/27.
//

import AppKit
import SwiftUI

enum AppIconHelper {
    /// Get app icon for a given bundle identifier
    /// - Parameter bundleIdentifier: The bundle identifier of the app
    /// - Returns: NSImage of the app icon, or nil if not found
    static func getAppIcon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }

        // Try to get the app from the bundle identifier
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        // Get the app's icon
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    /// Get app icon as SwiftUI Image
    /// - Parameter bundleIdentifier: The bundle identifier of the app
    /// - Returns: SwiftUI Image of the app icon, or a default icon if not found
    static func getAppIconImage(for bundleIdentifier: String?) -> Image {
        guard let nsImage = getAppIcon(for: bundleIdentifier) else {
            return Image(systemName: "app")
        }

        return Image(nsImage: nsImage)
    }
}
