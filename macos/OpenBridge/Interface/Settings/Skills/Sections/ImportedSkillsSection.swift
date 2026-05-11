import AppKit
import SwiftUI

struct ImportedSkillsSection: View {
    let onNavigateToDetail: (Skill) -> Void

    @Binding var selectedSkills: Set<Skill>
    @State private var skillManager = SkillManager.shared

    private var skills: [Skill] {
        skillManager.skills.filter {
            $0.category == .imported && !($0.visibility == .hidden && $0.disabled)
        }
    }

    @State private var showingDeleteConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        if !skills.isEmpty {
            Section("Imported Skills") {
                SkillList(
                    skills: skills,
                    onNavigateToDetail: onNavigateToDetail,
                    onAdd: nil,
                    selectedSkills: $selectedSkills
                )
            }
            .alert("Message", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = alertMessage {
                    Text(message)
                }
            }
        }
    }
}
