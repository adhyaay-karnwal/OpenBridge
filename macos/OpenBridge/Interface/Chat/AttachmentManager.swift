import ComposerEditor
import Foundation

/// Manages chat attachments including upload state and lifecycle.
@MainActor
@Observable
final class AttachmentManager {
    private static let localEnvironmentLabel = "Local"

    private(set) var attachments: [ChatAttachment] = []

    private let logger = Logger.ui

    // MARK: - Computed Properties

    var hasUploadedAttachments: Bool {
        attachments.contains { $0.isUploaded }
    }

    var hasPendingOrUploadingAttachments: Bool {
        attachments.contains { $0.uploadState == .pending || $0.isUploading }
    }

    var uploadedAttachments: [ChatAttachment] {
        attachments.filter(\.isUploaded)
    }

    var uploadedAttachmentsCount: Int {
        uploadedAttachments.count
    }

    // MARK: - Public Methods

    /// Add an attachment and start processing immediately.
    func addAttachment(_ attachment: ChatAttachment, source: AttachmentSource) {
        attachments.append(attachment)
        trackAddAttachment(attachment, source: source)

        processAttachment(attachment)
    }

    /// Add an attachment from a URL, loading the file data asynchronously for images.
    /// For non-image files, the local path is used directly without loading data.
    func addAttachmentFromURL(_ url: URL, source: AttachmentSource) {
        let attachment = ChatAttachment(localURL: url)
        attachments.append(attachment)

        // For non-image files, we don't need to load data - just use the local path
        guard attachment.isImage else {
            trackAddAttachment(attachment, source: source, fileSize: AttachmentManager.fileSize(at: url))
            markNonImageAsReady(attachment)
            return
        }

        // Load image data in background for local normalization
        Task { @MainActor in
            let fileData: Data? = try? await Task.detached {
                try Data(contentsOf: url)
            }.value

            guard let fileData else {
                updateAttachmentState(id: attachment.id, state: .failed(error: String(localized: "Failed to load file")))
                return
            }

            updateAttachmentData(id: attachment.id, data: fileData)

            if let updatedAttachment = attachments.first(where: { $0.id == attachment.id }) {
                trackAddAttachment(updatedAttachment, source: source)
                processAttachment(updatedAttachment)
            }
        }
    }

    private func trackAddAttachment(_ attachment: ChatAttachment, source: AttachmentSource, fileSize: Int? = nil) {
        AnalyticsManager.track(.init(
            do: .chatAttachmentAdded(
                source: source.rawValue,
                attachmentType: attachment.isImage ? "image" : "file",
                fileSize: fileSize ?? attachment.data.count,
                contentType: attachment.contentType
            ),
            at: .chat
        ))
    }

    private static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// Remove an attachment by ID.
    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Retry a failed attachment.
    func retryAttachment(_ attachment: ChatAttachment) {
        processAttachment(attachment)
    }

    /// Clear all uploaded attachments (typically after sending a message).
    func clearUploadedAttachments() {
        attachments.removeAll { $0.isUploaded }
    }

    /// Clear all attachments (typically when starting a new conversation).
    func clearAllAttachments() {
        attachments.removeAll()
    }

    /// Build input contents from text and uploaded attachments as SessionHistoryMessage content.
    func buildInputContents(
        text: String?,
        quote: SessionHistoryMessage.Content? = nil
    ) -> [SessionHistoryMessage.Content] {
        Self.buildInputContents(text: text, attachments: uploadedAttachments, quote: quote, logger: logger)
    }

    /// Static version for building input contents from external attachments.
    static func buildInputContents(
        text: String?,
        attachments: [ChatAttachment],
        quote: SessionHistoryMessage.Content? = nil,
        logger: Logger? = nil
    ) -> [SessionHistoryMessage.Content] {
        var content: [SessionHistoryMessage.Content] = []

        let uploadedAttachments = attachments.filter(\.isUploaded)

        for attachment in uploadedAttachments {
            if attachment.isImage {
                guard let localPath = attachment.savedLocalPath else { continue }
                let localURL = URL(fileURLWithPath: localPath)
                let imageURL = makeLocalImageDataURL(for: localURL)
                let mimeType = localURL.detectedMimeType() ?? attachment.contentType ?? "image/jpeg"
                let fileName = localURL.lastPathComponent.isEmpty ? attachment.filename : localURL.lastPathComponent

                if imageURL == nil {
                    logger?.warning("Failed to load normalized image preview data URL: \(fileName)")
                }

                content.append(SessionHistoryMessage.Content(
                    type: "image",
                    text: nil,
                    url: imageURL,
                    fileRef: SessionHistoryMessage.FileRef(
                        environmentId: localEnvironmentLabel,
                        path: localPath
                    ),
                    fileRefs: nil,
                    fileName: fileName,
                    mimeType: mimeType,
                    sizeBytes: Int64(fileSize(at: localURL)),
                    entryKind: "file"
                ))
                logger?.info(imageAttachmentLogMessage(for: attachment, url: imageURL, savedPath: localPath))
            } else {
                content.append(SessionHistoryMessage.Content(
                    type: "file",
                    text: nil,
                    url: nil,
                    fileRef: SessionHistoryMessage.FileRef(
                        environmentId: localEnvironmentLabel,
                        path: attachment.localURL.path
                    ),
                    fileRefs: nil,
                    fileName: attachment.filename,
                    mimeType: attachment.contentType,
                    sizeBytes: Int64(fileSize(at: attachment.localURL)),
                    entryKind: attachment.isDirectory ? "dir" : "file"
                ))
            }
        }

        if let quote,
           quote.type == "quote",
           let quoteText = quote.text,
           !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           quote.quoteRef != nil
        {
            content.append(quote)
        }

        // User text
        content.append(SessionHistoryMessage.Content(
            type: "text",
            text: text ?? "<empty/>",
            url: nil,
            fileRef: nil,
            fileName: nil,
            mimeType: nil,
            quoteRef: nil
        ))

        return content
    }

