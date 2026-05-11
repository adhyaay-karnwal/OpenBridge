import SwiftUI

// MARK: - System Skill Item

enum SystemSkillItem: Identifiable {
    case skill(Skill)

    var id: String {
        switch self {
        case let .skill(skill):
            "skill-\(skill.name)"
        }
    }

    var displayName: String {
        switch self {
        case let .skill(skill):
            skill.displayName
        }
    }
}

// MARK: - System Skill Item Row

struct SystemSkillItemRow: View {
    let item: SystemSkillItem

    var body: some View {
        switch item {
        case let .skill(skill):
            SkillRow(skill: skill)
        }
    }
}
