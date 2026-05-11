import AppKit
import Foundation

/// Observer system instruction — kept close to the legacy Node
/// `provider.js` wording so the model continues to return
/// single-sentence round summaries and paragraph-style final recaps.
private let observerSystemInstruction = """
You are Observer, a screen-observation model for a computer-use interruption workflow.

You will receive each round as a timeline since session start.
Each timeline is ordered by time and may contain:
- Prior one-sentence summaries produced by you in earlier rounds ("<elapsed>s <summary>").
- Screenshot markers like "4.5s screen #1:" followed immediately by the screenshot image for that moment.
Each screenshot is local and may not represent the whole screen.

Prefer observable facts over speculation. Mention uncertainty briefly when needed.

For regular per-screen rounds, reply with exactly one concise sentence. If the user did nothing meaningful, reply exactly with "[NO_ACTION]".

For the Final Summary (when the user message includes a Final Summary instruction): reply with a detailed description of the user's behavior across the session — concrete actions (clicks, drags, scrolls, typing, keyboard shortcuts), where attention went (windows, panes, fields, controls), and the resulting visible UI state. Ground this in the timeline and screenshots; briefly note uncertainty where needed. Omit idle / dead-end noise unless task-relevant.
"""

private let observerFinalTailInstruction = """
This is Final Summary. Give a detailed account of what the user actually did (inputs, navigation, focus, and on-screen outcomes), not a generic recap; leave out idle movement / ineffective clicks / dead-end exploration unless task-relevant. Prefer direct observations over guesses.
"""

/// Vision-capable model we route observer calls to. Matches the legacy
/// Gemini-2.5-flash choice: cheap, fast, handles low-res screenshots
/// well.
private let observerModelName = "gemini/gemini-2.5-flash"

@MainActor
enum ObserverBridgeExecutor {
    /// Build a local timeline summary for observer events.
    static func execute(_ request: ObserverRequestWire) async throws -> String {
        let tail: String? = request.kind == .final ? observerFinalTailInstruction : nil
        let text = buildTimelineText(
            timeline: request.timeline,
            sessionStartedAt: request.sessionStartedAt,
            tail: tail
        )
        let normalized: String = switch request.kind {
        case .round: normalizeSingleSentence(text)
        case .final: normalizeFinalSummary(text)
        }
        return normalized.isEmpty ? "[NO_ACTION]" : normalized
    }

    // MARK: - Timeline construction

    private static func buildTimelineText(
        timeline: [ObserverRequestWire.TimelineEntry],
        sessionStartedAt: Double,
        tail: String?
    ) -> String {
        var buffered: [String] = []

        for entry in timeline {
            let elapsed = max(0, (entry.timestampMs - sessionStartedAt) / 1000.0)
            switch entry.type {
            case .summary:
                if let text = entry.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    buffered.append(String(format: "%.1fs %@", elapsed, text))
                }
            case .capture:
                buffered.append(String(format: "%.1fs screen #%d:", elapsed, entry.displayIndex))
            }
        }

        if let tail, !tail.isEmpty {
            buffered.append(tail)
        }
        return buffered.joined(separator: "\n")
    }

    // MARK: - Output normalization (mirror of legacy provider.js)

    private static func normalizeSingleSentence(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "[*_`>#-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let stripped = cleaned.replacingOccurrences(of: "[。！？.!?]+$", with: "", options: .regularExpression)
        let parts = stripped.components(separatedBy: CharacterSet(charactersIn: "。！？.!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: "，").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "" : joined + "。"
    }

    private static func normalizeFinalSummary(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[*_`>#-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
