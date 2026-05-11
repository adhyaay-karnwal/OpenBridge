import Foundation
import SwiftUI

@Observable
class Skill {
    enum Category {
        case synced
        case custom
        case imported
        case reflected
        case system
    }

    enum Source: Hashable {
        case synced(fileURL: URL)
        case remote(rootPath: String)
        case legacy(fileURL: URL)
    }

    struct Resource: Hashable, Identifiable {
        enum Kind: Hashable {
            case file
            case directory
        }

        let relativePath: String
        let localURL: URL?
        let kind: Kind

        var id: String {
            relativePath
        }

        var displayPath: String {
            localURL?.path ?? relativePath
        }
    }

    let id: String
    let category: Category
    let source: Source

    var data: SkillData
    private(set) var packagedResources: [Resource]

    /// Whether this skill is currently being updated
    var isUpdating: Bool = false

    static func load(from fileURL: URL) throws -> Skill {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = SkillDecoder()
        let data = try decoder.decode(content)
        return try Skill(
            id: fileURL.path,
            data: data,
            category: inferCategory(from: fileURL.path),
            source: inferLocalSource(from: fileURL)
        )
    }

    init(
        id: String,
        data: SkillData,
        category: Category,
        source: Source,
        packagedResources: [Resource] = []
    ) {
        self.id = id
        self.data = data
        self.category = category
        self.source = source
        self.packagedResources = packagedResources
    }

    var name: String {
        data.frontmatter.name
    }

    var displayName: String {
        data.frontmatter.metadata?.displayName ?? name
    }

    var description: String {
        data.frontmatter.description
    }

    var content: String {
        data.content
    }

    var icon: String? {
        data.frontmatter.metadata?.icon
    }

    var color: String? {
        data.frontmatter.metadata?.color
    }

    var visibility: SkillData.Visibility {
        data.frontmatter.metadata?.visibility ?? .visible
    }

    var pinned: Bool {
        data.frontmatter.metadata?.pinned ?? false
    }

    var sendDirectly: Bool {
        pinned ? (data.frontmatter.metadata?.sendDirectly ?? false) : false
    }

    var disabled: Bool {
        data.frontmatter.metadata?.disabled ?? data.frontmatter.disabled ?? false
    }

    var outputDir: String? {
        data.frontmatter.metadata?.outputDir
    }

    var placeholder: String? {
        data.frontmatter.metadata?.placeholder
    }

    var fileURL: URL {
        switch source {
        case let .synced(fileURL), let .legacy(fileURL):
            fileURL
        case let .remote(rootPath):
            URL(fileURLWithPath: rootPath, isDirectory: true).appendingPathComponent("SKILL.md")
        }
    }

    var folderURL: URL {
        switch source {
        case let .synced(fileURL), let .legacy(fileURL):
            fileURL.deletingLastPathComponent()
        case let .remote(rootPath):
            URL(fileURLWithPath: rootPath, isDirectory: true)
        }
    }

    var localRootPath: String? {
        switch source {
        case .synced, .legacy:
            nil
        case let .remote(rootPath):
            rootPath
        }
    }

    var isLegacySkill: Bool {
        if case .legacy = source {
            true
        } else {
            false
        }
    }

    var isSyncedSkill: Bool {
        if case .synced = source {
            true
        } else {
            false
        }
    }

    var isRemoteSkill: Bool {
        if case .remote = source {
            true
        } else {
            false
        }
    }

    var canEditInApp: Bool {
        category == .custom || category == .imported || category == .reflected
    }

    var canPinInApp: Bool {
        category != .synced
    }

    var canToggleEnabledInApp: Bool {
        category != .synced
    }

    var canManageLocalResources: Bool {
        false
    }

    var canOpenInFileSystem: Bool {
        isSyncedSkill
    }

    var canDelete: Bool {
        category == .custom || category == .imported || category == .reflected
    }

    var supportsUpdates: Bool {
        false
    }

    /// Unique key for lock file lookups and deduplication.
    /// For imported skills, derived from the relative path under `imported/`.
    /// E.g., official: "formatter", external: "acme/tools/formatter"
    var lockKey: String {
        guard category == .imported else { return name }
        let path = folderURL.path
        guard let range = path.range(of: "/imported/") else { return name }
        let relative = String(path[range.upperBound...])
        return relative.hasSuffix("/") ? String(relative.dropLast()) : relative
    }

    /// Source repo for imported external skills (e.g., "steipete/clawdis").
    /// Returns nil for official, custom, built-in, and sync skills.
    var sourceRepo: String? {
        guard category == .imported else { return nil }
        return SkillLockManager.shared.getEntry(lockKey: lockKey)?.sourceRepo
    }

