import SwiftUI

struct SkillList: View {
    let skills: [Skill]
    let onNavigateToDetail: (Skill) -> Void
    let onAdd: (() -> Void)?

    @Binding var selectedSkills: Set<Skill>

    @State private var lastSelectedSkill: Skill?
    @State private var showingDeleteConfirmation = false
    @State private var showingAlert = false
    @State private var alertMessage: String?

    /// Skills in this list that are currently selected (ignores selections from other lists sharing the same binding)
    private var selectedSkillsInList: Set<Skill> {
        selectedSkills.intersection(skills)
    }

    private var deletableSelectedSkills: Set<Skill> {
        selectedSkillsInList.filter(\.canDelete)
    }

    var body: some View {
        List {
            if skills.isEmpty {
                Text("No skills found")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .frame(height: 48)
            } else {
                ForEach(skills, id: \.id) { skill in
                    let isSelected = selectedSkills.contains(skill)
                    let isLast = skill == skills.last

                    SkillRow(
                        skill: skill,
                        isSelected: isSelected,
                        onSelect: { handleSkillSelection(skill: skill) },
                        onNavigateToDetail: { onNavigateToDetail(skill) },
                        onDelete: skill.canDelete ? { deleteSingleSkill(skill) } : nil
                    )
                    .listRowBackground(isSelected ? Color.accentColor : Color.clear)
                    .listRowSeparator(isLast ? .hidden : .automatic)
                }
            }

            HStack {
                if let onAdd {
                    Button {
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("Add custom skill")

                    Divider()
                }

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Remove selected skills")
                .disabled(deletableSelectedSkills.isEmpty)

                Spacer()
            }
            .listRowBackground(Color.primary.opacity(0.06))
        }
        .alert("Delete Skill", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedSkills()
                showingDeleteConfirmation = false
            }
        } message: {
            let toDelete = deletableSelectedSkills
            if toDelete.count == 1, let skill = toDelete.first {
                Text(
                    "Are you sure you want to delete '\(skill.displayName)'? This action cannot be undone."
                )
            } else if toDelete.count > 1 {
                Text(
                    "Are you sure you want to delete \(toDelete.count) skills? This action cannot be undone."
                )
            }
        }
    }

    private func handleSkillSelection(skill: Skill) {
        let modifierFlags = NSEvent.modifierFlags
        let isCommand = modifierFlags.contains(.command)
        let isShift = modifierFlags.contains(.shift)

        if isShift, let last = lastSelectedSkill, let lastIndex = skills.firstIndex(of: last), let currentIndex = skills.firstIndex(of: skill) {
            let range = lastIndex < currentIndex ? lastIndex ... currentIndex : currentIndex ... lastIndex
            let rangeSkills = range.compactMap { skills[safe: $0] }
            selectedSkills.formUnion(rangeSkills)
        } else if isCommand {
            if selectedSkills.contains(skill) {
                selectedSkills.remove(skill)
                if lastSelectedSkill == skill {
                    lastSelectedSkill = selectedSkills.first
                }
            } else {
                selectedSkills.insert(skill)
                lastSelectedSkill = skill
            }
        } else {
            if selectedSkills.count == 1, selectedSkills.contains(skill) {
                selectedSkills.removeAll()
                lastSelectedSkill = nil
            } else {
                selectedSkills = [skill]
                lastSelectedSkill = skill
            }
        }
    }

    private func deleteSingleSkill(_ skill: Skill) {
        Task { @MainActor in
            do {
                try await SkillManager.shared.deleteSkill(skill: skill)
                selectedSkills.remove(skill)
                if lastSelectedSkill == skill {
                    lastSelectedSkill = nil
                }
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }

    private func deleteSelectedSkills() {
        let toDelete = deletableSelectedSkills
        Task { @MainActor in
            do {
                for skill in toDelete {
                    try await SkillManager.shared.deleteSkill(skill: skill)
                }
                selectedSkills.subtract(toDelete)
                lastSelectedSkill = nil
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

// MARK: - Preview

#Preview("With Skills") {
    @Previewable @State var selectedSkills: Set<Skill> = []

    let skills = [
        Skill.previewCustom(),
        Skill(
            id: "/tmp/.openbridge/skills/custom/code-review/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "code-review",
                    description: "Review code and provide suggestions for improvement.",
                    metadata: .init(displayName: "Code Review", icon: "👨‍💻", color: "#34C759")
                ),
                content: ""
            ),
            category: .custom,
            source: .remote(rootPath: "/tmp/.openbridge/skills/custom/code-review")
        ),
        Skill(
            id: "/tmp/.openbridge/skills/custom/translator/SKILL.md",
            data: SkillData(
                frontmatter: .init(
                    name: "translator",
                    description: "Translate text between languages.",
                    metadata: .init(displayName: "Translator", icon: "🌐", color: "#FF9500", disabled: true)
                ),
                content: ""
            ),
            category: .custom,
            source: .remote(rootPath: "/tmp/.openbridge/skills/custom/translator")
        ),
    ]

    SkillList(
        skills: skills,
        onNavigateToDetail: { _ in },
        onAdd: {},
        selectedSkills: $selectedSkills
    )
    .frame(height: 300)
    .environment(SettingsManager.shared)
}

#Preview("Empty") {
    @Previewable @State var selectedSkills: Set<Skill> = []

    SkillList(
        skills: [],
        onNavigateToDetail: { _ in },
        onAdd: {},
        selectedSkills: $selectedSkills
    )
    .frame(height: 200)
    .environment(SettingsManager.shared)
}
