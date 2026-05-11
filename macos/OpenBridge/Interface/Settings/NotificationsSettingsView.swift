import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var heartbeatNotificationsBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.showHeartbeatNotifications },
            set: { isEnabled in
                settingsManager.showHeartbeatNotifications = isEnabled
                AnalyticsManager.track(.init(do: .settingsFeatureToggled(feature: "heartbeat_notifications", enabled: isEnabled)))
                Task {
                    await HeartbeatNotificationService.shared.refreshAuthorization(reason: "settings_toggle_changed")
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                SettingInfoBanner(
                    iconName: "app.badge",
                    title: "Notifications",
                    info: "Control native macOS notifications for scheduled task results",
                    backgroundStyle: .init(iconBackground: .gradient(.orange))
                )
            }

            Section(
                footer: Text(
                    "When enabled, OpenBridge shows native macOS banners when a scheduled task finishes and requests notification permission when needed."
                )
            ) {
                TintedToggle("Show scheduled task notifications", isOn: heartbeatNotificationsBinding)
                    .accessibilityIdentifier(AccessibilityID.Settings.notificationsScheduledTaskToggle)
            }
            .tint(settingsManager.systemAccentColor)
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .accessibilityIdentifier(AccessibilityID.Settings.notificationsRoot)
    }
}

#Preview {
    NotificationsSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 600, height: 500)
}
