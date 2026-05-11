import AppKit
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    private var languages = Bundle.main.localizations.filter { $0 != "Base" }

    @State private var cachedLaunchAtLogin: Bool = false

    var body: some View {
        @Bindable var settingsManager = settingsManager
        Form {
            Section {
                SettingInfoBanner(
                    iconName: "gearshape",
                    title: "General",
                    info: "Configure the app's fundamental features and behavior",
                    backgroundStyle: .init(iconBackground: .gradient(.blue))
                )
            }

            Section {
                VStack(alignment: .leading, spacing: 24) {
                    // Appearance Setting
                    SettingOptionPicker(
                        title: "Appearance",
                        options: Appearance.allCases,
                        selection: $settingsManager.appearance,
                        animateSelection: false
                    ) { appearance, isSelected in
                        appearancePreview(for: appearance, isSelected: isSelected)
                    } label: { appearance, _ in
                        appearance.displayName
                    }
                    .onChange(of: settingsManager.appearance) { _, newAppearance in
                        AnalyticsManager.track(.init(do: .settingsAppearanceChanged(appearance: newAppearance.rawValue)))
                        NSApp.appearance = newAppearance.nsAppearance
                    }

                    Divider()

                    // Accent Color Setting
                    SettingOptionPicker(
                        title: "Accent color",
                        options: SystemAccentColor.allCases,
                        selection: $settingsManager.accentColorName
                    ) { color, isSelected in
                        Circle()
                            .fill(color.color)
                            .frame(width: 24, height: 24, alignment: .center)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(NSColor.windowBackgroundColor), lineWidth: isSelected ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(settingsManager.accentColor, lineWidth: isSelected ? 3 : 0)
                                    .padding(-2)
                            )
                    } label: { color, isSelected in
                        isSelected ? color.displayName : nil
                    }
                    .onChange(of: settingsManager.accentColorName) { _, newColor in
                        AnalyticsManager.track(.init(do: .settingsAccentColorChanged(color: newColor.rawValue)))
                    }
                }
                .padding(.vertical, 8)
            }

            Section(footer: Text("Some languages are translated using AI. You can correct them in the local app resources.")) {
                languageSetting
            }

            Section {
                SettingOptionPicker(
                    title: "App icon",
                    options: AppIcon.allCases,
                    selection: $settingsManager.appIcon
                ) { icon, isSelected in
                    iconView(for: icon, isSelected: isSelected)
                } label: { icon, isSelected in
                    isSelected ? icon.displayName : nil
                }
                .onChange(of: settingsManager.appIcon) { _, newIcon in
                    newIcon.apply()
                }
            }

            Section(footer: Text(String(localized: "OpenBridge disables the bundled Local VM environment by default on machines with less than 15 GB of memory. When enabled, the local agent can use it."))) {
                TintedToggle("Enable Local VM environment", isOn: $settingsManager.enableLocalVMEnvironment)
                    .onChange(of: settingsManager.enableLocalVMEnvironment) { _, _ in
                        AgentSessionManager.shared.refreshConnectorConfiguration()
                    }
            }
            .tint(settingsManager.systemAccentColor)

            Section(footer: Text("Mounted folders are visible inside the Local VM sandbox. Writable mounts use the review flow before changes are applied back to this Mac.")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(settingsManager.localVMMounts.indices, id: \.self) { index in
                        localVMMountRow(index: index)
                        if index != settingsManager.localVMMounts.indices.last {
                            Divider()
                        }
                    }

                    HStack {
                        Button("Add Folder") {
                            addLocalVMMount()
                        }
                        Button("Reset") {
                            resetLocalVMMounts()
                        }
                        .disabled(settingsManager.localVMMounts == LocalVMMount.defaultMounts())
                    }
                }
                .onChange(of: settingsManager.localVMMounts) { _, _ in
                    AgentSessionManager.shared.refreshConnectorConfiguration()
                }
            }
            .tint(settingsManager.systemAccentColor)

            Section(footer: Text("Change Show dock icon, need to restart the app.")) {
                TintedToggle("Launch OpenBridge at login", isOn: $cachedLaunchAtLogin)
                    .onAppear {
                        Task.detached {
                            let value = LaunchAtLogin.isEnabled
                            await MainActor.run { cachedLaunchAtLogin = value }
                        }
                    }
                    .onChange(of: cachedLaunchAtLogin) { _, _ in
                        LaunchAtLogin.isEnabled = cachedLaunchAtLogin
                    }
                TintedToggle("Show menu bar icon", isOn: $settingsManager.showMenuBarIcon)
                    .onChange(of: settingsManager.showMenuBarIcon) { _, show in
                        if show {
                            BarMenuCoordinator.shared.rebuild()
                        } else {
                            BarMenuCoordinator.shared.hide()
                        }
                    }
                TintedToggle("Show dock icon", isOn: $settingsManager.showDockIcon)
            }
            .tint(settingsManager.systemAccentColor)
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

