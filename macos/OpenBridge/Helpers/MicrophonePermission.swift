import AppKit
@preconcurrency import AVFoundation
import Foundation

@MainActor
struct MicrophonePermission {
    init() {}

    var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    @discardableResult
    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            NotificationCenter.default.post(name: .microphonePermissionDidChange, object: nil)
            return granted
        @unknown default:
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
