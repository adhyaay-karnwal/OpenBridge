//
//  ChatFollowUpViewModel.swift
//  OpenBridge
//
//  Created by Cursor on 2025/12/26.
//

import Foundation
import JSBridge

@JSBridgeType
struct FollowUpItem: Identifiable, Equatable, Codable {
    var id: UUID = .init()
    let displayText: String
    let sendText: String
}

private final nonisolated class FollowUpItemsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FollowUpItem] = []

    func replace(with items: [FollowUpItem]) {
        lock.lock()
        self.items = items
        lock.unlock()
    }

    func snapshot() -> [FollowUpItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@MainActor
@Observable
final class ChatFollowUpViewModel {
    var followUpItems: [FollowUpItem] = []
    var isGenerating: Bool = false
    private(set) var generateTask: Task<Void, Never>?

    private weak var session: LocalAgentSession?
    private let logger: Logger = .ui

    init(session: LocalAgentSession) {
        self.session = session
    }

    func generate() {
        generateTask?.cancel()
        generateTask = Task {
            await performGenerate()
        }
    }

    func cancel() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
    }

    func reset() {
        cancel()
        followUpItems = []
    }

    private func performGenerate() async {
        guard let session else { return }

        isGenerating = true
        followUpItems = []

        defer {
            if !Task.isCancelled {
                isGenerating = false
            }
        }

        let historyMessages = extractRecentConversation(from: session.historyMessages, rounds: 3)

        guard !historyMessages.isEmpty else {
            logger.info("No conversation history for follow-up generation")
            return
        }

        do {
            let items = try await generateFollowUps(historyMessages: historyMessages)

            try Task.checkCancellation()

            followUpItems = items
            logger.info("Generated \(items.count) follow-up items")
        } catch is CancellationError {
            return
        } catch {
            logger.warning("Failed to generate follow-ups: \(error.localizedDescription)")
        }
    }

    private func extractRecentConversation(from messages: [SessionHistoryMessage], rounds: Int) -> [AnyCodingValue] {
        var userMessageCount = 0
        var startIndex = messages.count

        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            let msg = messages[i]
            if msg.type == "message", msg.role == "user" {
                userMessageCount += 1
                if userMessageCount >= rounds {
                    startIndex = i
                    break
                }
            }
        }

        if userMessageCount < rounds, startIndex == messages.count {
            startIndex = 0
        }

        // Convert SessionHistoryMessage to AnyCodingValue for the follow-up LLM call
        return messages[startIndex...].compactMap { msg -> AnyCodingValue? in
            guard msg.type == "message" else { return nil }

            var payload: [String: AnyCodingValue] = [
                "type": .string("message"),
                "role": .string(msg.role ?? "user"),
            ]

            if let content = msg.content {
                var contentParts: [AnyCodingValue] = []
                for c in content {
                    if c.type == "text", let text = c.text {
                        contentParts.append(.object([
                            "type": .string("output_text"),
                            "text": .string(text),
                        ]))
                    }
                }
                payload["content"] = .array(contentParts)
            }

            return .object(payload)
        }
    }

    private func generateFollowUps(historyMessages _: [AnyCodingValue]) async throws -> [FollowUpItem] {
        []
    }
}