    // MARK: - Private Methods

    private func updateAttachmentState(id: UUID, state: ChatAttachment.UploadState) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            var updated = attachments[index]
            updated.uploadState = state
            attachments[index] = updated
        }
    }

    private func updateAttachmentData(id: UUID, data: Data) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            var updated = attachments[index]
            updated.setData(data)
            attachments[index] = updated
        }
    }

    private func processAttachment(_ attachment: ChatAttachment) {
        // Skip if already uploaded (e.g., restored from editing)
        if attachment.isUploaded {
            logger.info("Attachment already uploaded, skipping: \(attachment.filename)")
            return
        }

        if attachment.isImage {
            prepareImage(attachment)
        } else {
            markNonImageAsReady(attachment)
        }
    }

    private func markNonImageAsReady(_ attachment: ChatAttachment) {
        let localPath = attachment.localURL.path
        updateAttachmentState(id: attachment.id, state: .uploaded(localPath: localPath))
        logger.info("Non-image file ready (no upload): \(attachment.filename) at \(localPath)")
    }

    private func prepareImage(_ attachment: ChatAttachment) {
        let startTime = Date()

        updateAttachmentState(id: attachment.id, state: .uploading(progress: 0))

        Task {
            do {
                let savedLocalPath = try await Self.prepareImageOffMain(attachment)
                updateAttachmentState(
                    id: attachment.id,
                    state: .uploaded(localPath: savedLocalPath)
                )
                logger.info("Prepared local image attachment: \(attachment.filename) -> \(savedLocalPath)")
                trackUploadResult(attachment, success: true, startTime: startTime)
            } catch {
                let failureMessage = error.localizedDescription.isEmpty
                    ? String(localized: "Failed to process image")
                    : error.localizedDescription
                updateAttachmentState(id: attachment.id, state: .failed(error: failureMessage))
                logger.error("Failed to prepare image attachment: \(attachment.filename), error: \(failureMessage)")
                trackUploadResult(attachment, success: false, startTime: startTime)
            }
        }
    }

    private nonisolated static func prepareImageOffMain(_ attachment: ChatAttachment) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let normalized = normalizeImageForChatInput(
                data: attachment.data,
                filename: attachment.filename
            ) else {
                throw AttachmentPreparationError.failedToNormalize
            }

            let savedPath = try TempImageStorage.saveImageOffMain(
                data: normalized.data,
                originalFilename: normalized.filename,
                contentType: normalized.contentType
            )
            let savedLocalPath = savedPath.path

            guard FileManager.default.fileExists(atPath: savedLocalPath) else {
                throw AttachmentPreparationError.failedToPersist
            }

            return savedLocalPath
        }.value
    }

    private nonisolated enum AttachmentPreparationError: LocalizedError {
        case failedToNormalize
        case failedToPersist

        var errorDescription: String? {
            switch self {
            case .failedToNormalize:
                String(localized: "Failed to process image")
            case .failedToPersist:
                String(localized: "Failed to save normalized image")
            }
        }
    }

    private func trackUploadResult(_ attachment: ChatAttachment, success: Bool, startTime: Date) {
        AnalyticsManager.track(.init(
            do: .chatAttachmentUploaded(
                success: success,
                attachmentType: "image",
                fileSize: attachment.data.count,
                duration: Date().timeIntervalSince(startTime)
            ),
            at: .chat
        ))
    }

    private static func makeLocalImageDataURL(for fileURL: URL) -> String? {
        guard let mimeType = fileURL.detectedMimeType(),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        return data.dataURL(mimeType: mimeType)
    }

    private static func isDataURL(_ url: String) -> Bool {
        url.lowercased().hasPrefix("data:")
    }

    private static func imageAttachmentLogMessage(for attachment: ChatAttachment, url: String, savedPath: String? = nil) -> String {
        let pathInfo = savedPath.map { " (local: \($0))" } ?? ""
        if isDataURL(url) {
            return "Added inline image (base64) to message: \(attachment.filename)\(pathInfo)"
        }
        return "Added image attachment to message: \(url)\(pathInfo)"
    }

    private static func imageAttachmentLogMessage(for attachment: ChatAttachment, url: String?, savedPath: String? = nil) -> String {
        guard let url else {
            let pathInfo = savedPath.map { " (local: \($0))" } ?? ""
            return "Added local image attachment to message: \(attachment.filename)\(pathInfo)"
        }
        return imageAttachmentLogMessage(for: attachment, url: url, savedPath: savedPath)
    }

    /// Format file size as human-readable string.
    /// Returns empty string for directories.
    private static func formatFileSize(_ url: URL) -> String {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            return ""
        }

        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return ""
        }

        let bytes = Int64(fileSize)
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }
}
