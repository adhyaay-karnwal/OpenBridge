import ApplicationServices
import Combine
import JSBridge
import SwiftUI

/// TCC helpers used by OpenBridge-owned app features and embedded web views.
enum ComputerUsePermissionService {
    enum PermissionPane: String {
        case accessibility
        case inputMonitoring = "input_monitoring"
        case screenRecording = "screen_recording"
    }

    static func openSystemSettings(for rawPane: String) throws {
        guard let pane = PermissionPane(rawValue: rawPane) else {
            throw RuntimeError("Unsupported computer use permission pane: \(rawPane)")
        }
        guard let url = settingsURL(for: pane) else {
            throw RuntimeError("Unable to open System Settings for \(rawPane)")
        }
        NSWorkspace.shared.open(url)
    }

    static func status() -> [SessionHistoryMessage.ComputerUsePermissionPane] {
        [
            SessionHistoryMessage.ComputerUsePermissionPane(
                pane: PermissionPane.accessibility.rawValue,
                granted: AXIsProcessTrusted()
            ),
            SessionHistoryMessage.ComputerUsePermissionPane(
                pane: PermissionPane.screenRecording.rawValue,
                granted: CGPreflightScreenCaptureAccess()
            ),
        ]
    }

    @discardableResult
    static func request(_ rawPane: String) throws -> [SessionHistoryMessage.ComputerUsePermissionPane] {
        guard let pane = PermissionPane(rawValue: rawPane) else {
            throw RuntimeError("Unsupported computer use permission pane: \(rawPane)")
        }

        switch pane {
        case .accessibility:
            let options = [
                "AXTrustedCheckOptionPrompt": true,
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            try openSystemSettings(for: rawPane)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            if !CGPreflightScreenCaptureAccess() {
                try openSystemSettings(for: rawPane)
            }
        case .inputMonitoring:
            try openSystemSettings(for: rawPane)
        }

        return status()
    }

    private static func settingsURL(for pane: PermissionPane) -> URL? {
        let urlString = switch pane {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        return URL(string: urlString)
    }
}

/// OpenBridge for utility functions accessible from JavaScript
@MainActor
@JSBridge
class UtilsBridge {
    func openURL(_ urlString: String) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw RuntimeError("Invalid URL: \(urlString)")
        }
        NSWorkspace.shared.open(url)
    }

    /// Check if debug mode is enabled
    func isDebugMode() -> Bool {
        SettingsManager.shared.enableDebugMode
    }

    func getAccentBackgroundColor() -> String {
        SettingsManager.shared.accentColor.toHexString() ?? ""
    }

    func getAccentForegroundColor() -> String {
        SettingsManager.shared.accentColorForegroundColor.toHexString() ?? ""
    }

    func getLanguage() -> String {
        SettingsManager.shared.language
    }

    func saveFile(filename: String, content: String, mimeType: String) throws {
        _ = mimeType
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw RuntimeError("Cannot access Downloads directory")
        }

        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            throw RuntimeError("Failed to save file: \(error.localizedDescription)")
        }
    }

    func getUsername() -> String {
        NSFullUserName()
    }

    func openPaywall() {
        SettingsNavigation.shared.navigate(to: .general)
        Windows.shared.open(.settings)
    }

    func getMacOSMajorVersion() -> Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    func saveImage(imageURL: String, filename: String?) async throws {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RuntimeError("Image URL is empty")
        }

        let image = try await UtilsBridgeImageSaver.resolveImage(from: trimmed)
        let savedURL = try UtilsBridgeImageSaver.saveImage(image, preferredFilename: filename)
        NSWorkspace.shared.open(savedURL)
    }

    // MARK: - Swift → JS events

    @EmitEvent
    func setDebugMode(_ enabled: Bool)

    @EmitEvent
    func setAccentForegroundColor(_ color: String)

    @EmitEvent
    func setAccentBackgroundColor(_ color: String)

    @EmitEvent
    func setLanguage(_ language: String)

    @EmitEvent
    func setUsername(_ username: String)
}

/// Helper view to handle settings changes and broadcast them to the JavaScript side
struct UtilsBridgeHelperView: View {
    var bridge: UtilsBridge

    var body: some View {
        Color.clear
            .onChange(of: SettingsManager.shared.enableDebugMode) { _, _ in
                handleDebugModeChange()
            }
            .onChange(of: SettingsManager.shared.accentColor) { _, _ in
                handleAccentColorChange()
            }
            .onChange(of: SettingsManager.shared.language) { _, _ in
                handleLanguageChange()
            }
    }

    private func handleDebugModeChange() {
        let enabled = SettingsManager.shared.enableDebugMode
        bridge.setDebugMode(enabled)
    }

    private func handleAccentColorChange() {
        let foregroundColor = SettingsManager.shared.accentColorForegroundColor.toHexString()
        let backgroundColor = SettingsManager.shared.accentColor.toHexString()
        bridge.setAccentForegroundColor(foregroundColor ?? "")
        bridge.setAccentBackgroundColor(backgroundColor ?? "")
    }

    private func handleLanguageChange() {
        let language = SettingsManager.shared.language
        guard !language.isEmpty else { return }
        bridge.setLanguage(language)
    }

    private func handleUsernameChange() {
        let username = NSFullUserName()
        guard !username.isEmpty else { return }
        bridge.setUsername(username)
    }
}

private struct ResolvedBridgeImage {
    let data: Data
    let filename: String
}

private enum UtilsBridgeImageSaver {
    private static let imageExtensionsByMIMEType: [String: String] = [
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/svg+xml": "svg",
        "image/heic": "heic",
        "image/heif": "heif",
        "image/bmp": "bmp",
        "image/tiff": "tiff",
        "image/avif": "avif",
    ]

