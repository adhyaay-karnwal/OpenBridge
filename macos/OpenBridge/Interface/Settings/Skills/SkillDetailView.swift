import AppKit
import ComposerEditor
import SwiftUI

struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsManager.self) private var settings

    @State private var currentSkill: Skill?
    @State private var skillDisplayName: String
    @State private var skillDescription: String
    @State private var skillContent: String
    @State private var skillIcon: String
    @State private var skillColor: String
    @State private var isDisabled: Bool
    @State private var isPinned: Bool
    @State private var isSendDirectly: Bool
    @State private var skillResources: [Skill.Resource]
    @State private var skillOutputDir: String?
    @State private var selectedResource: Skill.Resource?
    @State private var showEmojiPicker = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var showingDiscardAlert = false
    @State private var pendingCloseAction: (() -> Void)?
    @State private var isSaving = false

    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isDescriptionFieldFocused: Bool
    @FocusState private var isContentFieldFocused: Bool

    private var isEditableSkill: Bool {
        currentSkill?.canEditInApp == true
    }

    private var showsMetadataSection: Bool {
        currentSkill?.canEditInApp == true ||
            currentSkill?.canToggleEnabledInApp == true ||
            currentSkill?.canPinInApp == true
    }

    private var showsActionSection: Bool {
        currentSkill?.canOpenInFileSystem == true
    }

    private var canSave: Bool {
        hasUnsavedChanges && !skillDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        guard let skill = currentSkill else { return false }
        let resourceChanged =
            Set(skillResources.map(\.id)) !=
            Set(skill.resourceDescriptors.map(\.id))

        return skillDisplayName != skill.displayName ||
            skillDescription != skill.description ||
            skillContent != skill.content ||
            skillIcon != (skill.icon ?? "") ||
            skillColor != (skill.color ?? "") ||
            isDisabled != skill.disabled ||
            isPinned != skill.pinned ||
            isSendDirectly != skill.sendDirectly ||
            resourceChanged ||
            skillOutputDir != skill.outputDir
    }

    init(skill: Skill? = nil) {
        _currentSkill = State(initialValue: skill)
        _skillDisplayName = State(initialValue: skill?.displayName ?? "")
        _skillDescription = State(initialValue: skill?.description ?? "")
        _skillContent = State(initialValue: skill?.content ?? "")
        _skillIcon = State(initialValue: skill?.icon ?? "")
        _skillColor = State(initialValue: skill?.color ?? "")
        _isDisabled = State(initialValue: skill?.disabled ?? false)
        _isPinned = State(initialValue: skill?.pinned ?? false)
        _isSendDirectly = State(initialValue: skill?.sendDirectly ?? false)
        _skillResources = State(initialValue: skill?.resourceDescriptors ?? [])
        _skillOutputDir = State(initialValue: skill?.outputDir)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                Form {
                    skillInfoSection
                    if showsMetadataSection {
                        skillMetaSection
                    }
                    skillResourcesSection

                    if showsActionSection {
                        actionsSection
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .background(
            WindowCloseInterceptor(
                shouldIntercept: hasUnsavedChanges,
                onCloseAttempt: { closeWindow in
                    pendingCloseAction = closeWindow
                    showingDiscardAlert = true
                }
            )
        )
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .navigation) {
                    Button {
                        pendingCloseAction = { dismiss() }
                        showingDiscardAlert = true
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Spacer()
                Button("Save") {
                    save()
                }
                .foregroundStyle(canSave ? settings.accentColor : .secondary)
                .padding([.leading, .trailing], 4)
                .disabled(!canSave || isSaving)
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Unsaved Changes", isPresented: $showingDiscardAlert) {
            Button("Save") {
                save {
                    pendingCloseAction?()
                    pendingCloseAction = nil
                }
            }
            Button("Discard", role: .destructive) {
                pendingCloseAction?()
                pendingCloseAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloseAction = nil
            }
        } message: {
            Text("You have unsaved changes. Would you like to save them?")
        }
    }
}

private extension SkillDetailView {
    var header: some View {
        VStack(spacing: 16) {
            Button {
                showEmojiPicker = true
            } label: {
                ZStack {
                    Rectangle()
                        .fill(skillColor.isEmpty ? Color(nsColor: .controlBackgroundColor) : Color(hex: skillColor))
                        .frame(width: 72, height: 72)
                        .cornerRadius(12)

                    if !skillIcon.isEmpty {
                        if skillIcon.isEmojiOnly {
                            Text(skillIcon)
                                .font(.system(size: 42))
                        } else {
                            Image(systemName: skillIcon)
                                .font(.system(size: 42))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "text.page")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEmojiPicker) {
                EmojiPickerView { selectedEmoji, backgroundColor in
                    skillIcon = selectedEmoji
                    skillColor = backgroundColor ?? ""
                    showEmojiPicker = false
                }
            }

            TextField(String(localized: "Skill Name"), text: $skillDisplayName)
                .font(.headline)
                .fontWeight(.semibold)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .disabled(!isEditableSkill)
                .onChange(of: isNameFieldFocused) { _, focused in
                    guard !focused, skillDisplayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    skillDisplayName = currentSkill?.displayName ?? ""
                }
        }
    }

    var skillInfoSection: some View {
        Section("Skill Info") {
            VStack(alignment: .leading, spacing: 16) {
                descriptionSection
                contentSection
            }
        }
    }

    var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.body)
                .fontWeight(.medium)

            editorContainer(
                placeholder: "Describe what you would like this skill to do...",
                text: $skillDescription,
                height: 60,
                isEditable: isEditableSkill,
                focused: $isDescriptionFieldFocused
            )
        }
    }

    var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.body)
                .fontWeight(.medium)

            editorContainer(
                placeholder: "Write detailed instructions or content for this skill...",
                text: $skillContent,
                height: 200,
                isEditable: isEditableSkill,
                focused: $isContentFieldFocused
            )
        }
    }

    func editorContainer(
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        height: CGFloat,
        isEditable: Bool,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }

            if isEditable {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 10)
                    .frame(height: height)
                    .focused(focused)
            } else {
                ScrollView {
                    Text(text.wrappedValue)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                .frame(height: height)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    var skillMetaSection: some View {
        Group {
            Section {
                if currentSkill?.canToggleEnabledInApp == true {
                    TintedToggle("Enable Skill", isOn: Binding(
                        get: { !isDisabled },
                        set: {
                            isDisabled = !$0
                            if isDisabled {
                                isPinned = false
                            }
                        }
                    ))
                }

                if currentSkill?.canPinInApp == true {
                    TintedToggle("Pin Skill", isOn: Binding(
                        get: { isPinned },
                        set: {
                            isPinned = $0
                            if isPinned {
                                isDisabled = false
                            }
                        }
                    ))

                    if isPinned, currentSkill?.canEditInApp == true {
                        TintedToggle("Run Immediately", isOn: $isSendDirectly)
                    }
                }
            }

            if currentSkill?.canEditInApp == true {
                Section("Default Output Directory") {
                    HStack {
                        Button {
                            selectOutputDirectory()
                        } label: {
                            HStack {
                                Text(skillOutputDir ?? String(localized: "Select default output directory"))
                                    .font(.body)
                                    .foregroundStyle(skillOutputDir != nil ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if skillOutputDir == nil {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEditableSkill)

                        if skillOutputDir != nil {
                            Button {
                                skillOutputDir = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear output directory")
                            .disabled(!isEditableSkill)
                        }
                    }
                }
            }
        }
    }

    var skillResourcesSection: some View {
        Section("Skill Resources") {
            List {
                if skillResources.isEmpty {
                    Text("No resources found")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .frame(height: 48)
                } else {
                    ForEach(skillResources) { resource in
                        resourceRow(for: resource)
                    }
                }

                resourceToolbarRow
            }
        }
    }

    func resourceRow(for resource: Skill.Resource) -> some View {
        let isSelected = selectedResource == resource
        let isLast = resource == skillResources.last
        let isDirectory = resource.kind == .directory

        return HStack(spacing: 8) {
            Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 12, weight: .regular))
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
                .background(isDirectory ? .blue : .gray)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(resource.displayPath)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor : Color.clear)
        .listRowSeparator(isLast ? .hidden : .automatic)
        .onTapGesture {
            selectedResource = isSelected ? nil : resource
        }
    }

    var resourceToolbarRow: some View {
        HStack {
            Button {
                addResourceFiles()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help("Add resource")

            Divider()

            Button {
                guard let selectedResource else { return }
                removeResource(selectedResource)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help("Remove resource")
            .disabled(selectedResource == nil)

            Spacer()
        }
        .listRowBackground(Color.primary.opacity(0.06))
        .disabled(currentSkill?.canManageLocalResources != true)
    }

    var actionsSection: some View {
        Section {
            if currentSkill?.canOpenInFileSystem == true {
                Button {
                    openInEditor()
                } label: {
                    HStack {
                        Text("Open in editor")
                            .font(.body)
                        Spacer()
                        Text(verbatim: "Cursor")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    openInFinder()
                } label: {
                    HStack {
                        Text("Open in Finder")
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension SkillDetailView {
    func refresh() {
        skillDisplayName = currentSkill?.displayName ?? ""
        skillDescription = currentSkill?.description ?? ""
        skillContent = currentSkill?.content ?? ""
        skillIcon = currentSkill?.icon ?? ""
        skillColor = currentSkill?.color ?? ""
        isDisabled = currentSkill?.disabled ?? false
        isPinned = currentSkill?.pinned ?? false
        isSendDirectly = currentSkill?.sendDirectly ?? false
        skillResources = currentSkill?.resourceDescriptors ?? []
        skillOutputDir = currentSkill?.outputDir
    }

    func selectOutputDirectory() {
        Task { @MainActor in
            let urls = await FilePicker.pickURLs(
                canChooseFiles: false,
                canChooseDirectories: true,
                allowsMultipleSelection: false
            )
            skillOutputDir = urls.first?.path
        }
    }

    func addResourceFiles() {
        Task { @MainActor in
            let urls = await FilePicker.pickURLs(
                canChooseFiles: true,
                canChooseDirectories: true,
                allowsMultipleSelection: true,
                showsHiddenFiles: true,
                message: "Select resource files or folders to add to this skill"
            )
            guard !urls.isEmpty else { return }
            guard currentSkill?.canManageLocalResources == true else { return }

            let newResources = urls.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return Skill.Resource(
                    relativePath: url.lastPathComponent,
                    localURL: url,
                    kind: isDirectory == true ? .directory : .file
                )
            }
            let uniqueResources = Dictionary(
                (skillResources + newResources).map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            skillResources = uniqueResources.values.sorted {
                $0.displayPath.localizedCaseInsensitiveCompare($1.displayPath) == .orderedAscending
            }
            if let firstNewResource = newResources.first {
                selectedResource = firstNewResource
            }
        }
    }

    func removeResource(_ resource: Skill.Resource) {
        skillResources = skillResources.filter { $0 != resource }
        if selectedResource == resource {
            selectedResource = nil
        }
    }

    func openInEditor() {
        Task {
            do {
                guard let skillFolder = currentSkill?.folderURL else { return }

                let fileManager = FileManager.default
                let appDirectories = fileManager.urls(
                    for: .applicationDirectory,
                    in: [.systemDomainMask, .localDomainMask, .userDomainMask]
                )

                for appDirectory in appDirectories {
                    let apps = try fileManager.contentsOfDirectory(
                        at: appDirectory,
                        includingPropertiesForKeys: nil,
                        options: []
                    )
                    for app in apps where app.lastPathComponent == "Cursor.app" {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.createsNewApplicationInstance = true
                        configuration.arguments = [skillFolder.path]
                        try await NSWorkspace.shared.open(app, configuration: configuration)
                        dismiss()
                        return
                    }
                }
            } catch {
                errorMessage = "Failed to open editor: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }

    func openInFinder() {
        guard let skillFolder = currentSkill?.folderURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: skillFolder.path)
    }

    func save(afterSuccess: (() -> Void)? = nil) {
        Task { @MainActor in
            await performSave(afterSuccess: afterSuccess)
        }
    }

    @MainActor
    func performSave(afterSuccess: (() -> Void)? = nil) async {
        guard let currentSkill else { return }
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            if currentSkill.canEditInApp {
                try await SkillManager.shared.updateRemoteSkill(
                    currentSkill,
                    with: .init(
                        displayName: skillDisplayName,
                        description: skillDescription,
                        content: skillContent,
                        icon: skillIcon,
                        color: skillColor,
                        pinned: isPinned,
                        disabled: isDisabled,
                        sendDirectly: isSendDirectly,
                        outputDir: skillOutputDir
                    )
                )
            } else if currentSkill.category == .system,
                      currentSkill.pinned != isPinned || currentSkill.disabled != isDisabled
            {
                try await SkillManager.shared.updateSystemSkillState(
                    currentSkill,
                    pinned: isPinned,
                    disabled: isDisabled
                )
            }

            refresh()
            afterSuccess?()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
}

private struct WindowCloseInterceptor: NSViewRepresentable {
    let shouldIntercept: Bool
    let onCloseAttempt: (@escaping () -> Void) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.setupDelegate(for: window)
            }
        }
        return view
    }

    func updateNSView(_: NSView, context: Context) {
        context.coordinator.shouldIntercept = shouldIntercept
        context.coordinator.onCloseAttempt = onCloseAttempt
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldIntercept: shouldIntercept, onCloseAttempt: onCloseAttempt)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldIntercept: Bool
        var onCloseAttempt: (@escaping () -> Void) -> Void
        private weak var originalDelegate: NSWindowDelegate?
        private weak var observedWindow: NSWindow?

        init(shouldIntercept: Bool, onCloseAttempt: @escaping (@escaping () -> Void) -> Void) {
            self.shouldIntercept = shouldIntercept
            self.onCloseAttempt = onCloseAttempt
        }

        func setupDelegate(for window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window
            originalDelegate = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if shouldIntercept {
                onCloseAttempt { [weak sender] in
                    sender?.close()
                }
                return false
            }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }
    }
}

#Preview {
    NavigationStack {
        SkillDetailView(skill: .previewCustom())
    }
    .environment(SettingsManager.shared)
}
