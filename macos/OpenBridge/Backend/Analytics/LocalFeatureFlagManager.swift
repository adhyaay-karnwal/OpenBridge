import Foundation

enum LocalFeatureFlag: CaseIterable {
    case webviewDevTool
}

@MainActor
@Observable
final class LocalFeatureFlagManager {
    static let shared = LocalFeatureFlagManager()

    private init() {}

    func isEnabled(_ flag: LocalFeatureFlag) -> Bool {
        switch flag {
        case .webviewDevTool:
            #if DEBUG
                true
            #else
                false
            #endif
        }
    }
}
