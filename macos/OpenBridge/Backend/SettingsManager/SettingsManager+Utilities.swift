import Foundation
import SwiftUI

extension SettingsManager {
    private static let boolKeyPaths: [SettingsKeys: ReferenceWritableKeyPath<SettingsManager, Bool>] = [
        .showMenuBarIcon: \.showMenuBarIcon,
        .showDockIcon: \.showDockIcon,
        .enableLocalVMEnvironment: \.enableLocalVMEnvironment,
        .enableDebugMode: \.enableDebugMode,
        .autoUpdate: \.autoUpdate,
        .ocrAutoDetectLanguage: \.ocrAutoDetectLanguage,
        .useChatDevServerInDebug: \.useChatDevServerInDebug,
        .usePreviewDevServerInDebug: \.usePreviewDevServerInDebug,
        .enableSoundEffects: \.enableSoundEffects,
        .showHeartbeatNotifications: \.showHeartbeatNotifications,
        .hasCompletedOnboarding: \.hasCompletedOnboarding,
        .useLegacyMacOS26UI: \.useLegacyMacOS26UI,
    ]

    private static let intKeyPaths: [SettingsKeys: ReferenceWritableKeyPath<SettingsManager, Int>] = [
        .maxRetentionPeriod: \.maxRetentionPeriod,
        .maxRecords: \.maxRecords,
    ]

    private static let stringKeyPaths: [SettingsKeys: ReferenceWritableKeyPath<SettingsManager, String>] = [
        .primaryLanguage: \.primaryLanguage,
        .language: \.language,
    ]

    private static let stringArrayKeyPaths: [SettingsKeys: ReferenceWritableKeyPath<SettingsManager, [String]>] = [
        .commonLanguages: \.commonLanguages,
    ]

    func resetToDefaults() {
        showMenuBarIcon = Defaults.showMenuBarIcon
        showDockIcon = Defaults.showDockIcon
        enableLocalVMEnvironment = Defaults.enableLocalVMEnvironment
        enableDebugMode = Defaults.enableDebugMode
        autoUpdate = Defaults.autoUpdate
        maxRetentionPeriod = Defaults.maxRetentionPeriod
        maxRecords = Defaults.maxRecords
        ocrAutoDetectLanguage = Defaults.ocrAutoDetectLanguage
        primaryLanguage = Defaults.primaryLanguage
        commonLanguages = Defaults.commonLanguages
        accentColorName = Defaults.accentColorName
        language = Defaults.language
        appIcon = Defaults.appIcon
        lastSelectedAgentTemplateID = Defaults.lastSelectedAgentTemplateID
        chatPresentationMode = Defaults.chatPresentationMode
        useChatDevServerInDebug = Defaults.useChatDevServerInDebug
        usePreviewDevServerInDebug = Defaults.usePreviewDevServerInDebug
        enableSoundEffects = Defaults.enableSoundEffects
        showHeartbeatNotifications = Defaults.showHeartbeatNotifications
        useLegacyMacOS26UI = Defaults.useLegacyMacOS26UI
        localVMMounts = Defaults.localVMMounts
        localEnvironmentPermissionMode = Defaults.localEnvironmentPermissionMode
    }

    func getAllSettings() -> [String: Any] {
        SettingsKeys.allCases.reduce(into: [String: Any]()) { result, key in
            if let value = currentValue(for: key) {
                result[key.key] = value
            }
        }
    }

    func getValue<T>(for key: SettingsKeys, type _: T.Type) -> T? {
        currentValue(for: key) as? T
    }

    // swiftlint:disable:next cyclomatic_complexity
    func setSettingValue(_ value: some Any, for key: SettingsKeys) {
        if let keyPath = Self.boolKeyPaths[key], let bool = value as? Bool {
            self[keyPath: keyPath] = bool
            return
        }

        if let keyPath = Self.intKeyPaths[key], let int = value as? Int {
            self[keyPath: keyPath] = int
            return
        }

        if let keyPath = Self.stringKeyPaths[key], let string = value as? String {
            self[keyPath: keyPath] = string
            return
        }

        if let keyPath = Self.stringArrayKeyPaths[key], let array = value as? [String] {
            self[keyPath: keyPath] = array
            return
        }

        switch key {
        case .appIcon:
            if let icon = value as? AppIcon {
                appIcon = icon
            } else if let raw = value as? String, let icon = AppIcon(rawValue: raw) {
                appIcon = icon
            }
        case .chatPresentationMode:
            if let mode = value as? ChatPresentationMode {
                chatPresentationMode = mode
            } else if let raw = value as? String, let mode = ChatPresentationMode(rawValue: raw) {
                chatPresentationMode = mode
            }
        case .localEnvironmentPermissionMode:
            if let mode = value as? LocalEnvironmentPermissionMode {
                localEnvironmentPermissionMode = mode
            } else if let raw = value as? String, let mode = LocalEnvironmentPermissionMode(rawValue: raw) {
                localEnvironmentPermissionMode = mode
            }
        default:
            break
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func currentValue(for key: SettingsKeys) -> Any? {
        switch key {
        case .showMenuBarIcon: showMenuBarIcon
        case .showDockIcon: showDockIcon
        case .enableLocalVMEnvironment: enableLocalVMEnvironment
        case .enableDebugMode: enableDebugMode
        case .autoUpdate: autoUpdate
        case .maxRetentionPeriod: maxRetentionPeriod
        case .maxRecords: maxRecords
        case .ocrAutoDetectLanguage: ocrAutoDetectLanguage
        case .primaryLanguage: primaryLanguage
        case .commonLanguages: commonLanguages
        case .appearance: appearance
        case .accentColorName: accentColorName
        case .language: language
        case .appIcon: appIcon
        case .useChatDevServerInDebug: useChatDevServerInDebug
        case .usePreviewDevServerInDebug: usePreviewDevServerInDebug
        case .chatPresentationMode: chatPresentationMode
        case .lastSelectedAgentTemplateID:
            lastSelectedAgentTemplateID
        case .enableSoundEffects: enableSoundEffects
        case .showHeartbeatNotifications: showHeartbeatNotifications
        case .soundEventSettings: soundEventSettings
        case .enabledFeatures: enabledFeatures
        case .hasCompletedOnboarding: hasCompletedOnboarding
        case .glassMaterialMode: glassMaterialMode
        case .useLegacyMacOS26UI: useLegacyMacOS26UI
        case .skillLastUsedTimes: skillLastUsedTimes
        case .remoteEnvironmentRootPath: remoteEnvironmentRootPath
        case .localVMMounts: localVMMounts
        case .localEnvironmentPermissionMode: localEnvironmentPermissionMode
        }
    }
}
