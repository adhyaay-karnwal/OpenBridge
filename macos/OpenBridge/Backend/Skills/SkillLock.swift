import Foundation

// MARK: - SkillLockEntry

struct SkillLockEntry: Codable {
    let name: String
    let source: SkillSource
    let sourceRepo: String?
    let sourcePath: String?
    let branch: String?
    var version: String
    let installedAt: Date
    var updatedAt: Date

    var lockKey: String {
        if source == .external, let repo = sourceRepo {
            return "\(repo)/\(name)"
        }
        return name
    }
}

// MARK: - SkillLockFile

struct SkillLockFile: Codable {
    var entries: [String: SkillLockEntry]

    init(entries: [String: SkillLockEntry] = [:]) {
        self.entries = entries
    }
}

// MARK: - LegacySkillLockReader

private final class LegacySkillLockReader {
    private let lockFileURL: URL
    private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "LegacySkillLockReader")
    private let decoder: JSONDecoder

    init() {
        let homeDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let skillsDir = homeDir
            .appendingPathComponent(".openbridge", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        lockFileURL = skillsDir.appendingPathComponent(".skill-lock.json")

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    var url: URL {
        lockFileURL
    }

    func load() -> SkillLockFile {
        guard FileManager.default.fileExists(atPath: lockFileURL.path) else {
            return SkillLockFile()
        }

        do {
            let data = try Data(contentsOf: lockFileURL)
            return try decoder.decode(SkillLockFile.self, from: data)
        } catch {
            logger.error("Failed to load legacy skill lock file: \(error)")
            return SkillLockFile()
        }
    }

    func removeIfPresent() {
        guard FileManager.default.fileExists(atPath: lockFileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: lockFileURL)
        } catch {
            logger.error("Failed to remove legacy skill lock file: \(error)")
        }
    }
}

// MARK: - SkillLockManager

final class SkillLockManager {
    static let shared = SkillLockManager()

    private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "SkillLockManager")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let legacyReader = LegacySkillLockReader()
    private let localLockFileURL: URL

    private var cachedFile = SkillLockFile()
    private var hasLoadedLocalLock = false

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let homeDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        localLockFileURL = homeDir
            .appendingPathComponent(".openbridge", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(".skill-lock.json", isDirectory: false)
    }

    func clearCache() {
        cachedFile = SkillLockFile()
        hasLoadedLocalLock = false
    }

    func load() -> SkillLockFile {
        cachedFile
    }

    func refreshFromDisk() async throws {
        guard FileManager.default.fileExists(atPath: localLockFileURL.path) else {
            cachedFile = SkillLockFile()
            hasLoadedLocalLock = true
            return
        }

        do {
            let data = try Data(contentsOf: localLockFileURL)
            cachedFile = try decoder.decode(SkillLockFile.self, from: data)
            hasLoadedLocalLock = true
        } catch {
            cachedFile = SkillLockFile()
            hasLoadedLocalLock = true
            logger.error("Failed to load local skill lock; using an empty lock file: \(error.localizedDescription)")
        }
    }

    func ensureLoaded() async throws {
        guard hasLoadedLocalLock == false else {
            return
        }
        try await refreshFromDisk()
    }

    func addEntry(_ entry: SkillLockEntry) async throws {
        var file = try await loadedCloudFile()
        if let existingEntry = file.entries[entry.lockKey] {
            file.entries[entry.lockKey] = SkillLockEntry(
                name: entry.name,
                source: entry.source,
                sourceRepo: entry.sourceRepo,
                sourcePath: entry.sourcePath,
                branch: entry.branch,
                version: entry.version,
                installedAt: existingEntry.installedAt,
                updatedAt: entry.updatedAt
            )
        } else {
            file.entries[entry.lockKey] = entry
        }
        try await save(file)
        logger.info("Added local lock entry for skill: \(entry.lockKey)")
    }

    func getEntry(lockKey: String) -> SkillLockEntry? {
        cachedFile.entries[lockKey]
    }

    func getEntry(name: String) -> SkillLockEntry? {
        if let entry = cachedFile.entries[name] {
            return entry
        }
        return cachedFile.entries.values.first { $0.name == name }
    }

    func updateVersion(lockKey: String, newVersion: String) async throws {
        var file = try await loadedCloudFile()
        guard var entry = file.entries[lockKey] else {
            logger.warning("Cannot update local lock version: no lock entry for skill \(lockKey)")
            return
        }
        entry.version = newVersion
        entry.updatedAt = Date()
        file.entries[lockKey] = entry
        try await save(file)
        logger.info("Updated local lock version for skill \(lockKey) to \(newVersion)")
    }

    func removeEntry(lockKey: String) async throws {
        var file = try await loadedCloudFile()
        guard file.entries.removeValue(forKey: lockKey) != nil else {
            return
        }
        try await save(file)
        logger.info("Removed local lock entry for skill: \(lockKey)")
    }

    func migrateLegacyEntries(forRemoteSkills remoteSkills: [Skill]) async throws -> Bool {
        let legacyFile = legacyReader.load()
        guard legacyFile.entries.isEmpty == false else {
            return false
        }

        var localFile = try await loadedCloudFile()
        let remoteImportedKeys = Set(remoteSkills.filter { $0.category == .imported }.map(\.lockKey))
        var didMigrateAnyEntry = false

        for (lockKey, legacyEntry) in legacyFile.entries {
            guard remoteImportedKeys.contains(lockKey) else {
                continue
            }
            guard localFile.entries[lockKey] == nil else {
                continue
            }
            localFile.entries[lockKey] = legacyEntry
            didMigrateAnyEntry = true
        }

        if didMigrateAnyEntry {
            try await save(localFile)
            logger.info("Migrated legacy skill lock entries to local lock file")
        }

        let canRemoveLegacyFile = legacyFile.entries.keys.allSatisfy { localFile.entries[$0] != nil }
        if canRemoveLegacyFile {
            legacyReader.removeIfPresent()
        }

        return didMigrateAnyEntry
    }

    private func loadedCloudFile() async throws -> SkillLockFile {
        try await ensureLoaded()
        return cachedFile
    }

    private func save(_ file: SkillLockFile) async throws {
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(
            at: localLockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: localLockFileURL, options: .atomic)
        cachedFile = file
        hasLoadedLocalLock = true
    }
}
