import Foundation

@MainActor
@Observable
final class SkillManager {
    static let shared = SkillManager()

    let logger = Logger(subsystem: Logger.loggingSubsystem, category: "SkillManager")
    let skillDirs: SkillDirectories
    let userSkillCacheTTL: TimeInterval = 30

    private(set) var skills: [Skill] = []
    private(set) var isRefreshingUserSkills = false
    private(set) var isRefreshingSystemSkills = false
    private(set) var lastUserSkillsRefreshAt: Date?

    private var syncedSkills: [Skill] = []
    private var remoteUserSkills: [Skill] = []
    private var systemSkills: [Skill] = []

    private init() {
        do {
            skillDirs = try SkillDirectories.create()
            try installSystemSkills()
        } catch {
            fatalError("Failed to create skill directories: \(error)")
        }

        loadSyncedSkills()
        loadLocalUserSkills()
        loadSystemSkills()
        mergeSkills(notify: false)
    }

    // MARK: - Public Inventory

    func scanSkills() {
        loadSyncedSkills()
        loadLocalUserSkills()
        loadSystemSkills()
        mergeSkills(notify: true)
    }

    func makeUniqueSkillName(_ name: String, for excluding: Skill? = nil) throws -> String {
        var uniqueName = name
        let excludingID = excluding?.id
        let existingNames = Set(
            skills
                .filter { $0.id != excludingID }
                .map(\.name)
        )

        var counter = 1
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(name)-\(counter)"
        }

        return uniqueName
    }

    func checkAndUpdateAllSkills() async {
        logger.debug("Online skill auto-update is disabled in the local build.")
    }
}

// MARK: - Local Skill Scan

extension SkillManager {
    func handleSessionStateChange() async {
        loadSyncedSkills()
        loadLocalUserSkills()
        loadSystemSkills()
        mergeSkills(notify: true)
    }

    func loadSyncedSkills() {
        do {
            try validateSymbolicLinks(in: skillDirs.sync)
        } catch {
            logger.error("⚠️ Failed to validate synced skill links: \(error)")
        }

        var skillsByID: [String: Skill] = [:]

        do {
            try scanDirectory(skillDirs.sync, into: &skillsByID)
        } catch {
            logger.error("⚠️ Failed to scan synced skills: \(error)")
        }

        syncedSkills = skillsByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func loadLocalUserSkills() {
        var skillsByID: [String: Skill] = [:]

        do {
            try scanDirectory(skillDirs.custom, into: &skillsByID)
        } catch {
            logger.error("⚠️ Failed to scan custom skills: \(error)")
        }

        do {
            try scanDirectory(skillDirs.imported, into: &skillsByID)
        } catch {
            logger.error("⚠️ Failed to scan imported skills: \(error)")
        }

        remoteUserSkills = skillsByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        lastUserSkillsRefreshAt = Date()
    }

    func loadSystemSkills() {
        var skillsByID: [String: Skill] = [:]

        guard FileManager.default.fileExists(atPath: skillDirs.system.path) else {
            systemSkills = []
            return
        }

        do {
            try scanDirectory(skillDirs.system, into: &skillsByID)
        } catch {
            logger.error("Failed to scan system skills: \(error)")
        }

        systemSkills = skillsByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func installSystemSkills() throws {
        let fm = FileManager.default
        let sourceURL = SkillDirectories.bundledSystemSkillsURL()
        guard fm.fileExists(atPath: sourceURL.path) else {
            logger.warning("Bundled system skills not found at \(sourceURL.path, privacy: .public)")
            return
        }

        if fm.fileExists(atPath: skillDirs.system.path) {
            try fm.removeItem(at: skillDirs.system)
        }
        try fm.createDirectory(at: skillDirs.system, withIntermediateDirectories: true)

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        while let itemURL = enumerator.nextObject() as? URL {
            let relativePath = itemURL.path.replacingOccurrences(of: sourceURL.path + "/", with: "")
            guard !relativePath.isEmpty else { continue }
            let destinationURL = skillDirs.system.appendingPathComponent(relativePath)
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destinationURL.path) {
                    try fm.removeItem(at: destinationURL)
                }
                try fm.copyItem(at: itemURL, to: destinationURL)
            }
        }
    }

    func refreshRemoteSkills(notify: Bool) async {
        loadSyncedSkills()
        loadLocalUserSkills()
        loadSystemSkills()
        mergeSkills(notify: notify)
    }

