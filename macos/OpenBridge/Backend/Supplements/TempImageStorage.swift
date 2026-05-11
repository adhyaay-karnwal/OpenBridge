//
//  TempImageStorage.swift
//  OpenBridge
//
//  Manages temporary storage of chat images.
//

import Foundation
import UniformTypeIdentifiers

/// Manages temporary storage of chat images.
/// Images are persisted to ~/.openbridge/tmp/images/ for stable local paths.
@MainActor
final class TempImageStorage {
    static let shared = TempImageStorage()
    nonisolated static let storageDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openbridge/tmp/images", isDirectory: true)

    let directoryURL: URL
    private let logger = Logger.ui

    private init() {
        directoryURL = Self.storageDirectoryURL

        do {
            try Self.ensureStorageDirectoryExists()
        } catch {
            logger.error("Failed to create image storage directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    /// Save image data to local storage and return the saved path.
    /// - Parameters:
    ///   - data: The image data to save
    ///   - originalFilename: Optional original filename (preferred if available)
    ///   - contentType: MIME type of the image
    /// - Returns: The URL where the image was saved
    func saveImage(data: Data, originalFilename: String?, contentType: String) -> URL {
        do {
            let path = try Self.saveImageOffMain(
                data: data,
                originalFilename: originalFilename,
                contentType: contentType
            )
            logger.info("Saved image to temp storage: \(path.path)")
            return path
        } catch {
            logger.error("Failed to save image: \(error.localizedDescription)")
            return uniquePath(baseName: originalFilename, ext: Self.extensionForMimeType(contentType))
        }
    }

    nonisolated static func saveImageOffMain(
        data: Data,
        originalFilename: String?,
        contentType: String
    ) throws -> URL {
        try ensureStorageDirectoryExists()
        let ext = extensionForMimeType(contentType)
        let path = uniquePath(baseName: originalFilename, ext: ext, addUUIDPrefix: true)
        try data.write(to: path, options: .atomic)
        return path
    }

    // MARK: - Private Helpers

    /// Get file extension for a MIME type.
    private nonisolated static func ensureStorageDirectoryExists() throws {
        try FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
    }

    private nonisolated static func extensionForMimeType(_ mimeType: String) -> String {
        switch mimeType {
        case "image/png":
            return "png"
        case "image/jpeg":
            return "jpg"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        default:
            // Try to get extension from UTType
            if let utType = UTType(mimeType: mimeType),
               let ext = utType.preferredFilenameExtension
            {
                return ext
            }
            return "png"
        }
    }

    /// Generate a unique file path, avoiding collisions with existing files.
    /// Uses original filename if provided, otherwise generates a random name.
    /// Appends a suffix (_1, _2, etc.) if the file already exists.
    private func uniquePath(baseName: String?, ext: String) -> URL {
        Self.uniquePath(baseName: baseName, ext: ext)
    }

    private nonisolated static func uniquePath(
        baseName: String?,
        ext: String,
        addUUIDPrefix: Bool = false
    ) -> URL {
        let sanitizedBase = sanitizeBaseName(baseName)
        let prefix = addUUIDPrefix ? "\(UUID().uuidString)-" : ""
        let filename = "\(prefix)\(sanitizedBase).\(ext)"
        var path = storageDirectoryURL.appendingPathComponent(filename)

        // If file doesn't exist, use as-is
        guard FileManager.default.fileExists(atPath: path.path) else {
            return path
        }

        // File exists, try with numeric suffix
        for i in 1 ... 999 {
            let newFilename = "\(sanitizedBase)_\(i).\(ext)"
            path = storageDirectoryURL.appendingPathComponent("\(prefix)\(newFilename)")
            if !FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }

        // Fallback: use random suffix if somehow all 999 slots are taken
        let randomSuffix = String((0 ..< 6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return storageDirectoryURL.appendingPathComponent("\(prefix)\(sanitizedBase)_\(randomSuffix).\(ext)")
    }

    /// Sanitize the base name from original filename, or generate a random one.
    private nonisolated static func sanitizeBaseName(_ original: String?) -> String {
        if let original, !original.isEmpty {
            let baseName = (original as NSString).deletingPathExtension
            // Sanitize to prevent path traversal
            return baseName
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
        }

        // Generate a short random filename (8 chars)
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0 ..< 8).map { _ in chars.randomElement()! })
        return "img_\(randomPart)"
    }
}
