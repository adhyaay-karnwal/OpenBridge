//
//  SoundsSettingsView.swift
//  OpenBridge
//

import SwiftUI

struct SoundsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var expandedEventType: SoundEventType?

    var body: some View {
        @Bindable var settingsManager = settingsManager
        Form {
            Section {
                SettingInfoBanner(
                    iconName: "speaker.wave.3.fill",
                    title: "Sounds",
                    info: "Configure sound effects for different app events",
                    backgroundStyle: .init(iconBackground: .gradient(.orange))
                )
            }

            Section {
                TintedToggle("Enable sound effects", isOn: $settingsManager.enableSoundEffects)
                    .onChange(of: settingsManager.enableSoundEffects) { _, enable in
                        if enable {
                            SoundsService.preload(SoundType.preloadList)
                            SoundsService.play(.boom)
                        }
                    }
            }

            if settingsManager.enableSoundEffects {
                Section(header: Text("Sound Events")) {
                    ForEach(SoundEventVisibility.availableEvents) { eventType in
                        SoundEventRow(
                            eventType: eventType,
                            config: binding(for: eventType),
                            isExpanded: Binding(
                                get: { expandedEventType == eventType },
                                set: { isExpanded in
                                    expandedEventType = isExpanded ? eventType : nil
                                }
                            )
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sounds")
    }

    private func binding(for eventType: SoundEventType) -> Binding<SoundEventConfig> {
        Binding(
            get: { settingsManager.soundEventSettings.config(for: eventType) },
            set: { newConfig in
                var settings = settingsManager.soundEventSettings
                settings.setConfig(newConfig, for: eventType)
                settingsManager.soundEventSettings = settings
            }
        )
    }
}

// MARK: - Sound Event Row

private struct SoundEventRow: View {
    let eventType: SoundEventType
    @Binding var config: SoundEventConfig
    @Binding var isExpanded: Bool

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { isExpanded && config.isEnabled },
            set: { isExpanded = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eventType.displayName)
                            .font(.system(size: 13))
                        Text(eventType.eventDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: eventType.iconName)
                }
                .labelStyle(
                    SettingItemLabelStyle(
                        style: eventType.iconBackground,
                        containerSize: 28,
                        iconSize: 14, iconCornerRadius: 8
                    )
                )
                .id(eventType.id)

                Spacer()

                TintedToggle(
                    "",
                    isOn: Binding(
                        get: { config.isEnabled },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                config.isEnabled = newValue
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Enable or disable this sound event")
            }
            HStack {
                Text("Sound")
                    .opacity(0.65)
                Spacer()
                SoundTypePicker(selection: $config.soundType)
            }
            .padding(.leading, 36)
            .frame(height: config.isEnabled ? nil : 0, alignment: .top)
            .padding(.top, config.isEnabled ? 8 : 0)
            .clipped()
        }
    }
}

#Preview {
    SoundsSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 500, height: 700)
}
