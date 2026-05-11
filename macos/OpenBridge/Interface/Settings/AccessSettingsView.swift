//
//  AccessSettingsView.swift
//  OpenBridge
//
//  Created by Claude on 11/13/25.
//

import AppKit
@preconcurrency import AVFoundation
import SwiftUI

struct AccessSettingsView: View {
    @State private var isScreenAuthorized = ScreenCapturePermission().isAuthorized
    @State private var microphoneStatus = MicrophonePermission().authorizationStatus
    @State private var isRequestingMicrophone = false
    @State private var hasFilesAndFoldersAccess = FilesAndFoldersPermission.isAuthorized
    @State private var hasFullDiskAccess = FullDiskAccessPermission.isAuthorized

    var body: some View {
        Form {
            Section {
                bannerView
            }

            Section {
                screenRecordingSettingView
                microphoneSettingView
                // filesAndFoldersView
                fullDiskAccessView
            }
        }
        .navigationTitle("Access")
        .onAppear {
            refreshStatuses()
        }
        .onReceiveNotification(name: .microphonePermissionDidChange) { _ in
            refreshStatuses()
        }
        .onReceiveNotification(name: NSApplication.didBecomeActiveNotification) { _ in
            refreshStatuses()
        }
        .formStyle(.grouped)
    }

    private var bannerView: some View {
        SettingInfoBanner(
            iconName: "checkerboard.shield",
            title: "Access",
            info: "Manage permissions and security settings",
            backgroundStyle: .init(iconBackground: .gradient(.green))
        )
        .padding(.bottom, 8)
    }

    private var screenRecordingSettingView: some View {
        AccessSettingItem(
            iconName: "record.circle",
            title: "Screen Recording",
            statusText: isScreenAuthorized ? String(localized: "Enabled") : String(localized: "Disabled"),
            statusColor: isScreenAuthorized ? .green : .orange
        ) {
            EmptyView()
        } actions: {
            if !isScreenAuthorized {
                Button(String(localized: "Enable")) {
                    ScreenCapturePermission().openSystemSettings()
                }
            }

            Button(String(localized: "Refresh")) {
                refreshStatuses()
            }
            .buttonStyle(.pillOutlined)
            .accessibilityIdentifier(AccessibilityID.Settings.accessScreenRecordingRefreshButton)
        }
    }

    private var microphoneSettingView: some View {
        AccessSettingItem(
            iconName: "microphone.fill",
            title: "Microphone",
            statusText: microphoneStatusText,
            statusColor: microphoneStatusColor
        ) {
            EmptyView()
        } actions: {
            if microphoneStatus != .authorized {
                Button {
                    requestMicrophoneAccess()
                } label: {
                    if isRequestingMicrophone {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Enable")
                    }
                }
                .disabled(isRequestingMicrophone)
            }

            Button(String(localized: "Refresh")) {
                refreshStatuses()
            }
            .buttonStyle(.pillOutlined)
        }
    }

    private var filesAndFoldersView: some View {
        AccessSettingItem(
            iconName: "folder",
            title: "Files and Folders",
            statusText: hasFilesAndFoldersAccess ? String(localized: "Enabled") : String(localized: "Disabled"),
            statusColor: hasFilesAndFoldersAccess ? .green : .orange
        ) {
            Text("Manage access to Desktop, Documents, Downloads and other folders.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } actions: {
            if !hasFilesAndFoldersAccess {
                Button(String(localized: "Enable")) {
                    FilesAndFoldersPermission.openSystemSettings()
                }
            }

            Button(String(localized: "Refresh")) {
                refreshStatuses()
            }
            .buttonStyle(.pillOutlined)
        }
    }

    private var fullDiskAccessView: some View {
        AccessSettingItem(
            iconName: "opticaldiscdrive",
            title: "Full Disk Access",
            statusText: hasFullDiskAccess ? String(localized: "Enabled") : String(localized: "Disabled"),
            statusColor: hasFullDiskAccess ? .green : .orange
        ) {
            Text("Required for accessing files in protected locations. You may need to manually add OpenBridge to the list.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } actions: {
            if !hasFullDiskAccess {
                Button(String(localized: "Enable")) {
                    FullDiskAccessPermission.openSystemSettings()
                }
            }

            Button(String(localized: "Refresh")) {
                refreshStatuses()
            }
            .buttonStyle(.pillOutlined)
        }
    }
}

// MARK: - Permissions Helpers

private extension AccessSettingsView {
    var microphoneStatusText: String {
        switch microphoneStatus {
        case .authorized:
            return String(localized: "Enabled")
        case .denied:
            return String(localized: "Denied")
        case .restricted:
            return String(localized: "Restricted")
        case .notDetermined:
            return String(localized: "Not Determined")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    var microphoneStatusColor: Color {
        switch microphoneStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    func refreshStatuses() {
        isScreenAuthorized = ScreenCapturePermission().isAuthorized
        microphoneStatus = MicrophonePermission().authorizationStatus
        hasFilesAndFoldersAccess = FilesAndFoldersPermission.isAuthorized
        hasFullDiskAccess = FullDiskAccessPermission.isAuthorized
    }

    func requestMicrophoneAccess() {
        guard !isRequestingMicrophone else { return }

        let microphonePermission = MicrophonePermission()
        switch microphonePermission.authorizationStatus {
        case .authorized:
            refreshStatuses()
            return
        case .denied, .restricted:
            microphonePermission.openSystemSettings()
            return
        case .notDetermined:
            break
        @unknown default:
            return
        }

        isRequestingMicrophone = true
        Task { @MainActor in
            defer { isRequestingMicrophone = false }
            _ = await microphonePermission.requestAccess()
            refreshStatuses()
        }
    }
}

#Preview {
    AccessSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 600, height: 800)
}
