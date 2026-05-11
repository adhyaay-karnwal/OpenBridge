//
//  Logger.swift
//  OpenBridge
//
//  Created by qaq on 2025/11/2.
//

import Foundation
import OSLog

nonisolated extension Logger {
    static let loggingSubsystem: String = MainActor.assumeIsolated {
        Bundle.main.bundleIdentifier ?? "OpenBridge"
    }

    static var database: Logger {
        LogCategory.database.logger
    }

    static var syncEngine: Logger {
        LogCategory.syncEngine.logger
    }

    static var chatService: Logger {
        LogCategory.chatService.logger
    }

    static var app: Logger {
        LogCategory.app.logger
    }

    static var scrubber: Logger {
        LogCategory.scrubber.logger
    }

    static var bridge: Logger {
        LogCategory.bridge.logger
    }

    static var ui: Logger {
        LogCategory.ui.logger
    }

    static var network: Logger {
        LogCategory.network.logger
    }

    static var model: Logger {
        LogCategory.model.logger
    }

    static var agent: Logger {
        LogCategory.agent.logger
    }

    static var updater: Logger {
        LogCategory.updater.logger
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Sendable {
    let id: Int
    let timestamp: String
    let level: LogLevel
    let category: String
    let message: String
    let rawLine: String
}

extension LogEntry {
    // Format: "2025-11-02T12:34:56.789+00:00 [INFO] [App] message text"
    static func parse(line: String, index: Int) -> LogEntry? {
        guard let firstBracket = line.range(of: " [") else { return nil }
        let timestamp = String(line[line.startIndex ..< firstBracket.lowerBound])

        guard timestamp.count >= 10,
              timestamp[timestamp.startIndex].isNumber
        else { return nil }

        let rest = String(line[firstBracket.upperBound...])

        guard let levelEnd = rest.firstIndex(of: "]") else { return nil }
        let levelStr = String(rest[rest.startIndex ..< levelEnd])

        let level: LogLevel = switch levelStr {
        case "DEBUG": .debug
        case "INFO": .info
        case "ERROR": .error
        default: .debug
        }

        let afterLevel = rest[rest.index(after: levelEnd)...]
        guard let catStart = afterLevel.range(of: "["),
              let catEnd = afterLevel[catStart.upperBound...].firstIndex(of: "]")
        else { return nil }

        let category = String(afterLevel[catStart.upperBound ..< catEnd])

        let afterCat = afterLevel[afterLevel.index(after: catEnd)...]
        let message = String(afterCat.drop(while: { $0 == " " }))

        return LogEntry(
            id: index,
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            rawLine: line
        )
    }

    static func parseAll(from text: String) -> [LogEntry] {
        let lines = text.components(separatedBy: "\n")
        var entries: [LogEntry] = []
        var entryIndex = 0

        for line in lines where !line.isEmpty {
            if let entry = parse(line: line, index: entryIndex) {
                entries.append(entry)
                entryIndex += 1
            } else if !entries.isEmpty {
                let prev = entries[entries.count - 1]
                entries[entries.count - 1] = LogEntry(
                    id: prev.id,
                    timestamp: prev.timestamp,
                    level: prev.level,
                    category: prev.category,
                    message: prev.message + "\n" + line,
                    rawLine: prev.rawLine + "\n" + line
                )
            }
        }

        return entries
    }
}

// MARK: - Log Level

public nonisolated enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"
}

public nonisolated enum LogCategory: String, Sendable, CaseIterable {
    case database = "Database"
    case syncEngine = "SyncEngine"
    case chatService = "ChatService"
    case app = "App"
    case scrubber = "Scrubber"
    case bridge = "OpenBridge"
    case ui = "UI"
    case network = "Network"
    case model = "Model"
    case agent = "Agent"
    case updater = "Updater"

    var logger: Logger {
        Logger(subsystem: Logger.loggingSubsystem, category: rawValue)
    }
}

public actor LogStore {
    public static let shared = LogStore()

    private let maxFileSize: Int = 128 * 1024 * 1024 // 128 MB
    private let maxFiles: Int = 5

    private lazy var logsDir: URL = {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var logFileURL: URL {
        logsDir.appendingPathComponent("OpenBridge.log")
    }

    public func append(level: LogLevel, category: String, message: String) {
        let line = "\(timestamp()) [\(level.rawValue)] [\(category)] \(message)\n"
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {}
        }
        rotateIfNeeded()
    }

    public func readAll(maxBytes: Int = 1_048_576) -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        if data.count <= maxBytes {
            return String(data: data, encoding: .utf8) ?? ""
        }
        let slice = data.suffix(maxBytes)
        return String(data: slice, encoding: .utf8) ?? ""
    }

    public var currentLogFileURL: URL {
        logFileURL
    }

    public func readTail(maxBytes: Int = 128 * 1024) -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        if data.count <= maxBytes { return String(data: data, encoding: .utf8) ?? "" }
        let slice = data.suffix(maxBytes)
        return String(data: slice, encoding: .utf8) ?? ""
    }

    public func clear() {
        try? FileManager.default.removeItem(at: logFileURL)
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? NSNumber else { return }
        if size.intValue < maxFileSize { return }

        // Shift old files
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let src = logsDir.appendingPathComponent("OpenBridge.log.\(i)")
            let dst = logsDir.appendingPathComponent("OpenBridge.log.\(i + 1)")
            if FileManager.default.fileExists(atPath: dst.path) { try? FileManager.default.removeItem(at: dst) }
            if FileManager.default.fileExists(atPath: src.path) { try? FileManager.default.moveItem(at: src, to: dst) }
        }
        let first = logsDir.appendingPathComponent("OpenBridge.log.1")
        if FileManager.default.fileExists(atPath: first.path) { try? FileManager.default.removeItem(at: first) }
        try? FileManager.default.moveItem(at: logFileURL, to: first)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

nonisolated extension Logger {
    private func inferredCategory(from file: String) -> String {
        let lower = file.lowercased()
        if lower.contains("model") { return "Model" }
        if lower.contains("network") { return "Network" }
        if lower.contains("ui") || lower.contains("view") || lower.contains("controller") {
            return "UI"
        }
        if lower.contains("storage") || lower.contains("database") { return "Database" }
        return "App"
    }

    func debug(_ message: String, category: String? = nil, file: String = #file) {
        let cat = category ?? inferredCategory(from: file)
        Task.detached {
            await LogStore.shared.append(level: .debug, category: cat, message: message)
        }
        log(level: .debug, "[\(cat, privacy: .public)] \(message, privacy: .public)")
    }

    func info(_ message: String, category: String? = nil, file: String = #file) {
        let cat = category ?? inferredCategory(from: file)
        Task.detached {
            await LogStore.shared.append(level: .info, category: cat, message: message)
        }
        log(level: .info, "[\(cat, privacy: .public)] \(message, privacy: .public)")
    }

    func error(_ message: String, category: String? = nil, file: String = #file) {
        let cat = category ?? inferredCategory(from: file)
        Task.detached {
            await LogStore.shared.append(level: .error, category: cat, message: message)
        }
        log(level: .error, "[\(cat, privacy: .public)] \(message, privacy: .public)")
    }
}
