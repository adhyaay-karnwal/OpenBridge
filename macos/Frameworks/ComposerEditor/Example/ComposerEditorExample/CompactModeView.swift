//
//  CompactModeView.swift
//  ComposerEditorExample
//
//  Created by qaq on 7/1/2026.
//

import Combine
import ComposerEditor
import SwiftUI

// MARK: - Compact Mode Demo

struct CompactModeView: View {
    @State private var viewModel = ComposerViewModel(compactMode: true)
    @State private var messages: [String] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var hasSetupEvents = false
    @State private var showFilePickerWindow = false
    @State private var pendingFileURLs: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(
                messages: messages,
                backgroundColor: Color.green.opacity(0.1)
            )

            Divider()

            // Compact Composer - centered, fixed height
            HStack {
                Spacer()
                ComposerView(
                    viewModel: viewModel,
                    accentColor: .green,
                    placeholder: "Type a message...",
                    appearance: .compact
                )
                .frame(maxWidth: 600)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showFilePickerWindow) {
            FileAttachmentSheet(
                urls: pendingFileURLs,
                onConfirm: { attachments in
                    // User confirmed from external window, inject attachments
                    viewModel.setAttachments(attachments)
                    showFilePickerWindow = false
                    pendingFileURLs = []
                },
                onCancel: {
                    showFilePickerWindow = false
                    pendingFileURLs = []
                }
            )
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

                case let .fileDropRequested(urls):
                    // User dropped files in compact mode - open file picker window
                    pendingFileURLs = urls
                    showFilePickerWindow = true

                case .fileAttachRequested:
                    // User clicked attach button in compact mode - open file picker window
                    showFilePickerWindow = true

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
}

#Preview("Compact Tab") {
    CompactModeView()
        .frame(width: 700, height: 500)
}
