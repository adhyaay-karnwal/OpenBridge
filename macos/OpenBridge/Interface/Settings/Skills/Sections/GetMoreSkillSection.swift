import SwiftUI

// MARK: - Get More Skill Section

struct GetMoreSkillSection: View {
    var body: some View {
        Section {
            HStack {
                Text("Get More Skills")
                    .font(.headline)
                Spacer()
                Button {
                    NSWorkspace.shared.open(Constant.skillsURL)
                } label: {
                    Text("Open Skills Folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)
        }
    }
}

extension Constant {
    static var skillsURL: URL {
        SkillManager.shared.skillDirs.root
    }
}
