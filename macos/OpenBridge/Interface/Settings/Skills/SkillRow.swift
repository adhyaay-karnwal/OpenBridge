import SwiftUI

struct SkillRow: View {
    @Environment(SettingsManager.self) private var settings

    @Bindable var skill: Skill
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    var onNavigateToDetail: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var showEmojiPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var localPinned: Bool?
    @State private var localDisabled: Bool?
    @State private var isMutatingState = false

    private var iconBackgroundStyle: AnyShapeStyle {
        skill.color.map { AnyShapeStyle(Color(hex: $0).gradient) } ?? AnyShapeStyle(Color.black.gradient)
    }

    private var displayedPinned: Bool {
        localPinned ?? skill.pinned
    }

    private var displayedDisabled: Bool {
        localDisabled ?? skill.disabled
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { !displayedDisabled },
            set: { isEnabled in
                handleDisabledToggle(nextDisabled: !isEnabled)
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            iconView

            skillInfo
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect?()
                }

            if skill.supportsUpdates, skill.isUpdating {
                ProgressView()
                    .controlSize(.small)
            }

            HStack(spacing: 12) {
                pinButton
                editButton
                enabledToggle
            }
        }
        .padding(.vertical, 4)
        .opacity(skill.isUpdating ? 0.6 : 1.0)
        .contextMenu { contextMenuContent }
        .onAppear {
            synchronizeDisplayedState()
        }
        .onChange(of: skill.id) { _, _ in
            synchronizeDisplayedState()
        }
        .onChange(of: skill.pinned) { _, nextValue in
            guard !isMutatingState else { return }
            localPinned = nextValue
        }
        .onChange(of: skill.disabled) { _, nextValue in
            guard !isMutatingState else { return }
            localDisabled = nextValue
        }
        .alert(String(localized: "Delete Skill"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete"), role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete '\(skill.displayName)'? This action cannot be undone.")
        }
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        if skill.canEditInApp == false {
            staticIcon
        } else {
            iconButton
        }
    }

    private var staticIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconBackgroundStyle)
                .frame(width: 28, height: 28)

            if let icon = skill.icon, icon.isEmojiOnly {
                Text(icon)
                    .font(.system(size: 14))
            } else {
                Image(systemName: skill.icon ?? "document.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        }
    }

    private var iconButton: some View {
        Button {
            showEmojiPicker = true
        } label: {
            staticIcon
        }
        .buttonStyle(.plain)
        .help(String(localized: "Change Icon"))
        .popover(isPresented: $showEmojiPicker) {
            EmojiPickerView { selectedEmoji, backgroundColor in
                Task {
                    try? await SkillManager.shared.setSkillPresentation(
                        skill,
                        icon: selectedEmoji,
                        color: backgroundColor
                    )
                }
                showEmojiPicker = false
            }
        }
    }

    // MARK: - Skill Info

    private var skillInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(skill.displayName)
                    .font(.system(size: 13))
                if let repo = skill.sourceRepo {
                    Text(repo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            Text(skill.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pin Button

    @ViewBuilder
    private var pinButton: some View {
        let canPin = skill.canPinInApp
        let isPinned = displayedPinned

        if canPin {
            Button {
                handlePinToggle(nextPinned: !isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(isPinned ? settings.accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(isMutatingState)
            .help(isPinned ? String(localized: "Unpin") : String(localized: "Pin"))
        }
    }

    // MARK: - Enabled Toggle

    @ViewBuilder
    private var enabledToggle: some View {
        let canToggleEnabled = skill.canToggleEnabledInApp

        if canToggleEnabled {
            TintedToggle("", isOn: isEnabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(isMutatingState)
                .help(displayedDisabled ? String(localized: "Enable") : String(localized: "Disable"))
        }
    }

    // MARK: - Edit Button

    @ViewBuilder
    private var editButton: some View {
        if let onNavigateToDetail {
            Button {
                onNavigateToDetail()
            } label: {
                Image(systemName: "pencil.line")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        let canPin = skill.canPinInApp
        let isPinned = displayedPinned
        let canToggleEnabled = skill.canToggleEnabledInApp
        let isDisabled = displayedDisabled

        if canPin {
            Button {
                handlePinToggle(nextPinned: !isPinned)
            } label: {
                Label(
                    isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }

        if let onNavigateToDetail {
            Button {
                onNavigateToDetail()
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil.line")
            }
        }

        if skill.canDelete {
            Divider()
        }

        if canToggleEnabled {
            Button {
                handleDisabledToggle(nextDisabled: !isDisabled)
            } label: {
                Label(
                    isDisabled ? String(localized: "Enable") : String(localized: "Disable"),
                    systemImage: isDisabled ? "checkmark.circle" : "xmark.circle"
                )
            }
        }

        if onDelete != nil {
            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func synchronizeDisplayedState() {
        localPinned = skill.pinned
        localDisabled = skill.disabled
    }

    private func handlePinToggle(nextPinned: Bool) {
        let previousPinned = displayedPinned
        let previousDisabled = displayedDisabled
        localPinned = nextPinned
        if nextPinned {
            localDisabled = false
        }
        isMutatingState = true

        Task {
            do {
                let updatedSkill = try await SkillManager.shared.setSkillPinned(skill, isPinned: nextPinned)
                await MainActor.run {
                    localPinned = updatedSkill.pinned
                    localDisabled = updatedSkill.disabled
                    isMutatingState = false
                }
            } catch {
                await MainActor.run {
                    localPinned = previousPinned
                    localDisabled = previousDisabled
                    isMutatingState = false
                }
            }
        }
    }

    private func handleDisabledToggle(nextDisabled: Bool) {
        let previousPinned = displayedPinned
        let previousDisabled = displayedDisabled
        localDisabled = nextDisabled
        if nextDisabled {
            localPinned = false
        }
        isMutatingState = true

        Task {
            do {
                let updatedSkill = try await SkillManager.shared.setSkillDisabled(skill, isDisabled: nextDisabled)
                await MainActor.run {
                    localPinned = updatedSkill.pinned
                    localDisabled = updatedSkill.disabled
                    isMutatingState = false
                }
            } catch {
                await MainActor.run {
                    localPinned = previousPinned
                    localDisabled = previousDisabled
                    isMutatingState = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        Section("Custom Remote") {
            SkillRow(skill: .previewCustom(), onNavigateToDetail: {})
        }
        Section("Synced") {
            SkillRow(skill: .previewSync(), onNavigateToDetail: {})
        }
        Section("Imported Remote") {
            SkillRow(skill: .previewImported(), onNavigateToDetail: {})
        }
    }
    .frame(minHeight: 400)
    .padding(20)
    .environment(SettingsManager.shared)
}
