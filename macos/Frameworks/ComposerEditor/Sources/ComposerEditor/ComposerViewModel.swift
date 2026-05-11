import Combine
import Foundation
import Observation

@MainActor
@Observable
public final class ComposerViewModel: ComposerEventPublisher, ComposerEditing {
    public var text: String {
        didSet {
            if text != oldValue {
                eventSubject.send(.textChanged(text))
            }
        }
    }

    public var isFocused: Bool = false {
        didSet {
            if isFocused != oldValue {
                eventSubject.send(.focusChanged(isFocused))
            }
        }
    }

    public var isDraggingFile: Bool = false
    public var attachments: [ChatAttachment] = []
    public var isStreaming: Bool = false
    public var canStop: Bool {
        isStreaming
    }

    public var compactMode: Bool = false // Set by parent to control behavior

    let eventSubject = PassthroughSubject<ComposerEvent, Never>()
    public var eventPublisher: AnyPublisher<ComposerEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    public init(text: String = "", compactMode: Bool = false) {
        self.text = text
        self.compactMode = compactMode
    }

    // MARK: - External Data Injection

    /// Set text from external source (e.g., another window)
    public func setText(_ newText: String) {
        text = newText
    }

    /// Set attachments from external source (e.g., file picker window)
    public func setAttachments(_ newAttachments: [ChatAttachment]) {
        attachments = newAttachments
    }

    /// Append an attachment from external source
    public func appendAttachment(_ attachment: ChatAttachment) {
        attachments.append(attachment)
    }

    public var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasUploadedAttachments = attachments.contains { $0.isUploaded }
        let hasPendingOrUploading = attachments.contains { $0.uploadState == .pending || $0.isUploading }
        return !isStreaming && (hasText || hasUploadedAttachments) && !hasPendingOrUploading
    }

    public func requestSend() {
        guard canSend else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let submission = ComposerEvent.Submission(
            text: trimmed.isEmpty ? nil : trimmed,
            attachments: attachments
        )
        eventSubject.send(.submitted(submission))
    }

    public func requestStop() {
        eventSubject.send(.stopRequested)
    }

    public func requestEscape() {
        eventSubject.send(.escaped)
    }

    public func addAttachment(_ attachment: ChatAttachment, source: AttachmentSource) {
        // In compact mode, emit event instead of adding directly
        if compactMode {
            // Don't add attachment, let external handler decide
            return
        }

        attachments.append(attachment)
        eventSubject.send(.attachmentAdded(attachment, source))

        // For images with data, simulate upload
        if attachment.isImage, !attachment.data.isEmpty {
            eventSubject.send(.attachmentUploadStarted(attachment.id))
        }

        // For file URLs, load data asynchronously
        if attachment.data.isEmpty {
            loadAttachmentData(attachment)
        }
    }

    public func addFileURLs(_ urls: [URL], source: AttachmentSource) {
        // In compact mode, emit event for external handling
        if compactMode {
            switch source {
            case .drop:
                eventSubject.send(.fileDropRequested(urls))
            case .menu, .paste:
                eventSubject.send(.fileAttachRequested)
            }
            return
        }

        for url in urls {
            addAttachment(ChatAttachment(localURL: url), source: source)
        }
    }

    func loadAttachmentData(_ attachment: ChatAttachment) {
        Task {
            do {
                let data = try Data(contentsOf: attachment.localURL)
                updateAttachmentData(id: attachment.id, data: data)

                if attachment.isImage {
                    eventSubject.send(.attachmentUploadStarted(attachment.id))
                } else {
                    // Non-image files are ready immediately (use local path)
                    updateAttachmentState(id: attachment.id, state: .uploaded(
                        localPath: attachment.localURL.path
                    ))
                }
            } catch {
                updateAttachmentState(id: attachment.id, state: .failed(error: error.localizedDescription))
            }
        }
    }

    func updateAttachmentData(id: UUID, data: Data) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        var updated = attachments[index]
        updated.setData(data)
        attachments[index] = updated
    }

    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        eventSubject.send(.attachmentRemoved(id))
    }

    public func retryAttachment(_ attachment: ChatAttachment) {
        eventSubject.send(.attachmentUploadStarted(attachment.id))
    }

    public func updateAttachmentState(id: UUID, state: ChatAttachment.UploadState) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        var updated = attachments[index]
        updated.uploadState = state
        attachments[index] = updated

        switch state {
        case let .uploading(progress):
            eventSubject.send(.attachmentUploadProgress(id, progress))
        case let .uploaded(localPath, _):
            eventSubject.send(.attachmentUploadCompleted(id, localPath))
        case let .failed(error):
            eventSubject.send(.attachmentUploadFailed(id, error))
        case .pending:
            break
        }
    }

    public func clearAttachments() {
        attachments.removeAll()
    }

    public func reset() {
        text = ""
        attachments.removeAll()
        isStreaming = false
        isDraggingFile = false
        isFocused = false
    }
}