    var resourceDescriptors: [Resource] {
        switch source {
        case .synced, .legacy:
            Self.localResources(in: folderURL).sorted {
                $0.displayPath.localizedCaseInsensitiveCompare($1.displayPath) == .orderedAscending
            }
        case .remote:
            packagedResources
        }
    }

    var resources: [URL] {
        resourceDescriptors.compactMap(\.localURL)
    }

    func updatePackagedResources(_ resources: [Resource]) {
        packagedResources = resources.sorted {
            $0.displayPath.localizedCaseInsensitiveCompare($1.displayPath) == .orderedAscending
        }
    }

    func apply(_ data: SkillData) {
        self.data = data
    }

    private static func inferLocalSource(from fileURL: URL) -> Source {
        if fileURL.path.contains("/skills/sync/") {
            return .synced(fileURL: fileURL)
        }
        return .legacy(fileURL: fileURL)
    }

    private static func inferCategory(from path: String) throws -> Category {
        if path.contains("/skills/custom/") || path.contains("/.agent/skills/custom/") {
            return .custom
        }
        if path.contains("/Resources/SystemSkills.bundle/") || path.contains("/SystemSkills.bundle/") || path.contains("/skills/system/") {
            return .system
        }
        if path.contains("/skills/sync/") {
            return .synced
        }
        if path.contains("/skills/imported/") || path.contains("/.agent/skills/imported/") {
            return .imported
        }
        if path.contains("/.agent/skills/reflected/") {
            return .reflected
        }
        throw SkillError.invalidSkillType
    }

    private static func localResources(in folderURL: URL) -> [Resource] {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent != "SKILL.md" }
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return Resource(
                    relativePath: url.lastPathComponent,
                    localURL: url,
                    kind: isDirectory == true ? .directory : .file
                )
            }
    }
}

// MARK: - UI Helpers

extension Skill {
    /// Convert color string from metadata to SwiftUI Color
    var uiIconColor: Color {
        guard let colorName = color?.lowercased() else {
            return .blue
        }

        switch colorName {
        case "red":
            return .red
        case "blue":
            return .blue
        case "green":
            return .green
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "pink":
            return .pink
        case "yellow":
            return .yellow
        case "gray", "grey":
            return .gray
        case "brown":
            return .brown
        case "cyan":
            return .cyan
        case "indigo":
            return .indigo
        case "mint":
            return .mint
        case "teal":
            return .teal
        default:
            return .blue
        }
    }
}

// MARK: - Preview Helpers

extension Skill {
    static func previewCustom() -> Skill {
        Skill(
            id: "/tmp/.openbridge/skills/custom/custom-skill/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "custom-skill",
                    description: "A custom user-created skill.",
                    metadata: .init(
                        displayName: "Custom Skill",
                        icon: "🚀",
                        color: "#007AFF",
                        outputDir: "/tmp/skills/output"
                    )
                ),
                content: ""
            ),
            category: .custom,
            source: .remote(rootPath: "/tmp/.openbridge/skills/custom/custom-skill")
        )
    }

    static func previewSync() -> Skill {
        Skill(
            id: "/tmp/skills/sync/sync-skill/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "sync-skill",
                    description: "A skill synced from external folder.",
                    metadata: .init(displayName: "Sync Skill", icon: "🔄", color: "#34C759")
                ),
                content: ""
            ),
            category: .synced,
            source: .synced(fileURL: URL(fileURLWithPath: "/tmp/skills/sync/sync-skill/SKILL.md"))
        )
    }

    static func previewImported() -> Skill {
        Skill(
            id: "/tmp/.openbridge/skills/imported/imported-skill/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "imported-skill",
                    description: "An imported skill from package.",
                    metadata: .init(displayName: "Imported Skill", icon: "📦", color: "#FF9500", pinned: true)
                ),
                content: ""
            ),
            category: .imported,
            source: .remote(rootPath: "/tmp/.openbridge/skills/imported/imported-skill")
        )
    }

    static func previewReflected() -> Skill {
        Skill(
            id: "/tmp/.openbridge/skills/reflected/2026-04-21/reflected-skill/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "reflected-skill",
                    description: "A reflected skill managed by the agent runtime.",
                    metadata: .init(displayName: "Reflected Skill", icon: "mirror.side.left.and.right", color: "#5AC8FA")
                ),
                content: ""
            ),
            category: .reflected,
            source: .remote(rootPath: "/tmp/.openbridge/skills/reflected/2026-04-21/reflected-skill")
        )
    }

    static func previewSystem() -> Skill {
        Skill(
            id: "/tmp/SystemSkills/system-skill/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "system-skill",
                    description: "A built-in system skill.",
                    metadata: .init(displayName: "System Skill", icon: "gearshape", color: "blue")
                ),
                content: ""
            ),
            category: .system,
            source: .remote(rootPath: "/tmp/SystemSkills/system-skill")
        )
    }
}
