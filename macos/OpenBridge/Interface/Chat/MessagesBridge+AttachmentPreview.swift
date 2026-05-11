import CryptoKit
import Foundation
import UniformTypeIdentifiers

actor ChatAttachmentPreviewStore {
    private static let previewRootDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openbridge/tmp/preview", isDirectory: true)

    private let fileManager = FileManager.default
    private let logger = Logger.ui
    private let baseDirectoryURL: URL
    private var cachedFileURLs: [String: URL] = [:]
    private var inFlightDownloads: [String: Task<URL, Error>] = [:]

    init(namespace: String = UUID().uuidString) {
        baseDirectoryURL = Self.previewRootDirectoryURL
            .appendingPathComponent(namespace, isDirectory: true)
    }

    func prepare(source: String, fileName: String?, mimeType: String?) async throws {
        _ = try await fileURL(source: source, fileName: fileName, mimeType: mimeType)
    }

    func fileURL(source: String, fileName: String?, mimeType: String?) async throws -> URL {
        let cacheKey = Self.cacheKey(source: source, fileName: fileName, mimeType: mimeType)

        if let cachedFileURL = cachedFileURLs[cacheKey],
           fileManager.fileExists(atPath: cachedFileURL.path)
        {
            return cachedFileURL
        }

        if let task = inFlightDownloads[cacheKey] {
            return try await task.value
        }

        let baseDirectoryURL = baseDirectoryURL
        let task = Task<URL, Error> {
            try await Self.materializeFile(
                source: source,
                fileName: fileName,
                mimeType: mimeType,
                cacheKey: cacheKey,
                baseDirectoryURL: baseDirectoryURL
            )
        }
        inFlightDownloads[cacheKey] = task

        do {
            let localFileURL = try await task.value
            cachedFileURLs[cacheKey] = localFileURL
            inFlightDownloads.removeValue(forKey: cacheKey)
            return localFileURL
        } catch {
            inFlightDownloads.removeValue(forKey: cacheKey)
            throw error
        }
    }

    func clear() {
        let tasks = Array(inFlightDownloads.values)
        inFlightDownloads.removeAll()
        cachedFileURLs.removeAll()
        tasks.forEach { $0.cancel() }

        guard fileManager.fileExists(atPath: baseDirectoryURL.path) else { return }

        do {
            try fileManager.removeItem(at: baseDirectoryURL)
        } catch {
            logger.error("Failed to clear attachment preview cache: \(error.localizedDescription)")
        }
    }

    static func clearAllPreviewDirectories() {
        let fileManager = FileManager.default
        let logger = Logger.ui
        let previewRootURL = Self.previewRootDirectoryURL

        guard fileManager.fileExists(atPath: previewRootURL.path) else { return }

        do {
            try fileManager.removeItem(at: previewRootURL)
        } catch {
            logger.error("Failed to clear preview root directory: \(error.localizedDescription)")
        }
    }
}

private extension ChatAttachmentPreviewStore {
    struct ResolvedPreviewData {
        let data: Data
        let fileName: String?
        let mimeType: String?
    }

    static func materializeFile(
        source: String,
        fileName: String?,
        mimeType: String?,
        cacheKey: String,
        baseDirectoryURL: URL
    ) async throws -> URL {
        let resolvedData = try await resolvePreviewData(
            source: source,
            fileName: fileName,
            mimeType: mimeType
        )
        let destinationURL = makeDestinationURL(
            baseDirectoryURL: baseDirectoryURL,
            cacheKey: cacheKey,
            fileName: resolvedData.fileName ?? fileName,
            mimeType: resolvedData.mimeType ?? mimeType
        )

        try FileManager.default.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true
        )
        try resolvedData.data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func resolvePreviewData(
        source: String,
        fileName: String?,
        mimeType: String?
    ) async throws -> ResolvedPreviewData {
        if source.hasPrefix("data:") {
            let (data, inferredMimeType) = try decodeDataURL(source)
            return ResolvedPreviewData(
                data: data,
                fileName: fileName,
                mimeType: mimeType ?? inferredMimeType
            )
        }

        if source.hasPrefix("/") || source.hasPrefix("~") {
            let localPath = (source as NSString).expandingTildeInPath
            let localURL = URL(fileURLWithPath: localPath)
            let data = try Data(contentsOf: localURL)
            return ResolvedPreviewData(
                data: data,
                fileName: fileName ?? localURL.lastPathComponent,
                mimeType: detectedMimeType(for: localURL) ?? mimeType
            )
        }

        guard let url = URL(string: source) else {
            throw RuntimeError(localized: "Invalid preview source URL")
        }

        if url.isFileURL {
            let data = try Data(contentsOf: url)
            return ResolvedPreviewData(
                data: data,
                fileName: fileName ?? url.lastPathComponent,
                mimeType: detectedMimeType(for: url) ?? mimeType
            )
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            throw RuntimeError(localized: "Failed to download preview: HTTP \(httpResponse.statusCode)")
        }

        return ResolvedPreviewData(
            data: data,
            fileName: fileName ?? response.suggestedFilename ?? inferredFilename(from: url),
            mimeType: mimeType ?? response.mimeType
        )
    }

    static func decodeDataURL(_ source: String) throws -> (Data, String?) {
        guard let separatorIndex = source.firstIndex(of: ",") else {
            throw RuntimeError(localized: "Invalid preview data URL")
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
            throw RuntimeError(localized: "Invalid preview data URL payload")
        }

        return (data, mimeType)
    }

    static func makeDestinationURL(
        baseDirectoryURL: URL,
        cacheKey: String,
        fileName: String?,
        mimeType: String?
    ) -> URL {
        let baseName = sanitizedBaseName(fileName)
        let fileExtension = filenameExtension(from: fileName)
            ?? extensionForMimeType(mimeType)
            ?? "bin"
        let suffix = String(cacheKey.prefix(12))
        let finalName = "\(baseName)_\(suffix).\(fileExtension)"
        return baseDirectoryURL.appendingPathComponent(finalName, isDirectory: false)
    }

    static func inferredFilename(from url: URL) -> String? {
        let candidate = url.lastPathComponent
        return candidate.isEmpty ? nil : candidate
    }

    static func detectedMimeType(for fileURL: URL) -> String? {
        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let mimeType = contentType.preferredMIMEType
        {
            return mimeType
        }
        return UTType(filenameExtension: fileURL.pathExtension.lowercased())?.preferredMIMEType
    }

    static func cacheKey(source: String, fileName: String?, mimeType: String?) -> String {
        let payload = "\(source)\n\(fileName ?? "")\n\(mimeType ?? "")"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sanitizedBaseName(_ fileName: String?) -> String {
        let baseName = ((fileName ?? "preview") as NSString).deletingPathExtension
        let sanitized = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return sanitized.isEmpty ? "preview" : sanitized
    }

    static func filenameExtension(from fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let ext = URL(fileURLWithPath: fileName).pathExtension
        return ext.isEmpty ? nil : ext.lowercased()
    }

    static func extensionForMimeType(_ mimeType: String?) -> String? {
        guard let normalizedMimeType = mimeType?.lowercased(),
              let type = UTType(mimeType: normalizedMimeType)
        else {
            return nil
        }
        return type.preferredFilenameExtension
    }
}
