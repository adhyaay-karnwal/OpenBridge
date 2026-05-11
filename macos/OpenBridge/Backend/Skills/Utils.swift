import Foundation

// MARK: - Ignored Files

/// File names to ignore during skill import (e.g., macOS metadata files)
let skillIgnoredFileNames: Set<String> = [
    ".DS_Store",
]

// MARK: - SkillDirectories

struct SkillDirectories {
    let appRoot: URL
    let root: URL
    let custom: URL
    let sync: URL
    let imported: URL
    let system: URL
    let workspace: URL
    let migrationStateFile: URL

    /// Known sync skill folder definitions with display metadata
    struct SyncSkillSource {
        let key: String
        /// Path relative to home directory
        let relativePath: String
        let displayName: String
        let imageName: String?
    }

    static let defaultSyncSkillSources: [SyncSkillSource] = [
        SyncSkillSource(key: "claude", relativePath: ".claude/skills", displayName: "Claude", imageName: "claude"),
        SyncSkillSource(key: "codex", relativePath: ".codex/skills", displayName: "OpenAI Codex", imageName: "openai"),
        SyncSkillSource(key: "copilot", relativePath: ".copilot/skills", displayName: "GitHub Copilot", imageName: "github"),
        SyncSkillSource(key: "cursor", relativePath: ".cursor/skills", displayName: "Cursor", imageName: "cursor"),
        SyncSkillSource(key: "gemini", relativePath: ".gemini/skills", displayName: "Gemini", imageName: "google"),
        SyncSkillSource(key: "antigravity", relativePath: ".gemini/antigravity/skills", displayName: "Antigravity", imageName: "antigravity"),
        SyncSkillSource(key: "opencode", relativePath: ".config/opencode/skills", displayName: "OpenCode", imageName: "opencode"),
        SyncSkillSource(key: "openclaw", relativePath: ".openclaw/skills", displayName: "OpenClaw", imageName: "openclaw"),
    ]

    /// Create skill directories from home directory
    static func create() throws -> SkillDirectories {
        let homeDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let openBridgeDir = homeDir.appendingPathComponent(".openbridge", isDirectory: true)
        let skillsDir = openBridgeDir.appendingPathComponent("skills", isDirectory: true)

        let directories = SkillDirectories(
            appRoot: openBridgeDir,
            root: skillsDir,
            custom: skillsDir.appendingPathComponent("custom", isDirectory: true),
            sync: skillsDir.appendingPathComponent("sync", isDirectory: true),
            imported: skillsDir.appendingPathComponent("imported", isDirectory: true),
            system: skillsDir.appendingPathComponent("system", isDirectory: true),
            workspace: openBridgeDir.appendingPathComponent("workspace", isDirectory: true),
            migrationStateFile: skillsDir.appendingPathComponent(".custom-skill-migration.json", isDirectory: false)
        )

        try directories.ensureExists()
        return directories
    }

    /// Ensure all directories exist
    func ensureExists() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: custom, withIntermediateDirectories: true)
        try fm.createDirectory(at: sync, withIntermediateDirectories: true)
        try fm.createDirectory(at: imported, withIntermediateDirectories: true)
        try fm.createDirectory(at: system, withIntermediateDirectories: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    static func bundledSystemSkillsURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("SystemSkills.bundle", isDirectory: true),
           FileManager.default.fileExists(atPath: resourceURL.path)
        {
            return resourceURL
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/SystemSkills.bundle", isDirectory: true)
    }

    static func syncSkillSource(for url: URL) -> SyncSkillSource? {
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        let standardized = url.standardized
        return defaultSyncSkillSources.first { source in
            homeDir.appendingPathComponent(source.relativePath).standardized == standardized
        }
    }

    func getResolvedSyncSkillFolderURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: sync,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ))?.compactMap { $0.resolvingSymlinksInPath().standardized } ?? []
    }
}
