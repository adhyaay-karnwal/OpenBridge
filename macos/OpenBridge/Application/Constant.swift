import Foundation

nonisolated enum Constant {
    static let applicationLibraryURL: URL = MainActor.assumeIsolated {
        let url = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first!
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "OpenBridge"
        let urlWithBundleIdentifier = url.appendingPathComponent(
            bundleIdentifier, isDirectory: true
        )
        if !FileManager.default.fileExists(atPath: urlWithBundleIdentifier.path) {
            try? FileManager.default.createDirectory(
                at: urlWithBundleIdentifier,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return urlWithBundleIdentifier
    }

    static let imagesDirectoryURL: URL = {
        let url = applicationLibraryURL.appendingPathComponent("images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        return url
    }()

    static let filesDirectoryURL: URL = {
        let url = applicationLibraryURL.appendingPathComponent("files", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        return url
    }()

    static let temporaryURL: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleIdentifier = MainActor.assumeIsolated {
            Bundle.main.bundleIdentifier ?? "OpenBridge"
        }
        let urlWithBundleIdentifier = url.appendingPathComponent(
            bundleIdentifier, isDirectory: true
        )
        if !FileManager.default.fileExists(atPath: urlWithBundleIdentifier.path) {
            try? FileManager.default.createDirectory(
                at: urlWithBundleIdentifier,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return urlWithBundleIdentifier
    }()
}
