import SwiftUI

struct SystemSkillsSection: View {
    @State private var skillManager = SkillManager.shared

    private var systemSkills: [Skill] {
        skillManager.skills.filter {
            $0.category == .system && !($0.visibility == .hidden && $0.disabled)
        }
    }

    private var visibleItems: [SystemSkillItem] {
        let visibleSkills = systemSkills.filter { $0.visibility == .visible }

        return visibleSkills.map { SystemSkillItem.skill($0) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var hasToggledItems: Bool {
        systemSkills.contains { $0.visibility == .toggled }
    }

    var body: some View {
        Section {
            List {
                if visibleItems.isEmpty, !hasToggledItems {
                    Text("No system skills found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleItems) { item in
                        SystemSkillItemRow(item: item)
                    }

                    NavigationLink(value: SettingsDestination.allSystemSkills) {
                        HStack {
                            Text("Show more")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("System Skills")
        }
        .task {
            await skillManager.refreshSystemSkills(notify: true)
        }
    }
}

// MARK: - All System Skills View

struct AllSystemSkillsView: View {
    @State private var skillManager = SkillManager.shared

    private var sortedItems: [SystemSkillItem] {
        let visibleSkills = skillManager.skills.filter {
            $0.category == .system && $0.visibility != .hidden
        }

        return visibleSkills.map { SystemSkillItem.skill($0) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section {
                List {
                    if sortedItems.isEmpty {
                        Text("No system skills found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedItems) { item in
                            SystemSkillItemRow(item: item)
                        }
                    }
                }
            } header: {
                Text("All System Skills")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("All System Skills")
        .task {
            await skillManager.refreshSystemSkills(notify: true)
        }
    }
}
