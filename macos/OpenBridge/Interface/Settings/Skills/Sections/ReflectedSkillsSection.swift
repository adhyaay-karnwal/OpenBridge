import SwiftUI

struct ReflectedSkillsSection: View {
    let onNavigateToDetail: (Skill) -> Void

    @Binding var selectedSkills: Set<Skill>
    @State private var skillManager = SkillManager.shared

    private var skills: [Skill] {
        skillManager.skills.filter {
            $0.category == .reflected && !($0.visibility == .hidden && $0.disabled)
        }
    }

    var body: some View {
        if !skills.isEmpty {
            Section("Reflected Skills") {
                SkillList(
                    skills: skills,
                    onNavigateToDetail: onNavigateToDetail,
                    onAdd: nil,
                    selectedSkills: $selectedSkills
                )
            }
        }
    }
}
