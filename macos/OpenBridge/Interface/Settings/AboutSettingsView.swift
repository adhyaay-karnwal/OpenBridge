//
//  AboutSettingsView.swift
//  OpenBridge
//
//  Created by Claude Code on 11/9/25.
//

import Sparkle
import SwiftUI

struct AboutSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @ObservedObject private var updateManager = SparkleUpdateManager.shared

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    private var displayVersion: String {
        if buildNumber.isEmpty {
            return version
        }
        return "\(version) (\(buildNumber))"
    }

    @State private var showResetAppConfirmation = false
    @State private var isResettingApp = false
    @State private var resetErrorMessage: String?
    @State private var showResetSuccessAlert = false
    @State private var showResetUserDefaultsConfirmation = false
    @State private var chatViewModel = ChatViewModel.shared

    // Agent storage management
    @State private var agentActionInProgress: String?
    @State private var agentActionResult: Result<Int64, Error>?
    @State private var showResetAgentImageConfirmation = false

    // Hidden debug mode activation
    @State private var iconTapCount = 0
    @State private var rippleOrigin: CGPoint = .zero
    @State private var rippleTrigger = 0
    @State private var showDebugModeUnlocked: Bool

    @Binding var navigationPath: NavigationPath

    init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath()), showDebugModeUnlocked: Bool = false) {
        _navigationPath = navigationPath
        _showDebugModeUnlocked = State(initialValue: showDebugModeUnlocked)
    }

    #if DEBUG
        @State private var showResetConfirmation = false
        @State private var isResettingDatabase = false
    #endif

    var body: some View {
        @Bindable var settingsManager = settingsManager
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .modifier(RippleEffect(at: rippleOrigin, trigger: rippleTrigger, amplitude: 6))
                        .onTapGesture { location in
                            handleIconTap(at: location)
                        }

                    Text("About")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Learn more about OpenBridge")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                LabeledContent {
                    Text(displayVersion)
                } label: {
                    Text("Version")
                }
                LabeledContent {
                    Button(action: checkForUpdates) {
                        if updateManager.isDownloading {
                            if let version = updateManager.downloadingVersion {
                                Text("Downloading Update (\(version))…")
                            } else {
                                Text("Downloading Update…")
                            }
                        } else {
                            Text("Check for Updates")
                        }
                    }
                    .disabled(updateManager.isDownloading)
                } label: {
                    Text("Check for Updates")
                }
                .buttonStyle(.bordered)
            }

            Section {
                #if DEBUG
                    TintedToggle("Enable debug mode", isOn: $settingsManager.enableDebugMode)
                #else
                    if showDebugModeUnlocked || settingsManager.enableDebugMode {
                        TintedToggle("Enable debug mode", isOn: $settingsManager.enableDebugMode)
                    }
                #endif
                TintedToggle("Auto check for updates", isOn: $settingsManager.autoUpdate)
            }
            .tint(settingsManager.systemAccentColor)

            if settingsManager.enableDebugMode {
                Section {
                    NavigationLink(value: SettingsDestination.logViewer) {
                        Label("Log Viewer", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }

            #if DEBUG || STAGING
                if settingsManager.enableDebugMode {
                    Section(String(localized: "Notch")) {
                        NavigationLink(value: SettingsDestination.notchDebug) {
                            Label(String(localized: "Notch Debug"), systemImage: "rectangle.topthird.inset.filled")
                        }

                        Text(String(localized: "Tune notch geometry and animations live. Changes stay in memory only and reset when OpenBridge relaunches."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif

            Section("Agent") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage")
                        .font(.headline)
                    Text("Manage VM overlay images. Clear Cache removes unused images while keeping the current session. Reset Image deletes all images including the current one (requires app restart).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await performAgentAction("cache") {
                                try await AgentSessionManager.shared.resetAgentImage(includeCurrentImage: false)
                            }
                        }
                    } label: {
                        if agentActionInProgress == "cache" {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(agentActionInProgress != nil)

                    Button {
                        showResetAgentImageConfirmation = true
                    } label: {
                        if agentActionInProgress == "reset" {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Reset Image", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(agentActionInProgress != nil)
                    .confirmationDialog(
                        "Reset Agent Image?",
                        isPresented: $showResetAgentImageConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset and Restart", role: .destructive) {
                            Task { await resetAgentImageAndRestart() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all VM overlay images and restart the app to apply changes.")
                    }
                }

                if let result = agentActionResult {
                    switch result {
                    case let .success(bytesFreed):
                        Text("Freed: \(formatBytes(bytesFreed))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case let .failure(error):
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            #if DEBUG
                if settingsManager.enableDebugMode {
                    Section {
                        Button {
                            showResetAppConfirmation = true
                        } label: {
                            Label(
                                "Reset App",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isResettingApp)
                    }
                }
            #endif

            #if DEBUG || STAGING
                if settingsManager.enableDebugMode {
                    Section("Debug Agent Template") {
                        Picker("Template Override", selection: $settingsManager.lastSelectedAgentTemplateID) {
                            Text("Session default").tag("")
                            ForEach(chatViewModel.groupedTemplateOverridesByProvider, id: \.provider) { group in
                                Section(group.provider) {
                                    ForEach(group.templates, id: \.templateId) { template in
                                        Text(chatViewModel.templateOverrideLabel(for: template)).tag(template.templateId)
                                    }
                                }
                            }
                        }

                        Button("Refresh Templates") {
                            Task {
                                await chatViewModel.refreshAvailableTemplates()
                            }
                        }
                        .buttonStyle(.bordered)

                        Text("Debug-only override for local agent chat requests. Select a bundled template by template ID.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif

            #if DEBUG
                if settingsManager.enableDebugMode {
                    Section("Update Testing") {
                        Button(String(localized: "Show Chat Update Notification")) {
                            Windows.shared.open(.chat)
                            SparkleUpdateManager.shared.presentDebugChatUpdateNotification()
                        }
                        .buttonStyle(.bordered)

                        Text("Shows the native chat window update notification without waiting for Sparkle to find a real update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif

            #if DEBUG
                if settingsManager.enableDebugMode {
                    Section("macOS 26 Compatibility") {
                        TintedToggle(
                            "Force pre-macOS 26 UI",
                            isOn: $settingsManager.useLegacyMacOS26UI
                        )

                        Text("Disables Liquid Glass and other macOS 26-specific UI so you can verify the legacy experience on newer systems.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Glass Material") {
                        Picker("Background Material", selection: $settingsManager.glassMaterialMode) {
                            ForEach(GlassMaterialMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(settingsManager.useLegacyMacOS26UI)

                        Text(
                            settingsManager.useLegacyMacOS26UI
                                ? "Forced legacy mode overrides the background material setting."
                                : "Choose between legacy material (pre-macOS 26) and Liquid Glass (macOS 26+). Auto will detect based on OS version."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Section("Debug Tools") {
                        Button("Reveal Application Directory") {
                            revealDatabaseFileInFinder()
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showResetConfirmation = true
                        } label: {
                            Label(
                                "Reset Local Database",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isResettingDatabase)

                        Button {
                            showResetUserDefaultsConfirmation = true
                        } label: {
                            Label(
                                "Reset User Defaults",
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .alert(
            "Reset App?",
            isPresented: $showResetAppConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {
                    showResetAppConfirmation = false
                }
                Button("Reset", role: .destructive) {
                    showResetAppConfirmation = false
                    performAppReset()
                }
                .disabled(isResettingApp)
            },
            message: {
                Text("This will delete all local data including chat history, settings, and user preferences. You need to restart the app to apply the changes.")
            }
        )
        .alert(
            "Reset Failed",
            isPresented: Binding(
                get: { resetErrorMessage != nil },
                set: { if !$0 { resetErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    resetErrorMessage = nil
                }
            },
            message: {
                Text(resetErrorMessage ?? "Unknown error")
            }
        )
        .alert(
            "Reset Complete",
            isPresented: $showResetSuccessAlert,
            actions: {
                Button("OK") {
                    showResetSuccessAlert = false
                }
            },
            message: {
                Text("All app data has been reset. Please restart the app to apply the changes.")
            }
        )
        #if DEBUG
        .alert(
                "Reset Database?",
                isPresented: $showResetConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {
                        showResetConfirmation = false
                    }
                    Button("Reset", role: .destructive) {
                        showResetConfirmation = false
                        performDatabaseReset()
                    }
                    .disabled(isResettingDatabase)
                },
                message: {
                    Text(
                        "This will delete all local chat data. You need to restart OpenBridge to apply the changes."
                    )
                }
            )
            .alert(
                "Reset Failed",
                isPresented: Binding(
                    get: { resetErrorMessage != nil },
                    set: { if !$0 { resetErrorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        resetErrorMessage = nil
                    }
                },
                message: {
                    Text(resetErrorMessage ?? "Unknown error")
                }
            )
            .alert(
                "Reset User Defaults?",
                isPresented: $showResetUserDefaultsConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {
                        showResetUserDefaultsConfirmation = false
                    }
                    Button("Reset", role: .destructive) {
                        showResetUserDefaultsConfirmation = false
                        performUserDefaultsReset()
                    }
                },
                message: {
                    Text(
                        "This will clear all app UserDefaults storage. You may need to restart OpenBridge for all changes to take effect."
                    )
                }
            )
        #endif
    }

    private func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    private func handleIconTap(at location: CGPoint) {
        // Trigger ripple effect at tap location
        rippleOrigin = location
        rippleTrigger += 1

        // Count taps for debug mode unlock
        iconTapCount += 1
        if iconTapCount >= 5 {
            showDebugModeUnlocked = true
            iconTapCount = 0
        }

        // Reset tap count after 2 seconds of inactivity
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [iconTapCount] in
            if self.iconTapCount == iconTapCount {
                self.iconTapCount = 0
            }
        }
    }

    private func performAppReset() {
        guard isResettingApp == false else { return }
        isResettingApp = true

        Task {
            do {
                try await MainActor.run {
                    try AppResetManager.resetApp()
                    isResettingApp = false
                    showResetSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    resetErrorMessage = error.localizedDescription
                    isResettingApp = false
                }
            }
        }
    }

    private func performAgentAction(_ actionId: String, action: @escaping () async throws -> Int64) async {
        agentActionInProgress = actionId
        agentActionResult = nil

        do {
            let bytesFreed = try await action()
            agentActionResult = .success(bytesFreed)
        } catch {
            agentActionResult = .failure(error)
        }

        agentActionInProgress = nil
    }

    private func resetAgentImageAndRestart() async {
        agentActionInProgress = "reset"
        agentActionResult = nil

        do {
            _ = try await AgentSessionManager.shared.resetAgentImage(includeCurrentImage: true)
            await MainActor.run {
                restartApp()
            }
        } catch {
            agentActionResult = .failure(error)
            agentActionInProgress = nil
        }
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path] // -n opens a new instance
        task.launch()

        // Give the new process time to start before terminating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Debug Helpers

#if DEBUG
    private extension AboutSettingsView {
        func revealDatabaseFileInFinder() {
            NSWorkspace.shared.activateFileViewerSelecting([Constant.applicationLibraryURL])
        }

        func performDatabaseReset() {
            guard isResettingDatabase == false else { return }
            isResettingDatabase = true

            Task {
                do {
                    try await MainActor.run {
                        try Database.shared.reset()
                    }
                } catch {
                    await MainActor.run {
                        resetErrorMessage = error.localizedDescription
                        isResettingDatabase = false
                    }
                }
            }
        }

        func performUserDefaultsReset() {
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            UserDefaults.standard.synchronize()
        }
    }
#endif
