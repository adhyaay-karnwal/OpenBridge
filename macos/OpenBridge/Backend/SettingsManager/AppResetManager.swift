//
//  AppResetManager.swift
//  OpenBridge
//

import Foundation

@MainActor
enum AppResetManager {
    static func resetApp() throws {
        SettingsManager.shared.resetToDefaults()
        clearUserDefaults()

        Logger.app.info("App reset completed: UserDefaults cleared")
    }

    private static func clearUserDefaults() {
        let defaults = UserDefaults.standard

        for key in SettingsKeyName.allCases {
            defaults.removeObject(forKey: key.key)
        }

        defaults.removeObject(forKey: "com.openbridge.agentSessionMapping")

        defaults.synchronize()
    }
}
