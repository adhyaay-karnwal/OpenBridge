import Foundation

/// Errors that can surface from the Observer subsystem.
public enum ObserverRuntimeError: Error, CustomStringConvertible {
    case invalidSummaryResponse(String)
    case summaryRequestFailed(String, fatal: Bool)
    case summaryTimedOut(Int)
    case notConfigured

    public var description: String {
        switch self {
        case let .invalidSummaryResponse(m): "Observer received an invalid summary service response: \(m)"
        case let .summaryRequestFailed(m, _): m
        case let .summaryTimedOut(ms): "Observer final summary timed out after \(ms)ms"
        case .notConfigured: "Observer not configured"
        }
    }

    public var isFatal: Bool {
        switch self {
        case let .summaryRequestFailed(_, fatal): fatal
        case .invalidSummaryResponse, .summaryTimedOut, .notConfigured: false
        }
    }
}

public enum ObserverFinalSummaryResult: Sendable {
    case success(String)
    case timeout(Int)
    case failure(String)
    case notConfigured
}

/// Summary provider contract kept close to the legacy observer shape.
public protocol AgentSummarySession: Sendable {
    func summarizeObservation(
        timelineEntries: [ObserverTimelineEntry],
        roundIndex: Int,
        sessionStartedAt: Double
    ) async throws -> String

    func requestFinalSummary(
        timelineEntries: [ObserverTimelineEntry],
        sessionStartedAt: Double
    ) async throws -> String
}

public protocol AgentSummaryService: Sendable {
    func makeSession(logger: @escaping @Sendable (String) -> Void) -> any AgentSummarySession
}

/// Knobs for the observer runtime. Defaults match legacy behavior.
public struct ObservationConfiguration: Sendable {
    public var summaryService: (any AgentSummaryService)?
    public var captureIntervalMs: Int
    public var finalSummaryTimeoutMs: Int

    public init(
        summaryService: (any AgentSummaryService)? = nil,
        captureIntervalMs: Int = 3000,
        finalSummaryTimeoutMs: Int = 10000
    ) {
        self.summaryService = summaryService
        self.captureIntervalMs = max(1500, captureIntervalMs)
        self.finalSummaryTimeoutMs = max(5000, finalSummaryTimeoutMs)
    }
}

/// One entry in the rolling observation timeline the summary service receives.
/// Slim version — legacy also carried cursor trail + input events; we
/// keep just the essentials (summaries + screenshot frames) so the
/// local summary service has enough to produce useful per-round + final reports.
public enum ObserverTimelineEntryType: Sendable {
    case summary
    case capture
}

public struct ObserverTimelineEntry: Sendable {
    public var type: ObserverTimelineEntryType
    public var timestampMs: Double
    public var text: String?
    public var frameBase64: String?
    public var frameMimeType: String?
    public var displayIndex: Int
    public var sequence: Int

    public init(
        type: ObserverTimelineEntryType,
        timestampMs: Double,
        text: String? = nil,
        frameBase64: String? = nil,
        frameMimeType: String? = nil,
        displayIndex: Int = 1,
        sequence: Int
    ) {
        self.type = type
        self.timestampMs = timestampMs
        self.text = text
        self.frameBase64 = frameBase64
        self.frameMimeType = frameMimeType
        self.displayIndex = displayIndex
        self.sequence = sequence
    }
}

public func observerNowMs() -> Double {
    Date().timeIntervalSince1970 * 1000.0
}