    func refreshUserSkills(notify: Bool, force: Bool = false) async {
        guard force || shouldRefreshUserSkills() else {
            logger.debug("Skipping user skill refresh because cache is fresh: notify=\(notify), force=\(force)")
            return
        }
        guard !isRefreshingUserSkills else {
            logger.info("Skipping user skill refresh because another refresh is already running: notify=\(notify), force=\(force)")
            return
        }

        isRefreshingUserSkills = true
        defer { isRefreshingUserSkills = false }

        loadLocalUserSkills()
        lastUserSkillsRefreshAt = Self.updatedUserSkillRefreshTimestamp(
            previous: lastUserSkillsRefreshAt,
            didRefreshSucceed: true
        )

        if notify {
            mergeSkills(notify: true)
        }
    }

    func refreshSystemSkills(notify: Bool) async {
        loadSystemSkills()
        if notify {
            mergeSkills(notify: true)
        }
    }

    func shouldRefreshUserSkills(force: Bool = false, now: Date = .now) -> Bool {
        Self.shouldRefreshUserSkills(
            lastRefreshAt: lastUserSkillsRefreshAt,
            ttl: userSkillCacheTTL,
            force: force,
            now: now
        )
    }

    static func shouldRefreshUserSkills(
        lastRefreshAt: Date?,
        ttl: TimeInterval = 30,
        force: Bool = false,
        now: Date = .now
    ) -> Bool {
        if force {
            return true
        }
        guard let lastRefreshAt else {
            return true
        }
        return now.timeIntervalSince(lastRefreshAt) >= ttl
    }

    static func updatedUserSkillRefreshTimestamp(
        previous: Date?,
        didRefreshSucceed: Bool,
        now: Date = .now
    ) -> Date? {
        didRefreshSucceed ? now : previous
    }

    func mergeSkills(notify: Bool) {
        let merged = (remoteUserSkills + systemSkills + syncedSkills).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        skills = merged
        cleanupOrphanedSkillUsage()
        if notify {
            notifyChange()
        }
    }

    func notifyChange() {
        NotificationCenter.default.post(name: .skillInventoryDidChange, object: self)
        BarMenuCoordinator.shared.rebuild()
    }

    func scanDirectory(_ directory: URL, into skillsByID: inout [String: Skill]) throws {
        var visited = Set<URL>()

        struct SymlinkLink {
            let symlinkURL: URL
            let targetURL: URL
        }

        func reconstructPath(through symlinkChain: [SymlinkLink], from fileURL: URL) -> URL {
            symlinkChain.reversed().reduce(fileURL) { currentURL, link in
                let relativePath = currentURL.path.dropFirst(link.targetURL.path.count)
                let cleanRelativePath = relativePath.hasPrefix("/") ? relativePath.dropFirst() : relativePath
                return link.symlinkURL.appendingPathComponent(String(cleanRelativePath))
            }
        }

        func recursive(
            _ url: URL,
            _ visited: inout Set<URL>,
            _ symlinkChain: [SymlinkLink],
            _ skillsByID: inout [String: Skill]
        ) throws {
            guard !visited.contains(url) else { return }
            visited.insert(url)

            let meta = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            ])

            if meta.isRegularFile == true {
                guard url.lastPathComponent.lowercased() == "skill.md" else { return }
                let outputURL = symlinkChain.isEmpty ? url : reconstructPath(through: symlinkChain, from: url)
                if let skill = try? Skill.load(from: outputURL) {
                    skillsByID[skill.id] = skill
                } else {
                    logger.error("⚠️ Failed to load skill from \(outputURL.path)")
                }
                return
            }

