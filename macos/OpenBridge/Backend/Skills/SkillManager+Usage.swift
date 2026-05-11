import Foundation

extension SkillManager {
    func recordSkillUsage(skillName: String) {
        SettingsManager.shared.skillLastUsedTimes[skillName] = Date()
    }

    func lastUsedTime(for skillName: String) -> Date {
        SettingsManager.shared.skillLastUsedTimes[skillName] ?? .distantPast
    }

    func removeSkillUsage(skillName: String) {
        SettingsManager.shared.skillLastUsedTimes.removeValue(forKey: skillName)
    }

    func renameSkillUsage(from oldName: String, to newName: String) {
        var times = SettingsManager.shared.skillLastUsedTimes
        guard let timestamp = times[oldName] else { return }
        times.removeValue(forKey: oldName)
        times[newName] = timestamp
        SettingsManager.shared.skillLastUsedTimes = times
    }

    func cleanupOrphanedSkillUsage() {
        let existingSkillNames = Set(skills.map(\.name))
        var times = SettingsManager.shared.skillLastUsedTimes
        let orphanedKeys = times.keys.filter { !existingSkillNames.contains($0) }
        for key in orphanedKeys {
            times.removeValue(forKey: key)
        }
        SettingsManager.shared.skillLastUsedTimes = times
    }
}
