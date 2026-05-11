import AppKit
import Foundation
import UniformTypeIdentifiers

/// Represents a file attachment in the chat composer.
public nonisolated struct ChatAttachment: Identifiable, Sendable {
    public let id: UUID
    public let localURL: URL
    public let isDirectory: Bool
    public private(set) var filename: String
    public private(set) var contentType: String?
    public private(set) var data: Data
    public var uploadState: UploadState

    public enum UploadState: Sendable, Equatable, CustomStringConvertible {
        case pending
        case uploading(progress: Double)
        /// localPath: where the file is saved locally (required)
        /// publicURL: remote URL for LLM access (optional, only for images in production)
        case uploaded(localPath: String, publicURL: String? = nil)
        case failed(error: String)

        public var description: String {
            switch self {
            case .pending:
                "Pending"
            case let .uploading(progress):
                "Uploading: \(progress)"
            case let .uploaded(localPath, publicURL):
                "Uploaded: \(localPath) \(publicURL ?? "")"
            case let .failed(error):
                "Failed: \(error)"
            }
        }
    }

    /// Initialize from a URL with pending state (for async data loading like iCloud files).
    public init(localURL: URL) {
        id = UUID()
        self.localURL = localURL
        isDirectory = (try? localURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        filename = localURL.lastPathComponent
        contentType = if isDirectory {
            "directory"
        } else if let utType = UTType(filenameExtension: localURL.pathExtension) {
            utType.preferredMIMEType ?? "application/octet-stream"
        } else {
            nil
        }
        data = Data()
        uploadState = .pending
    }

    /// Initialize with data (for paste/drop where data is immediately available).
    public init(filename: String, contentType: String, data: Data) {
        id = UUID()
        localURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        uploadState = .pending
        self.data = data
        self.contentType = contentType
        self.filename = filename
        isDirectory = false
    }

    /// Set attachment data (for async loaded files).
    public mutating func setData(_ newData: Data) {
        data = newData
    }

    /// Whether this attachment is an image that can be sent to the LLM vision API.
    public var isImage: Bool {
        contentType?.hasPrefix("image/") ?? false
    }

    /// Whether this attachment has been successfully uploaded.
    public var isUploaded: Bool {
        if case .uploaded = uploadState {
            return true
        }
        return false
    }

    /// Whether this attachment is currently uploading.
    public var isUploading: Bool {
        if case .uploading = uploadState {
            return true
        }
        return false
    }

    /// The upload progress (0.0 to 1.0) if uploading, nil otherwise.
    public var uploadProgress: Double? {
        if case let .uploading(progress) = uploadState {
            return progress
        }
        return nil
    }

    /// The error message if upload failed, nil otherwise.
    public var errorMessage: String? {
        if case let .failed(error) = uploadState {
            return error
        }
        return nil
    }

    /// The local path where the file is saved.
    public var savedLocalPath: String? {
        if case let .uploaded(localPath, _) = uploadState {
            return localPath
        }
        return nil
    }

    /// The public URL for remote access (only available for images in production).
    public var publicURL: String? {
        if case let .uploaded(_, publicURL) = uploadState {
            return publicURL
        }
        return nil
    }

    /// Generate a thumbnail image for preview.
    /// This method is nonisolated and uses the stored data instead of reading from disk.
    public nonisolated func thumbnail(size: CGSize = CGSize(width: 80, height: 80)) -> NSImage? {
        // Check if image using contentType directly (isImage is not accessible in nonisolated context)
        guard let contentType, contentType.hasPrefix("image/") else {
            // For non-image files, return nil (icon will be generated on MainActor)
            return nil
        }

        guard let image = NSImage(data: data) else { return nil }
        let aspectRatio = image.size.width / image.size.height
        let targetSize = if aspectRatio > 1 {
            NSSize(width: size.width, height: size.width / aspectRatio)
        } else {
            NSSize(width: size.height * aspectRatio, height: size.height)
        }
        return NSImage(size: targetSize, flipped: false) { rect in
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            return true
        }
    }

    /// Generate a file icon for non-image files. Must be called on MainActor.
    @MainActor
    public func fileIcon() -> NSImage {
        NSWorkspace.shared.icon(forFile: localURL.path)
    }
}

// MARK: - File Picker Helper

@MainActor
public enum FilePicker {
    public struct AutomationResult: Sendable {
        public let route: String
        public let selectedCount: Int
        public let requestMessage: String?
    }

    public enum AutomationError: LocalizedError {
        case emptySelection
        case fileNotFound(String)
        case filesNotAllowed(String)
        case directoriesNotAllowed(String)
        case multipleSelectionNotAllowed
        case contentTypeNotAllowed(String)

        public var errorDescription: String? {
            switch self {
            case .emptySelection:
                "File picker selection cannot be empty."
            case let .fileNotFound(path):
                "Selected path does not exist: \(path)"
            case let .filesNotAllowed(path):
                "Files are not allowed for the active picker: \(path)"
            case let .directoriesNotAllowed(path):
                "Directories are not allowed for the active picker: \(path)"
            case .multipleSelectionNotAllowed:
                "The active picker only allows a single selection."
            case let .contentTypeNotAllowed(path):
                "Selected path does not match the active picker file type restrictions: \(path)"
            }
        }
    }

    public static func pickURLs(
        allowedTypes: [UTType]? = nil,
        canChooseFiles: Bool = true,
        canChooseDirectories: Bool = true,
        allowsMultipleSelection: Bool = true,
        showsHiddenFiles: Bool = false,
        directoryURL: URL? = nil,
        message: String? = nil
    ) async -> [URL] {
        await FilePickerCoordinator.shared.pickURLs(
            allowedTypes: allowedTypes,
            canChooseFiles: canChooseFiles,
            canChooseDirectories: canChooseDirectories,
            allowsMultipleSelection: allowsMultipleSelection,
            showsHiddenFiles: showsHiddenFiles,
            directoryURL: directoryURL,
            message: message
        )
    }

    /// Show a file picker dialog and return the selected file URLs.
    public static func pickFileURLs(allowedTypes: [UTType]? = nil) async -> [URL] {
        await pickURLs(
            allowedTypes: allowedTypes,
            canChooseFiles: true,
            canChooseDirectories: true,
            allowsMultipleSelection: true,
            message: String(localized: "Select files to upload")
        )
    }

    /// Show a file picker for images only.
    public static func pickImageURLs() async -> [URL] {
        await pickFileURLs(allowedTypes: [.image])
    }

    public static func fulfillAutomationSelection(with urls: [URL]) throws -> AutomationResult {
        try FilePickerCoordinator.shared.fulfillSelection(with: urls)
    }

    public static func cancelAutomationSelection() -> AutomationResult {
        FilePickerCoordinator.shared.cancelSelection()
    }
}

@MainActor
private final class FilePickerCoordinator {
    static let shared = FilePickerCoordinator()

    private struct RequestDescriptor {
        let allowedTypes: [UTType]?
        let canChooseFiles: Bool
        let canChooseDirectories: Bool
        let allowsMultipleSelection: Bool
        let requestMessage: String?
    }

    private struct ActiveRequest {
        let id: UUID
        let panel: NSOpenPanel
        let descriptor: RequestDescriptor
        let continuation: CheckedContinuation<[URL], Never>
    }

    private var pendingSelection: [URL]?
    private var activeRequest: ActiveRequest?

    func pickURLs(
        allowedTypes: [UTType]?,
        canChooseFiles: Bool,
        canChooseDirectories: Bool,
        allowsMultipleSelection: Bool,
        showsHiddenFiles: Bool,
        directoryURL: URL?,
        message: String?
    ) async -> [URL] {
        if let pendingSelection {
            self.pendingSelection = nil
            return pendingSelection
        }

        let descriptor = RequestDescriptor(
            allowedTypes: allowedTypes,
            canChooseFiles: canChooseFiles,
            canChooseDirectories: canChooseDirectories,
            allowsMultipleSelection: allowsMultipleSelection,
            requestMessage: message
        )

        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.showsHiddenFiles = showsHiddenFiles
        panel.directoryURL = directoryURL
        panel.message = message ?? ""
        panel.level = .modalPanel

        if let allowedTypes {
            panel.allowedContentTypes = allowedTypes
        }

        return await withCheckedContinuation { continuation in
            let requestID = UUID()
            activeRequest = ActiveRequest(
                id: requestID,
                panel: panel,
                descriptor: descriptor,
                continuation: continuation
            )

            panel.begin { [weak self] response in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(returning: [])
                        return
                    }

                    guard let activeRequest = self.activeRequest, activeRequest.id == requestID else {
                        return
                    }

                    self.activeRequest = nil
                    if response == .OK {
                        continuation.resume(returning: panel.urls)
                    } else {
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    func fulfillSelection(with urls: [URL]) throws -> FilePicker.AutomationResult {
        guard !urls.isEmpty else {
            throw FilePicker.AutomationError.emptySelection
        }

        if let activeRequest {
            try validate(urls: urls, for: activeRequest.descriptor)
            self.activeRequest = nil
            activeRequest.panel.orderOut(nil)
            activeRequest.panel.close()
            activeRequest.continuation.resume(returning: urls)
            return .init(
                route: "file_picker_active_request",
                selectedCount: urls.count,
                requestMessage: activeRequest.descriptor.requestMessage
            )
        }

        pendingSelection = urls
        return .init(
            route: "file_picker_pending_selection",
            selectedCount: urls.count,
            requestMessage: nil
        )
    }

    func cancelSelection() -> FilePicker.AutomationResult {
        if let activeRequest {
            self.activeRequest = nil
            activeRequest.panel.orderOut(nil)
            activeRequest.panel.close()
            activeRequest.continuation.resume(returning: [])
            return .init(
                route: "file_picker_active_cancel",
                selectedCount: 0,
                requestMessage: activeRequest.descriptor.requestMessage
            )
        }

        pendingSelection = nil
        return .init(
            route: "file_picker_pending_cancel",
            selectedCount: 0,
            requestMessage: nil
        )
    }

    private func validate(urls: [URL], for descriptor: RequestDescriptor) throws {
        if !descriptor.allowsMultipleSelection, urls.count > 1 {
            throw FilePicker.AutomationError.multipleSelectionNotAllowed
        }

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw FilePicker.AutomationError.fileNotFound(url.path)
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            let isDirectory = values?.isDirectory == true

            if isDirectory, !descriptor.canChooseDirectories {
                throw FilePicker.AutomationError.directoriesNotAllowed(url.path)
            }

            if !isDirectory, !descriptor.canChooseFiles {
                throw FilePicker.AutomationError.filesNotAllowed(url.path)
            }

            guard !isDirectory, let allowedTypes = descriptor.allowedTypes, !allowedTypes.isEmpty else {
                continue
            }

            let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
            guard let contentType,
                  allowedTypes.contains(where: { contentType.conforms(to: $0) })
            else {
                throw FilePicker.AutomationError.contentTypeNotAllowed(url.path)
            }
        }
    }
}
