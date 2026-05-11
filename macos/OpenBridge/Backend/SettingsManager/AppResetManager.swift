//
//  AppResetManager.swift
//  OpenBridge
//

import Foundation

@MainActor
enum AppResetManager {
    /// 重置应用：清空数据库和所有 UserDefaults 数据
    /// - Throws: 如果重置过程中出现错误
    static func resetApp() throws {
        // 1. 重置数据库
        try Database.shared.reset()

        // 2. 重置 SettingsManager 到默认值
        SettingsManager.shared.resetToDefaults()

        // 3. 清空 UserDefaults.standard 中所有与当前应用相关的数据
        clearUserDefaults()

        Logger.app.info("App reset completed: database and UserDefaults cleared")
    }

    /// 清空 UserDefaults.standard 中所有与当前应用相关的数据
    private static func clearUserDefaults() {
        let defaults = UserDefaults.standard

        // 清空 SettingsManager 的所有设置 key
        for key in SettingsKeyName.allCases {
            defaults.removeObject(forKey: key.key)
        }

        // 清空其他已知的 key
        defaults.removeObject(forKey: "com.openbridge.agentSessionMapping")

        // 同步以确保更改立即生效
        defaults.synchronize()
    }
}
