import SwiftUI

extension Skill: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - System Skills Settings View

struct SystemSkillsSettingsView: View {
    var body: some View {
        Form {
            SystemSkillsInfoBanner()
            SystemSkillsSection()
        }
        .formStyle(.grouped)
        .navigationTitle("System Skills")
    }
}

// MARK: - My Skills Settings View

struct MySkillsSettingsView: View {
    @Binding var navigationPath: NavigationPath

    @State private var selectedSkills: Set<Skill> = []

    private func navigateToDetail(_ skill: Skill) {
        navigationPath.append(SettingsDestination.skillDetail(skill))
    }

    var body: some View {
        Form {
            MySkillsInfoBanner()

            CustomSkillsSection(
                onNavigateToDetail: navigateToDetail,
                selectedSkills: $selectedSkills
            )

            ImportedSkillsSection(
                onNavigateToDetail: navigateToDetail,
                selectedSkills: $selectedSkills
            )

            ReflectedSkillsSection(
                onNavigateToDetail: navigateToDetail,
                selectedSkills: $selectedSkills
            )

            GetMoreSkillSection()
        }
        .formStyle(.grouped)
        .navigationTitle("My Skills")
    }
}

// MARK: - Synced Skills Settings View

struct SyncedSkillsSettingsView: View {
    var body: some View {
        Form {
            SyncedSkillsInfoBanner()
            SyncFolderSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Synced Skills")
    }
}

#Preview("System Skills") {
    SystemSkillsSettingsView()
        .environment(SettingsManager.shared)
}

#Preview("My Skills") {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        MySkillsSettingsView(navigationPath: $path)
    }
    .environment(SettingsManager.shared)
}

#Preview("Synced Skills") {
    SyncedSkillsSettingsView()
        .environment(SettingsManager.shared)
}
