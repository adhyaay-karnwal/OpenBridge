import Foundation
import KWWKAgent
import KWWKAI

extension LocalAgentSession {
    static func localAgentRunError(from messages: [Message], summary: AgentRunSummary) -> Error? {
        guard summary.finalStopReason == .error else { return nil }

        for message in messages.reversed() {
            guard case let .assistant(assistant) = message else { continue }
            if let errorMessage = assistant.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorMessage.isEmpty
            {
                return RuntimeError(errorMessage)
            }

            let text = assistant.content.compactMap { block -> String? in
                if case let .text(content) = block {
                    return content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

            if !text.isEmpty {
                return RuntimeError(text)
            }
        }

        return RuntimeError(localized: "Agent run failed")
    }
}
