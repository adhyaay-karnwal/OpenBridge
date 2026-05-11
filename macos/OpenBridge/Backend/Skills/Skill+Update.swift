import Foundation

// MARK: - Skill Update

extension Skill {
    /// Check if this skill has an update available
    /// Returns the new version if update available, nil otherwise
    func checkForUpdate() async -> String? {
        nil
    }

    /// Update this skill to the latest version
    /// Returns the new version after update
    @discardableResult
    func performUpdate() async throws -> String {
        throw SkillError.invalidSkillType
    }
}
