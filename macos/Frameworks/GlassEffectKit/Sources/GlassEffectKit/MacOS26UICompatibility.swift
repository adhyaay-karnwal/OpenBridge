#if os(macOS)
    import Foundation

    /// Resolves whether macOS 26-specific UI should be enabled for the current process.
    public enum MacOS26UICompatibility {
        public static let legacyFallbackUserDefaultsKey = "useLegacyMacOS26UI"

        public static func shouldUseMacOS26UI(
            forceLegacyFallback: Bool,
            isSupportedOS: Bool
        ) -> Bool {
            isSupportedOS && !forceLegacyFallback
        }

        public static func shouldUseMacOS26UI(forceLegacyFallback: Bool) -> Bool {
            shouldUseMacOS26UI(
                forceLegacyFallback: forceLegacyFallback,
                isSupportedOS: isMacOS26OrLater
            )
        }

        public static func shouldUseMacOS26UI(userDefaults: UserDefaults = .standard) -> Bool {
            shouldUseMacOS26UI(
                forceLegacyFallback: userDefaults.bool(forKey: legacyFallbackUserDefaultsKey)
            )
        }

        public static var isMacOS26OrLater: Bool {
            if #available(macOS 26.0, *) {
                true
            } else {
                false
            }
        }
    }
#endif
