import AppKit

@MainActor
struct ScreenCapturePermission {
    var isAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestAuthorization() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum FullDiskAccessPermission {
    static var isAuthorized: Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let protectedPath = homeDirectory.appendingPathComponent("Library/Mail")
        return FileManager.default.isReadableFile(atPath: protectedPath.path)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

enum FilesAndFoldersPermission {
    static var isAuthorized: Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            homeDirectory.appendingPathComponent("Desktop"),
            homeDirectory.appendingPathComponent("Documents"),
            homeDirectory.appendingPathComponent("Downloads"),
        ]

        return candidates.allSatisfy { url in
            (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
