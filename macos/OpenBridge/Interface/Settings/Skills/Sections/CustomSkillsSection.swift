import AppKit
import ComposerEditor
import SwiftUI
import UniformTypeIdentifiers

struct CustomSkillsSection: View {
    let onNavigateToDetail: (Skill) -> Void

    @Binding var selectedSkills: Set<Skill>
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var zipImportProgress: SkillZipImportProgress?
    @State private var skillManager = SkillManager.shared

    private var skills: [Skill] {
        skillManager.skills.filter {
            $0.category == .custom && !($0.visibility == .hidden && $0.disabled)
        }
    }

    private var isImportingZip: Bool {
        zipImportProgress != nil
    }

    var body: some View {
        Section {
            SkillList(
                skills: skills,
                onNavigateToDetail: onNavigateToDetail,
                onAdd: addSkill,
                selectedSkills: $selectedSkills
            )
        } header: {
            HStack {
                Text("Custom Skills")
                Spacer()
                Button {
                    Task {
                        await refreshSkills(force: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if skillManager.isRefreshingUserSkills {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(skillManager.isRefreshingUserSkills)
                .help("Refresh my skills")

                Button {
                    importSkillFromZip()
                } label: {
                    HStack {
                        Text("Import")
                        Image(systemName: "square.and.arrow.down")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isImportingZip)
                .help("Import skills from zip")
            }
        }
        .task {
            await refreshSkills(force: false)
        }
        .onReceiveNotification(name: NSApplication.didBecomeActiveNotification) { _ in
            Task {
                await refreshSkills(force: false)
            }
        }
        .sheet(isPresented: Binding(
            get: { zipImportProgress != nil },
            set: { isPresented in
                if !isPresented {
                    zipImportProgress = nil
                }
            }
        )) {
            if let zipImportProgress {
                SkillZipImportProgressSheet(progress: zipImportProgress)
                    .interactiveDismissDisabled()
            }
        }
        .alert("Message", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = alertMessage {
                Text(message)
            }
        }
    }

    private func addSkill() {
        Task { @MainActor in
            do {
                let newSkill = try await skillManager.createCustomSkill()
                onNavigateToDetail(newSkill)
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }

    private func refreshSkills(force: Bool) async {
        await skillManager.refreshUserSkills(notify: true, force: force)
    }

    private func importSkillFromZip() {
        Task { @MainActor in
            let urls = await FilePicker.pickURLs(
                allowedTypes: [.zip],
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                message: "Select a skill zip file to import"
            )
            guard let url = urls.first else { return }

            zipImportProgress = .init(
                title: String(localized: "Importing Skills"),
                message: String(localized: "Preparing zip file..."),
                detail: url.lastPathComponent,
                fractionCompleted: nil
            )

            do {
                let importedSkills = try await skillManager.importSkillFromZip(url) { progress in
                    zipImportProgress = progress
                }

                zipImportProgress = nil

                selectedSkills = Set(importedSkills)

                if importedSkills.count == 1, let skillName = importedSkills.first?.displayName {
                    alertMessage = String(
                        localized: "Successfully imported skill '\(skillName)'"
                    )
                    showingAlert = true
                } else if importedSkills.count > 1 {
                    alertMessage = String(
                        localized: "Successfully imported \(importedSkills.count) skills"
                    )
                    showingAlert = true
                }
            } catch {
                zipImportProgress = nil
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

private struct SkillZipImportProgressSheet: View {
    let progress: SkillZipImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(progress.title)
                .font(.title3.weight(.semibold))

            if let fractionCompleted = progress.fractionCompleted {
                ProgressView(value: fractionCompleted)
                    .controlSize(.large)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            Text(progress.message)
                .font(.body)

            if let detail = progress.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
