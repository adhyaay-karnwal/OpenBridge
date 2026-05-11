import AppKit
import Foundation

@MainActor
final class ConversationListActionController {
    static let shared = ConversationListActionController()

    private init() {}

    func promptForConversationRename(
        initialTitle: String,
        window: NSWindow?,
        onConfirm: @escaping (String, NSWindow) -> Void
    ) {
        let targetWindow = window?.isVisible == true ? window : NSApp.keyWindow
        guard let targetWindow else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Conversation")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = initialTitle.isEmpty ? "" : initialTitle
        alert.accessoryView = textField
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        alert.beginSheetModal(for: targetWindow) { response in
            guard response == .alertFirstButtonReturn else { return }

            let newTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else { return }
            onConfirm(newTitle, targetWindow)
        }
        alert.window.initialFirstResponder = textField
    }

    func renameConversation(
        _ session: SessionListInfo,
        controller: ConversationListViewController = .shared,
        onRenamed: ((String) -> Void)? = nil
    ) {
        promptForConversationRename(
            initialTitle: session.title,
            window: NSApp.keyWindow
        ) { newTitle, window in
            Task { @MainActor in
                do {
                    try await controller.renameConversation(conversationId: session.id, title: newTitle)
                    onRenamed?(newTitle)
                } catch {
                    let errorAlert = NSAlert(error: error)
                    errorAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }

    func deleteConversation(
        _ session: SessionListInfo,
        currentConversationId: String?,
        controller: ConversationListViewController = .shared,
        onDeletedCurrentConversation: @escaping () -> Void
    ) {
        guard let window = NSApp.keyWindow else { return }

        let displayTitle = session.title.isEmpty ? String(localized: "Untitled") : session.title

        let alert = NSAlert()
        alert.messageText = String(localized: "Delete Conversation")
        alert.informativeText = String(
            localized: "Are you sure you want to delete \"\(displayTitle)\"? This action cannot be undone."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }

            Task { @MainActor in
                do {
                    try await controller.deleteConversation(conversationId: session.id)
                    if session.id == currentConversationId {
                        onDeletedCurrentConversation()
                    }
                } catch {
                    let errorAlert = NSAlert(error: error)
                    errorAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }
}