    static func resolveImage(from source: String) async throws -> ResolvedBridgeImage {
        if source.hasPrefix("data:") {
            return try resolveDataURL(source)
        }

        if let url = URL(string: source),
           let scheme = url.scheme?.lowercased()
        {
            switch scheme {
            case "http", "https":
                return try await downloadImage(from: url)
            case "file":
                return try readLocalImage(from: url)
            default:
                break
            }
        }

        if let data = Data(base64Encoded: source, options: .ignoreUnknownCharacters) {
            return try makeImage(data: data, mimeType: nil, suggestedFilename: nil)
        }

        throw RuntimeError("Unsupported image source")
    }

    static func saveImage(_ image: ResolvedBridgeImage, preferredFilename: String?) throws -> URL {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw RuntimeError("Cannot access Downloads directory")
        }

        let fileURL = uniqueDestinationURL(in: downloadsURL, filename: preferredFilename ?? image.filename)

        do {
            try image.data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw RuntimeError("Failed to save image: \(error.localizedDescription)")
        }
    }

    private static func resolveDataURL(_ source: String) throws -> ResolvedBridgeImage {
        guard let separatorIndex = source.firstIndex(of: ",") else {
            throw RuntimeError("Invalid image data URL")
        }

        let metadata = source[..<separatorIndex]
        let payload = source[source.index(after: separatorIndex)...]
        let mimeType = metadata
            .dropFirst("data:".count)
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
        let isBase64 = metadata.localizedCaseInsensitiveContains(";base64")

        let data: Data?
        if isBase64 {
            data = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters)
        } else {
            let decodedPayload = String(payload).removingPercentEncoding ?? String(payload)
            data = decodedPayload.data(using: .utf8)
        }

        guard let data else {
            throw RuntimeError("Invalid image data URL payload")
        }

        return try makeImage(data: data, mimeType: mimeType, suggestedFilename: nil)
    }

    private static func downloadImage(from url: URL) async throws -> ResolvedBridgeImage {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200 ..< 300).contains(httpResponse.statusCode)
            {
                throw RuntimeError("Failed to download image: HTTP \(httpResponse.statusCode)")
            }

            return try makeImage(
                data: data,
                mimeType: response.mimeType,
                suggestedFilename: response.suggestedFilename ?? url.lastPathComponent
            )
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError("Failed to download image: \(error.localizedDescription)")
        }
    }

    private static func readLocalImage(from url: URL) throws -> ResolvedBridgeImage {
        do {
            let data = try Data(contentsOf: url)
            return try makeImage(data: data, mimeType: nil, suggestedFilename: url.lastPathComponent)
        } catch {
            throw RuntimeError("Failed to read image: \(error.localizedDescription)")
        }
    }

    private static func makeImage(
        data: Data,
        mimeType: String?,
        suggestedFilename: String?
    ) throws -> ResolvedBridgeImage {
        if isSVG(data: data, mimeType: mimeType, filename: suggestedFilename) {
            return ResolvedBridgeImage(data: data, filename: normalizedFilename(suggestedFilename, fallbackExtension: "svg"))
        }

        if let ext = filenameExtension(from: suggestedFilename) ?? imageExtension(for: mimeType) {
            return ResolvedBridgeImage(data: data, filename: normalizedFilename(suggestedFilename, fallbackExtension: ext))
        }

        guard let image = NSImage(data: data),
              let pngData = image.pngData()
        else {
            throw RuntimeError("Unsupported image data")
        }

        return ResolvedBridgeImage(data: pngData, filename: normalizedFilename(suggestedFilename, fallbackExtension: "png"))
    }

    private static func isSVG(data: Data, mimeType: String?, filename: String?) -> Bool {
        if mimeType?.lowercased() == "image/svg+xml" {
            return true
        }
        if filenameExtension(from: filename)?.lowercased() == "svg" {
            return true
        }
        return String(bytes: data.prefix(512), encoding: .utf8)?
            .lowercased()
            .contains("<svg") ?? false
    }

    private static func imageExtension(for mimeType: String?) -> String? {
        guard let normalizedMimeType = mimeType?.lowercased() else {
            return nil
        }

        return imageExtensionsByMIMEType[normalizedMimeType]
    }

    private static func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let baseName = filenameBaseName(from: filename) ?? "image"
        let ext = filenameExtension(from: filename) ?? "png"
        let fileManager = FileManager.default

        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        guard !fileManager.fileExists(atPath: candidate.path) else {
            for index in 1 ... 999 {
                candidate = directory.appendingPathComponent("\(baseName)_\(index).\(ext)")
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            let suffix = UUID().uuidString.prefix(8)
            return directory.appendingPathComponent("\(baseName)_\(suffix).\(ext)")
        }

        return candidate
    }

    private static func normalizedFilename(_ filename: String?, fallbackExtension: String) -> String {
        let sanitized = sanitizedFilename(filename)
        let baseName = filenameBaseName(from: sanitized) ?? "image"
        let ext = filenameExtension(from: sanitized) ?? fallbackExtension
        return "\(baseName).\(ext)"
    }

    private static func filenameBaseName(from filename: String?) -> String? {
        guard let filename else { return nil }

        let baseName = (filename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? nil : baseName
    }

    private static func filenameExtension(from filename: String?) -> String? {
        guard let filename else { return nil }

        let ext = (filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext
    }

    private static func sanitizedFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }

        let lastPathComponent = (filename as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lastPathComponent.isEmpty else { return nil }

        let invalidCharacters = CharacterSet(charactersIn: "/\\:\n\r\t")
        let sanitizedScalars = lastPathComponent.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : Character(scalar)
        }
        let sanitized = String(sanitizedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}
