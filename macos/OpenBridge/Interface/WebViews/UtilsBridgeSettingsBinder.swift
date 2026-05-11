import Foundation
import Observation

@MainActor
final class UtilsBridgeSettingsBinder {
    private var isCancelled = false

    func start(bridge: UtilsBridge) {
        broadcast(bridge: bridge)
        observe(bridge: bridge)
    }

    func cancel() {
        isCancelled = true
    }

    private func observe(bridge: UtilsBridge) {
        guard !isCancelled else { return }

        withObservationTracking {
            _ = SettingsManager.shared.enableDebugMode
            _ = SettingsManager.shared.accentColorName
            _ = SettingsManager.shared.language
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                self.broadcast(bridge: bridge)
                self.observe(bridge: bridge)
            }
        }
    }

    private func broadcast(bridge: UtilsBridge) {
        bridge.setDebugMode(SettingsManager.shared.enableDebugMode)

        let foregroundColor = SettingsManager.shared.accentColorForegroundColor.toHexString() ?? ""
        let backgroundColor = SettingsManager.shared.accentColor.toHexString() ?? ""
        bridge.setAccentForegroundColor(foregroundColor)
        bridge.setAccentBackgroundColor(backgroundColor)

        let language = SettingsManager.shared.language
        if !language.isEmpty {
            bridge.setLanguage(language)
        }
    }
}