            if meta.isDirectory == true {
                let children = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
                )
                try children.forEach { try recursive($0, &visited, symlinkChain, &skillsByID) }
                return
            }

            if meta.isSymbolicLink == true {
                let target = url.resolvingSymlinksInPath().standardizedFileURL
                let newChain = symlinkChain + [SymlinkLink(symlinkURL: url, targetURL: target)]
                try recursive(target, &visited, newChain, &skillsByID)
            }
        }

        try recursive(directory, &visited, [], &skillsByID)
    }

    func loadUserSkills() async throws -> [Skill] {
        loadLocalUserSkills()
        return remoteUserSkills.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func loadUserSkillsPreservingCache(
        failureContext: String,
        fallbackDescription: String
    ) async -> [Skill]? {
        do {
            return try await loadUserSkills()
        } catch {
            logger.error(
                "⚠️ Failed to \(failureContext, privacy: .public); preserving the \(fallbackDescription, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func shouldIncludeRemoteSkill(_ skill: Skill) -> Bool {
        !(skill.disabled && skill.visibility == .hidden)
    }

    private static func skillCategoryLabel(_ category: Skill.Category) -> String {
        switch category {
        case .custom:
            "custom"
        case .imported:
            "imported"
        case .reflected:
            "reflected"
        case .synced:
            "synced"
        case .system:
            "system"
        }
    }
}

// MARK: - Cloud Package Persistence

extension SkillManager {
    struct RemoteSkillUpdate {
        let displayName: String
        let description: String
        let content: String
        let icon: String
        let color: String
        let pinned: Bool
        let disabled: Bool
        let sendDirectly: Bool
        let outputDir: String?
    }

    func createCustomSkill(name: String = "custom-skill", description: String = "New custom skill") async throws -> Skill {
        let skillName = try makeUniqueSkillName(name)
        let skillData = SkillData(
            frontmatter: SkillData.Frontmatter(
                name: skillName,
                description: description
            ),
            content: ""
        )
        let rootURL = skillDirs.custom.appendingPathComponent(skillName, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let encoder = SkillEncoder()
        let content = try encoder.encode(skillData)
        let manifestURL = rootURL.appendingPathComponent("SKILL.md", isDirectory: false)
        try content.write(to: manifestURL, atomically: true, encoding: .utf8)
        let skill = try Skill.load(from: manifestURL)

        remoteUserSkills.append(skill)
        lastUserSkillsRefreshAt = Date()
        mergeSkills(notify: true)

        return skill
    }

    func deleteSkill(skill: Skill) async throws {
        AnalyticsManager.track(.init(do: .skillDeleted(name: skill.name)))

        try FileManager.default.removeItem(at: skill.folderURL)
        try removeLegacySkillIfPresent(for: skill)
        if skill.category == .imported {
            do {
                try await SkillLockManager.shared.removeEntry(lockKey: skill.lockKey)
            } catch {
                logger.error("Failed to remove local lock entry for deleted skill \(skill.lockKey): \(error)")
            }
        }
        switch skill.category {
        case .system:
            systemSkills.removeAll { $0.id == skill.id }
        case .custom, .imported, .reflected:
            remoteUserSkills.removeAll { $0.id == skill.id }
            lastUserSkillsRefreshAt = Date()
        case .synced:
            break
        }
        removeSkillUsage(skillName: skill.name)
        mergeSkills(notify: true)
    }

    func updateRemoteSkill(_ skill: Skill, with update: RemoteSkillUpdate) async throws {
        _ = try await mutateRemoteSkill(skill) { data in
            data.frontmatter.description = update.description
            data.content = update.content
            data.frontmatter.ensureMetadata()
            data.frontmatter.metadata?.displayName = update.displayName
            data.frontmatter.metadata?.icon = update.icon.isEmpty ? nil : update.icon
            data.frontmatter.metadata?.color = update.color.isEmpty ? nil : update.color
            data.frontmatter.metadata?.disabled = update.disabled ? true : nil
            data.frontmatter.disabled = update.disabled ? true : nil
            data.frontmatter.metadata?.pinned = update.pinned ? true : nil
            data.frontmatter.metadata?.sendDirectly = update.sendDirectly ? true : nil
            data.frontmatter.metadata?.outputDir = update.outputDir
            normalizeMetadata(&data)
        }
    }

    func setSkillPresentation(_ skill: Skill, icon: String, color: String?) async throws {
        _ = try await mutateRemoteSkill(skill) { data in
            data.frontmatter.ensureMetadata()
            data.frontmatter.metadata?.icon = icon.isEmpty ? nil : icon
            data.frontmatter.metadata?.color = (color?.isEmpty ?? true) ? nil : color
        }
    }

    @discardableResult
    func setSkillPinned(_ skill: Skill, isPinned: Bool) async throws -> Skill {
        if skill.category == .system {
            return updateLocalSkillState(skill, pinned: isPinned, disabled: isPinned ? false : nil)
        }

        return try await mutateRemoteSkill(skill) { data in
            data.frontmatter.ensureMetadata()
            data.frontmatter.metadata?.pinned = isPinned ? true : nil
            if isPinned {
                data.frontmatter.metadata?.disabled = nil
                data.frontmatter.disabled = nil
            }
            normalizeMetadata(&data)
        }
    }

    @discardableResult
    func setSkillDisabled(_ skill: Skill, isDisabled: Bool) async throws -> Skill {
        if skill.category == .system {
            return updateLocalSkillState(skill, pinned: isDisabled ? false : nil, disabled: isDisabled)
        }

        return try await mutateRemoteSkill(skill) { data in
            data.frontmatter.ensureMetadata()
            data.frontmatter.metadata?.disabled = isDisabled ? true : nil
            data.frontmatter.disabled = isDisabled ? true : nil
            normalizeMetadata(&data)
        }
    }

    func updateSystemSkillState(_ skill: Skill, pinned: Bool, disabled: Bool) async throws {
        guard skill.category == .system else {
            throw SkillError.invalidSkillType
        }
        _ = updateLocalSkillState(skill, pinned: pinned, disabled: disabled)
    }

    private func updateLocalSkillState(_ skill: Skill, pinned: Bool?, disabled: Bool?) -> Skill {
        var updatedData = skill.data
        updatedData.frontmatter.ensureMetadata()
        if let pinned {
            updatedData.frontmatter.metadata?.pinned = pinned ? true : nil
        }
        if let disabled {
            updatedData.frontmatter.metadata?.disabled = disabled ? true : nil
            updatedData.frontmatter.disabled = disabled ? true : nil
        }
        normalizeMetadata(&updatedData)
        skill.apply(updatedData)
        upsertRemoteSkill(skill)
        return skill
    }

    func upsertRemoteSkill(_ skill: Skill) {
        if skill.category == .system {
            upsertRemoteSkill(skill, in: &systemSkills)
        } else {
            upsertRemoteSkill(skill, in: &remoteUserSkills)
        }
        if skill.category != .system {
            lastUserSkillsRefreshAt = Date()
        }
        mergeSkills(notify: true)
    }

    private func upsertRemoteSkill(_ skill: Skill, in storage: inout [Skill]) {
        if let index = storage.firstIndex(where: { $0.id == skill.id }) {
            storage[index].apply(skill.data)
            storage[index].updatePackagedResources(skill.resourceDescriptors)
            return
        }

        storage.append(skill)
    }

    func removeLegacySkillIfPresent(for skill: Skill, excluding excludedURL: URL? = nil) throws {
        guard let legacyFolderURL = legacyFolderURL(for: skill) else {
            return
        }
        if legacyFolderURL == excludedURL {
            return
        }
        guard FileManager.default.fileExists(atPath: legacyFolderURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: legacyFolderURL)
    }

    func legacyFolderURL(for skill: Skill) -> URL? {
        switch skill.category {
        case .custom:
            skillDirs.custom.appendingPathComponent(skill.name, isDirectory: true)
        case .imported:
            skill.lockKey
                .split(separator: "/")
                .reduce(skillDirs.imported) { partialURL, component in
                    partialURL.appendingPathComponent(String(component), isDirectory: true)
                }
        case .reflected:
            nil
        case .synced:
            nil
        case .system:
            nil
        }
    }

    func performUpdate(for skill: Skill) async throws -> String {
        logger.debug("Online skill update requested for \(skill.name), but updates are disabled in the local build.")
        throw SkillError.invalidSkillType
    }

    private func mutateRemoteSkill(_ skill: Skill, mutation: (inout SkillData) -> Void) async throws -> Skill {
        var updatedData = skill.data
        mutation(&updatedData)

        let encodedContent = try SkillEncoder().encode(updatedData)
        try encodedContent.write(to: skill.fileURL, atomically: true, encoding: .utf8)
        skill.apply(updatedData)
        mergeSkills(notify: true)
        return skill
    }

    private func normalizeMetadata(_ data: inout SkillData) {
        data.frontmatter.syncDisabledState()
        let isDisabled = data.frontmatter.metadata?.disabled ?? data.frontmatter.disabled ?? false
        let isPinned = isDisabled ? false : (data.frontmatter.metadata?.pinned ?? false)
        let canSendDirectly = isPinned && !isDisabled && (data.frontmatter.metadata?.sendDirectly ?? false)

        data.frontmatter.ensureMetadata()
        data.frontmatter.metadata?.pinned = isPinned ? true : nil
        data.frontmatter.metadata?.sendDirectly = canSendDirectly ? true : nil
        data.frontmatter.metadata?.disabled = isDisabled ? true : nil
        data.frontmatter.disabled = isDisabled ? true : nil
    }
}

struct SkillPackageIOFile {
    let path: String
    let data: Data
    let contentType: String
}

enum SkillError: Error, LocalizedError {
    case invalidSkillName(String)
    case invalidSkillType
    case failedAddSyncSkillFolder(String)
    case skillNotFound(String)
    case unzipFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSkillName(message):
            message
        case .invalidSkillType:
            String(localized: "Invalid skill type")
        case let .failedAddSyncSkillFolder(message):
            message
        case let .skillNotFound(message):
            String(localized: "Skill not found: \(message)")
        case let .unzipFailed(message):
            String(localized: "Unzip failed: \(message)")
        case let .importFailed(message):
            String(localized: "Import failed: \(message)")
        }
    }
}
