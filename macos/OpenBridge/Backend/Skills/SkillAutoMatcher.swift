import Foundation
import OSLog

@MainActor
@Observable
final class SkillAutoMatcher {
    private struct MatchResponse: Decodable {
        let skill: String?
        let confidence: Double?
    }

    private struct SkillDescriptor {
        let name: String
        let displayName: String
        let description: String
    }

    private static let minimumConfidence = 0.8
    private static let minimumInputLength = 5
    private static let debounceDelayNanoseconds: UInt64 = 600_000_000

    private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "SkillAutoMatcher")

    private(set) var suggestedSkill: Skill?
    private(set) var isMatching = false

    private var debounceTask: Task<Void, Never>?
    private var matchTask: Task<Void, Never>?
    private var dismissedSkillName: String?
    private var dismissedMatchKey: String?
    private var lastMatchedKey: String?
    private var activeMatchToken: UUID?

    func updateInput(_ text: String, hasManualSkill: Bool) {
        let matchKey = Self.makeMatchKey(from: text)

        debounceTask?.cancel()
        debounceTask = nil
        matchTask?.cancel()
        matchTask = nil
        activeMatchToken = nil
        isMatching = false

        if let dismissedMatchKey, dismissedMatchKey != matchKey {
            self.dismissedMatchKey = nil
            dismissedSkillName = nil
        }

        guard hasManualSkill == false, shouldMatch(matchKey: matchKey) else {
            suggestedSkill = nil
            return
        }

        guard lastMatchedKey != matchKey else { return }

        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.debounceDelayNanoseconds)
            } catch {
                return
            }

            guard let self else { return }
            await beginMatch(for: text, matchKey: matchKey)
        }
    }

    func dismiss() {
        dismissedSkillName = suggestedSkill?.name
        dismissedMatchKey = lastMatchedKey
        suggestedSkill = nil
    }

    func reset() {
        debounceTask?.cancel()
        debounceTask = nil
        matchTask?.cancel()
        matchTask = nil
        activeMatchToken = nil
        suggestedSkill = nil
        isMatching = false
        dismissedSkillName = nil
        dismissedMatchKey = nil
        lastMatchedKey = nil
    }

    private func shouldMatch(matchKey: String) -> Bool {
        guard matchKey.isEmpty == false else { return false }
        guard matchKey.count >= Self.minimumInputLength else { return false }
        return matchKey.hasPrefix("/") == false
    }

    private func beginMatch(for text: String, matchKey: String) async {
        matchTask?.cancel()
        let token = UUID()
        matchTask = Task { [weak self] in
            await self?.performMatch(for: text, matchKey: matchKey, token: token)
        }
    }

    private func performMatch(for _: String, matchKey: String, token: UUID) async {
        activeMatchToken = token
        isMatching = true
        defer {
            if activeMatchToken == token {
                activeMatchToken = nil
                isMatching = false
            }
        }
        suggestedSkill = nil
        lastMatchedKey = matchKey
    }

    private static func makeMatchKey(from text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
