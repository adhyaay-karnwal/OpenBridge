import Combine
import Foundation

// MARK: - Composer Events

/// Events emitted by the composer that the app can observe
public enum ComposerEvent: Sendable {
    /// User submitted a message
    case submitted(Submission)

    /// User pressed escape key
    case escaped

    /// Attachment was added
    case attachmentAdded(ChatAttachment, AttachmentSource)

    /// Attachment was removed
    case attachmentRemoved(UUID)

    /// Attachment upload started
    case attachmentUploadStarted(UUID)

    /// Attachment upload progressed
    case attachmentUploadProgress(UUID, Double)

    /// Attachment upload completed
    case attachmentUploadCompleted(UUID, String)

    /// Attachment upload failed
    case attachmentUploadFailed(UUID, String)

    /// Text changed
    case textChanged(String)

    /// Focus changed
    case focusChanged(Bool)

    /// User requested stop (during streaming)
    case stopRequested

    /// File drop requested in compact mode (should open external window)
    case fileDropRequested([URL])

    /// File attach requested from menu in compact mode (should open external window)
    case fileAttachRequested

    public struct Submission: Sendable {
        public let text: String?
        public let attachments: [ChatAttachment]

        public init(text: String?, attachments: [ChatAttachment]) {
            self.text = text
            self.attachments = attachments
        }
    }
}

// MARK: - Event Publisher Protocol

/// Protocol for types that can publish composer events
@MainActor
public protocol ComposerEventPublisher {
    var eventPublisher: AnyPublisher<ComposerEvent, Never> { get }
}