extension GeneralSettingsView {
    @ViewBuilder
    private func appearancePreview(for appearance: Appearance, isSelected: Bool) -> some View {
        let previewContent = switch appearance {
        case .light: Image("AppearanceLight")
        case .dark: Image("AppearanceDark")
        case .system: Image("AppearanceAuto")
        }

        previewContent
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? settingsManager.accentColor : Color.clear, lineWidth: 3)
            )
    }

    private func iconView(for icon: AppIcon, isSelected: Bool) -> some View {
        Image(nsImage: icon.image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 48, height: 48, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(NSColor.windowBackgroundColor), lineWidth: isSelected ? 2 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(settingsManager.accentColor, lineWidth: isSelected ? 3 : 0)
                    .padding(-2)
            )
    }

    @ViewBuilder
    private var languageSetting: some View {
        @Bindable var settingsManager = settingsManager
        Picker("Language", selection: $settingsManager.language) {
            ForEach(languages, id: \.self) { code in
                Text(displayName(for: code)).tag(code)
            }
        }
    }

    private func displayName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    @ViewBuilder
    private func localVMMountRow(index: Int) -> some View {
        @Bindable var settingsManager = settingsManager
        let mount = settingsManager.localVMMounts[index]

        HStack(alignment: .center, spacing: 12) {
            Image(systemName: mount.readOnly ? "lock" : "folder")
                .foregroundStyle(settingsManager.systemAccentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(mount.hostPath)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if mount.vmPath != mount.hostPath {
                    Text("Mounted at \(mount.vmPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            Toggle("Read-only", isOn: $settingsManager.localVMMounts[index].readOnly)
                .toggleStyle(.switch)
                .labelsHidden()

            Button {
                removeLocalVMMount(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(settingsManager.localVMMounts.count <= 1)
        }
    }

    private func addLocalVMMount() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Add")

        guard panel.runModal() == .OK else { return }
        var nextMounts = settingsManager.localVMMounts
        let existingPaths = Set(nextMounts.map(\.hostPath))
        for url in panel.urls {
            let path = LocalVMMount.normalizedPath(url.path)
            guard !existingPaths.contains(path) else { continue }
            nextMounts.append(LocalVMMount(hostPath: path))
        }
        settingsManager.localVMMounts = nextMounts
    }

    private func removeLocalVMMount(at index: Int) {
        guard settingsManager.localVMMounts.indices.contains(index) else { return }
        guard settingsManager.localVMMounts.count > 1 else { return }
        var nextMounts = settingsManager.localVMMounts
        nextMounts.remove(at: index)
        settingsManager.localVMMounts = nextMounts
    }

    private func resetLocalVMMounts() {
        settingsManager.localVMMounts = LocalVMMount.defaultMounts()
    }
}

#Preview {
    GeneralSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 800)
}
