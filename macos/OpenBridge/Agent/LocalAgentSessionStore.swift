import Foundation
import OSLog

private let localAgentStoreLogger = Logger(subsystem: Logger.loggingSubsystem, category: "LocalAgentSessionStore")

struct LocalAgentSessionRecord: Codable, Sendable {
    var id: String
    var title: String
    var createdAt: Int64
    var updatedAt: Int64
    var messages: [SessionHistoryMessage]
}

enum LocalAgentSessionStore {
    private static var sessionsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("OpenBridge", isDirectory: true)
            .appendingPathComponent("LocalAgentSessions", isDirectory: true)
    }

    static func load(sessionID: String) -> LocalAgentSessionRecord? {
        let fileURL = recordURL(sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(LocalAgentSessionRecord.self, from: data)
        } catch {
            localAgentStoreLogger.warning("Failed to load local session \(sessionID): \(error.localizedDescription)")
            return nil
        }
    }

    static func list() -> [LocalAgentSessionRecord] {
        do {
            let directory = sessionsDirectory
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            return files
                .filter { $0.pathExtension == "json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(LocalAgentSessionRecord.self, from: data)
                }
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.createdAt > rhs.createdAt
                }
        } catch {
            localAgentStoreLogger.warning("Failed to list local sessions: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ record: LocalAgentSessionRecord) {
        do {
            let directory = sessionsDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: recordURL(sessionID: record.id), options: [.atomic])
        } catch {
            localAgentStoreLogger.warning("Failed to save local session \(record.id): \(error.localizedDescription)")
        }
    }

    static func delete(sessionID: String) {
        let fileURL = recordURL(sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            localAgentStoreLogger.warning("Failed to delete local session \(sessionID): \(error.localizedDescription)")
        }
    }

    private static func recordURL(sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(safeFileName(sessionID), isDirectory: false)
    }

    private static func safeFileName(_ sessionID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = sessionID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }.joined()
        return "\(sanitized).json"
    }
}
