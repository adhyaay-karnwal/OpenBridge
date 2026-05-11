import Combine
import Foundation

struct ConversationNavigationRequest: Sendable {
    let conversationId: String
    let messageId: String?
}

final class ContinueInChatManager {
    static let shared = ContinueInChatManager()

    private(set) var submissionPublisher: PassthroughSubject<ChatEditorViewModel.Submission, Never> = .init()
    private(set) var conversationPublisher: PassthroughSubject<ConversationNavigationRequest, Never> = .init()
    private(set) var populatePublisher: PassthroughSubject<ChatEditorViewModel.Submission, Never> = .init()
    private(set) var attachmentURLsPublisher: PassthroughSubject<[URL], Never> = .init()

    func sendSubmission(_ submission: ChatEditorViewModel.Submission) {
        Windows.shared.open(.chat)
        submissionPublisher.send(submission)
    }

    func openConversation(_ conversationId: String, messageId: String? = nil) {
        Windows.shared.open(.chat)
        conversationPublisher.send(
            ConversationNavigationRequest(conversationId: conversationId, messageId: messageId)
        )
    }

    func populateComposer(_ submission: ChatEditorViewModel.Submission) {
        Windows.shared.open(.chat)
        populatePublisher.send(submission)
    }

    func addFileURLsToComposer(_ urls: [URL]) {
        attachmentURLsPublisher.send(urls)
    }
}
