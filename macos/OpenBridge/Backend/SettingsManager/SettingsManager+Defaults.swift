import Foundation

nonisolated enum SettingsKeyName: String, CaseIterable {
    case showMenuBarIcon
    case showDockIcon
    case enableLocalVMEnvironment
    case enableDebugMode
    case autoUpdate
    case maxRetentionPeriod
    case maxRecords
    case ocrAutoDetectLanguage
    case primaryLanguage
    case commonLanguages
    case appearance
    case accentColorName
    case language
    case enableSoundEffects
    case showHeartbeatNotifications
    case soundEventSettings
    case appIcon
    case useChatDevServerInDebug
    case usePreviewDevServerInDebug
    case chatPresentationMode
    case lastSelectedAgentTemplateID
    case enabledFeatures
    case hasCompletedOnboarding
    case glassMaterialMode
    case useLegacyMacOS26UI
    case skillLastUsedTimes
    case remoteEnvironmentRootPath
    case localEnvironmentPermissionMode

    var key: String {
        rawValue
    }
}

/// Glass material rendering mode
enum GlassMaterialMode: String, CaseIterable, Codable {
    /// Auto-detect based on OS version (Liquid Glass on macOS 26+, fallback on older)
    case auto
    /// Force use legacy material (pre-macOS 26 style)
    case legacy
    /// Force use Liquid Glass (macOS 26+ style, requires macOS 26)
    case liquidGlass

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .legacy: "Legacy (Pre-macOS 26)"
        case .liquidGlass: "Liquid Glass (macOS 26)"
        }
    }
}

nonisolated enum SettingsDefaults {
    static let localVMMinimumHostMemoryBytes: UInt64 = 15_000_000_000

    static func defaultEnableLocalVMEnvironment(hostPhysicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Bool {
        hostPhysicalMemoryBytes >= localVMMinimumHostMemoryBytes
    }

    static let showMenuBarIcon = true
    static let showDockIcon = false
    static var enableLocalVMEnvironment: Bool {
        defaultEnableLocalVMEnvironment()
    }

    static let enableDebugMode = false
    static let autoUpdate = true
    static let maxRetentionPeriod = 30
    static let maxRecords = 1000
    static let ocrAutoDetectLanguage = true
    static let primaryLanguage = ""
    static let commonLanguages: [String] = []
    static let appearance: Appearance = .system
    static let accentColorName: SystemAccentColor = .default
    static let language: String = Locale.preferredLanguages.first ?? "en"
    static let enableSoundEffects = true
    static let showHeartbeatNotifications = true
    static let soundEventSettings: SoundEventSettings = .default
    static let appIcon: AppIcon = .default
    static let useChatDevServerInDebug = false
    static let usePreviewDevServerInDebug = false
    static let chatPresentationMode: ChatPresentationMode = .panel

    /// Debug-only agent chat template override. Empty means use the session default template.
    static let lastSelectedAgentTemplateID = ""

    /// Enabled feature flags.
    static let enabledFeatures: [FeatureFlag] = []

    /// Whether onboarding has been completed
    static let hasCompletedOnboarding = false

    /// Glass material rendering mode (auto by default)
    static let glassMaterialMode: GlassMaterialMode = .auto
    /// Forces macOS 26+ systems to use the pre-macOS 26 UI.
    static let useLegacyMacOS26UI = false
    /// Skill last used timestamps (skill name -> last used date)
    static let skillLastUsedTimes: [String: Date] = [:]
    static let remoteEnvironmentRootPath = ""

    static let localEnvironmentPermissionMode: LocalEnvironmentPermissionMode = .default
}

nonisolated extension SettingsManager {
    typealias SettingsKeys = SettingsKeyName
    typealias Defaults = SettingsDefaults
}
