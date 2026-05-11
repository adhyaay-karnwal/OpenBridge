import AppKit
import SwiftUI

enum ChatMainWindowViewHelpers {
    static func detailTitle(from conversationTitle: String) -> String {
        let trimmed = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "New Chat") : trimmed
    }

    static func toolbarTitle(from detailTitle: String) -> String {
        let limit = 24
        guard detailTitle.count > limit else { return detailTitle }
        return String(detailTitle.prefix(limit)) + "…"
    }

    static func currentConversationSession(
        conversationId: String?,
        sessions: [SessionListInfo],
        conversationTitle: String
    ) -> SessionListInfo? {
        guard let conversationId else { return nil }

        if let session = sessions.first(where: { $0.id == conversationId }) {
            return session
        }

        let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionListInfo(
            id: conversationId,
            title: title,
            messageCount: nil,
            lastMessagePreview: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }

    static func backgroundColor(for colorScheme: ColorScheme) -> Color {
        guard colorScheme == .light else {
            return Color(nsColor: .windowBackgroundColor)
        }

        return Color(hex: "FAFAFA", opacity: 1)
    }

    static func sectionDisplayTitle(_ title: String) -> String {
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }

    static func presentErrorAlert(_ error: Error) {
        Task { @MainActor in
            guard let window = NSApp.keyWindow else { return }
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window) { _ in }
        }
    }
}
