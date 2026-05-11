import Foundation
import Observation
import SwiftUI

/// A minimal interface required by `ComposerView`.
///
/// This lets the framework stay UI-focused while allowing host apps to keep their
/// existing business logic / view models.
@MainActor
public protocol ComposerEditing: AnyObject, Observable {
    // MARK: - Core editor state

    var text: String { get set }
    var isFocused: Bool { get set }
    var isDraggingFile: Bool { get set }

    // MARK: - Attachment state

    var attachments: [ChatAttachment] { get }

    // MARK: - Chat state

    var isStreaming: Bool { get }
    var canStop: Bool { get }
    var canSend: Bool { get }

    // MARK: - Actions

    func requestSend()
    func requestStop()
    func requestEscape()

    func addAttachment(_ attachment: ChatAttachment, source: AttachmentSource)
    func addFileURLs(_ urls: [URL], source: AttachmentSource)
    func removeAttachment(id: UUID)
    func retryAttachment(_ attachment: ChatAttachment)
}
