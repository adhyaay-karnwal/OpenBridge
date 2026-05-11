//
//  StandaloneModeView.swift
//  ComposerEditorExample
//
//  Created by qaq on 7/1/2026.
//

import Combine
import ComposerEditor
import SwiftUI

// MARK: - Standalone Mode Demo

struct StandaloneModeView: View {
    @State private var viewModel = ComposerViewModel()
    @State private var messages: [String] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var hasSetupEvents = false
    @State private var isLoadingModels = false
    @State private var modelGroups: [ComposerModelGroup] = []
    @State private var selectedModelId: String = ""

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(
                messages: messages,
                backgroundColor: Color.blue.opacity(0.1)
            )

            Divider()

            // Composer - Standalone mode
            ComposerView(
                viewModel: viewModel,
                accentColor: .blue,
                accentForegroundColor: .white,
                placeholder: "Type a message...",
                appearance: .standalone,
                modelSelector: modelSelectorConfig
            )
            .padding()
        }
        .onAppear {
            if !hasSetupEvents {
                setupEvents()
                hasSetupEvents = true
            }
        }
    }

    private func setupEvents() {
        viewModel.eventPublisher
            .sink { event in
                switch event {
                case let .submitted(submission):
                    handleSubmit(submission)

                case let .attachmentUploadStarted(id):
                    simulateUpload(id: id)

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func simulateUpload(id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                viewModel.updateAttachmentState(
                    id: id,
                    state: .uploaded(
                        localPath: "/tmp/mock/\(id).png",
                        publicURL: "mock://uploaded/\(id).png"
                    )
                )
            }
        }
    }

    private func handleSubmit(_ submission: ComposerEvent.Submission) {
        var text = submission.text ?? ""

        if !submission.attachments.isEmpty {
            let files = submission.attachments.map { "[\($0.filename)]" }.joined(separator: " ")
            text = text.isEmpty ? files : "\(text) \(files)"
        }

        messages.append(text)
        viewModel.text = ""
        viewModel.clearAttachments()
    }

    private var selectedModelTitle: String {
        if selectedModelId.isEmpty { return "Select model" }
        for group in modelGroups {
            if let match = group.models.first(where: { $0.id == selectedModelId }) {
                return match.title
            }
        }
        return selectedModelId
    }

    private var modelSelectorConfig: ComposerModelSelectorConfig {
        ComposerModelSelectorConfig(
            groups: modelGroups,
            isLoading: isLoadingModels,
            selectedModelId: $selectedModelId,
            selectedModelTitle: selectedModelTitle,
            onOpen: { loadModelsIfNeeded() },
            onSelect: { selectedModelId = $0 }
        )
    }

    private func loadModelsIfNeeded() {
        guard modelGroups.isEmpty, !isLoadingModels else { return }
        isLoadingModels = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            await MainActor.run {
                // Self-contained demo data
                modelGroups = [
                    ComposerModelGroup(
                        provider: "openai",
                        models: [
                            ComposerModelOption(id: "gpt-5.2", title: "GPT-5.2"),
                            ComposerModelOption(id: "gpt-5.1", title: "GPT-5.1"),
                        ]
                    ),
                    ComposerModelGroup(
                        provider: "anthropic",
                        models: [
                            ComposerModelOption(id: "claude-opus", title: "Claude Opus"),
                            ComposerModelOption(id: "claude-sonnet", title: "Claude Sonnet"),
                        ]
                    ),
                ]
                if selectedModelId.isEmpty, let first = modelGroups.first?.models.first {
                    selectedModelId = first.id
                }
                isLoadingModels = false
            }
        }
    }
}

#Preview("Standalone Tab") {
    StandaloneModeView()
        .frame(width: 700, height: 500)
}
