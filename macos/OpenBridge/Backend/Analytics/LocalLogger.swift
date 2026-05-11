import Foundation
import OSLog

nonisolated enum LocalLogSeverity {
    case debug
    case info
    case warning
    case error
}

nonisolated enum LocalAgentLogger {
    nonisolated static func log(
        _ message: String,
        category: LogCategory = .agent,
        severity: LocalLogSeverity = .info,
        data: [String: Any] = [:]
    ) {
        let attributes = data.isEmpty ? "" : " \(data)"
        let localMessage = "[Local] \(message)\(attributes)"
        let logger = category.logger

        switch severity {
        case .debug:
            logger.debug("\(localMessage)")
        case .info:
            logger.info("\(localMessage)")
        case .warning:
            logger.warning("\(localMessage)")
        case .error:
            logger.error("\(localMessage)")
        }
    }
}
