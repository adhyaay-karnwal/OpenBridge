//
//  SettingsManager.swift
//  OpenBridgeInterface
//
//  Created by GitHub Copilot on 20/10/2025.
//

import Foundation
import GlassEffectKit
import ObservableDefaults
import SwiftUI

/// OpenBridge 的集中化偏好存储入口。
/// - 新增需要持久化的配置时：必须声明默认值，并同步更新 `SettingsManager+Defaults.swift` 的 `SettingsKeys` 与 `Defaults`；
///   如涉及特殊处理（排序、去重等），请在对应的扩展中完成。
/// - 若增加仅供内部使用的状态，请使用 `@Ignore` 避免写入 UserDefaults。
/// - 如需额外副作用（例如缓存容量同步），在属性 `didSet` 中调用协作对象并遵守已有的早返回模式。
/// - 初始化已禁用宏自动生成版本：扩展构造逻辑时务必保持当前构造函数，并在末尾调用 `completeInitialization()` 确保副作用执行。
@MainActor
@ObservableDefaults(autoInit: false, defaultIsolationIsMainActor: true)
final class SettingsManager {
    static let shared = SettingsManager()

    @Ignore
    private var hasCompletedInitialization = false

    var showMenuBarIcon = Defaults.showMenuBarIcon
    var showDockIcon = Defaults.showDockIcon
    var enableLocalVMEnvironment = Defaults.enableLocalVMEnvironment
    var enableDebugMode = Defaults.enableDebugMode
    var autoUpdate = Defaults.autoUpdate
    var maxRetentionPeriod = Defaults.maxRetentionPeriod
    var maxRecords = Defaults.maxRecords
    var ocrAutoDetectLanguage = Defaults.ocrAutoDetectLanguage
    var primaryLanguage = Defaults.primaryLanguage
    var commonLanguages = Defaults.commonLanguages
    var appearance = Defaults.appearance

    var language = Defaults.language

    @DefaultsKey(userDefaultsKey: "accentColorName")
    var accentColorName = Defaults.accentColorName

    var accentColor: Color {
        accentColorName.color
    }

    var systemAccentColor: Color {
        SystemAccentColor.system.color
    }

    var accentColorForegroundColor: Color {
        accentColorName.foregroundColor
    }

    var appIcon = Defaults.appIcon

    var enableSoundEffects = Defaults.enableSoundEffects
    var showHeartbeatNotifications = Defaults.showHeartbeatNotifications

    var soundEventSettings = Defaults.soundEventSettings

    var useChatDevServerInDebug = Defaults.useChatDevServerInDebug
    var usePreviewDevServerInDebug = Defaults.usePreviewDevServerInDebug
    var chatPresentationMode = Defaults.chatPresentationMode

    var lastSelectedAgentTemplateID = Defaults.lastSelectedAgentTemplateID

    var enabledFeatures = Defaults.enabledFeatures

    var hasCompletedOnboarding = Defaults.hasCompletedOnboarding

    var glassMaterialMode = Defaults.glassMaterialMode
    var useLegacyMacOS26UI = Defaults.useLegacyMacOS26UI

    var shouldUseMacOS26UI: Bool {
        MacOS26UICompatibility.shouldUseMacOS26UI(forceLegacyFallback: useLegacyMacOS26UI)
    }

    var skillLastUsedTimes = Defaults.skillLastUsedTimes
    var remoteEnvironmentRootPath = Defaults.remoteEnvironmentRootPath
    var localVMMounts = Defaults.localVMMounts
    var localEnvironmentPermissionMode = Defaults.localEnvironmentPermissionMode

    init(
        userDefaults: UserDefaults? = nil,
        ignoreExternalChanges: Bool? = nil,
        prefix: String? = nil,
        ignoredKeyPathsForExternalUpdates: [PartialKeyPath<SettingsManager>] = []
    ) {
        if let userDefaults {
            _userDefaults = userDefaults
        }
        if let ignoreExternalChanges {
            _isExternalNotificationDisabled = ignoreExternalChanges
        }
        if let prefix {
            _prefix = prefix
        }
        _ignoredKeyPathsForExternalUpdates = ignoredKeyPathsForExternalUpdates
        assert(!_prefix.contains("."), "Prefix '\(_prefix)' should not contain '.' to avoid KVO issues!")
        if !_isExternalNotificationDisabled {
            observerStarter(observableKeysBlacklist: ignoredKeyPathsForExternalUpdates)
        }

        completeInitialization()
    }

    private func completeInitialization() {
        guard hasCompletedInitialization == false else { return }
        hasCompletedInitialization = true
    }
}
