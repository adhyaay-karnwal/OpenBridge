import Foundation

// MARK: - Skill Source

/// Represents the source of a skill package.
enum SkillSource: String, Codable {
    case official
    case external
}

// MARK: - Skill Info

/// Represents skill information from an external skill index.
struct SkillInfo: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
    let displayName: String?
    let description: String?
    let category: String?
    let heroURL: String?
    let videoURL: String?

    // External skill metadata (populated only for external skills)
    let sourceRepo: String?
    let sourcePath: String?
    let branch: String?
    let contentHtml: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, category
        case displayName = "display_name"
        case heroURL = "hero_url"
        case videoURL = "video_url"
        case version
        // External fields not in official API response, so we don't decode them
    }

    init(id: String, name: String, version: String, displayName: String? = nil, description: String?, category: String?, heroURL: String?, videoURL: String? = nil, sourceRepo: String? = nil, sourcePath: String? = nil, branch: String? = nil, contentHtml: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.displayName = displayName
        self.description = description
        self.category = category
        self.heroURL = heroURL
        self.videoURL = videoURL
        self.sourceRepo = sourceRepo
        self.sourcePath = sourcePath
        self.branch = branch
        self.contentHtml = contentHtml
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        heroURL = try container.decodeIfPresent(String.self, forKey: .heroURL)
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
        // External fields are not in the API response, set to nil
        sourceRepo = nil
        sourcePath = nil
        branch = nil
        contentHtml = nil
    }
}

// MARK: - Skill Import

extension SkillManager {
    /// Fetch skill info for the legacy skill import dialog.
    @MainActor
    func fetchSkillInfo(name _: String, source _: SkillSource = .official, repo _: String? = nil) async throws -> SkillInfo {
        throw SkillError.importFailed(String(localized: "Online skill library import is not available in this local build. Import skills from a local zip file or sync folder instead."))
    }

    /// Legacy online skill-library import entry point.
    @MainActor
    func importSkill(name: String, source: SkillSource = .official, repo: String? = nil) async {
        logger.info("Ignoring online skill import in local build: \(name), source: \(source.rawValue), repo: \(repo ?? "none")")
    }
}

// MARK: - Onboarding Skills

extension SkillManager {
    /// Online skill discovery is not available in the local build.
    @MainActor
    func fetchPublishedSkills() async throws -> [SkillInfo] {
        []
    }

    /// Get names of all imported skills
    func getImportedSkillNames() -> Set<String> {
        Set(skills.filter { $0.category == .imported }.map(\.name))
    }

    /// Online onboarding skill import is not available in the local build.
    @MainActor
    @discardableResult
    func importSkillSilently(name _: String) async throws -> Skill {
        throw SkillError.importFailed(String(localized: "Online onboarding skill import is not available in this local build."))
    }

    /// Delete an imported skill by name
    @MainActor
    func deleteImportedSkill(name: String) async throws {
        guard let skill = skills.first(where: { $0.name == name && $0.category == .imported }) else {
            logger.warning("Skill not found for deletion: \(name)")
            return
        }

        // deleteSkill handles lock entry removal for imported skills
        try await deleteSkill(skill: skill)
        logger.info("Deleted imported skill: \(name)")
    }
}
