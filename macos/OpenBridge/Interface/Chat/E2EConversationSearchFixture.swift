import Foundation

#if DEBUG
    struct E2EConversationSearchFixture {
        static let sessionIDEnvKey = "E2E_SEARCH_SESSION_ID"
        static let sessionTitleEnvKey = "E2E_SEARCH_SESSION_TITLE"
        static let messageIDEnvKey = "E2E_SEARCH_MESSAGE_ID"
        static let queryEnvKey = "E2E_SEARCH_QUERY"
        static let snippetEnvKey = "E2E_SEARCH_SNIPPET"

        let sessionID: String
        let sessionTitle: String
        let messageID: String
        let query: String
        let snippet: String

        static var current: E2EConversationSearchFixture? {
            guard ProcessInfo.processInfo.arguments.contains("-e2eMode") else {
                return nil
            }

            let env = ProcessInfo.processInfo.environment
            guard let sessionID = normalized(env[sessionIDEnvKey]),
                  let sessionTitle = normalized(env[sessionTitleEnvKey]),
                  let messageID = normalized(env[messageIDEnvKey]),
                  let query = normalized(env[queryEnvKey]),
                  let snippet = normalized(env[snippetEnvKey])
            else {
                return nil
            }

            return E2EConversationSearchFixture(
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                messageID: messageID,
                query: query,
                snippet: snippet
            )
        }

        private static func normalized(_ raw: String?) -> String? {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else {
                return nil
            }
            return trimmed
        }

        func matches(query searchQuery: String) -> Bool {
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }

            return [query, sessionTitle, snippet].contains {
                $0.localizedCaseInsensitiveContains(trimmed)
            }
        }

        var searchResult: ConversationSearchResult {
            ConversationSearchResult(
                id: "\(sessionID):\(messageID)",
                conversationId: sessionID,
                conversationTitle: sessionTitle,
                messageId: messageID,
                role: "user",
                createdAt: Date().timeIntervalSince1970,
                snippet: snippet,
                score: 1
            )
        }

        var historyMessage: SessionHistoryMessage {
            SessionHistoryMessage(
                id: "e2e-search-\(messageID)",
                type: "message",
                role: "user",
                timestamp: Date().timeIntervalSince1970,
                content: [
                    .init(
                        type: "text",
                        text: snippet,
                        url: nil,
                        fileRef: nil,
                        fileName: nil,
                        mimeType: nil
                    ),
                ],
                messageId: messageID,
                taskId: nil,
                action: nil,
                taskTitle: nil,
                todos: nil,
                sandboxId: nil,
                acceptedSummary: nil,
                reviewDiff: nil,
                reviewDiffTotal: nil,
                confirmationId: nil,
                traceparent: nil,
                tracestate: nil,
                question: nil,
                questionReply: nil,
                saveFileRequest: nil,
                saveFileReply: nil,
                permissionRequest: nil,
                permissionReply: nil,
                secretInput: nil,
                secretInputReply: nil,
                schedule: nil,
                toolUseId: nil,
                errorType: nil,
                error: nil
            )
        }
    }
#endif
