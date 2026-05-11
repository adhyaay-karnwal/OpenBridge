import Foundation

enum AnalyticsManager {
    static func initialize() {}

    static func identify(userID _: String, email _: String?, displayName _: String?, createdAt _: String? = nil) {}

    static func reset() {}

    static func alias(_: String) async {}

    static func track(_: Event) {}

    static func trackObservabilityEvent(
        failureClass _: String,
        severity _: String = "error",
        surface _: String,
        operationID _: String? = nil,
        requestID _: String? = nil,
        traceID _: String? = nil,
        spanID _: String? = nil,
        statusCode _: Int? = nil,
        networkErrorKind _: String? = nil,
        runbookID _: String? = nil,
        diagnosisHint _: String? = nil,
        error _: Error? = nil,
        properties _: [String: Any] = [:]
    ) {}

    static func trackStepEvent(
        stepName _: String,
        stepState _: String,
        surface _: String,
        operationID _: String? = nil,
        requestID _: String? = nil,
        properties _: [String: Any] = [:]
    ) {}
}
