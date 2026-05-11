//
//  FileAttachmentSheet.swift
//  ComposerEditorExample
//
//  Created by qaq on 7/1/2026.
//

import ComposerEditor
import SwiftUI

/// Sheet for handling file attachments in compact mode
/// This simulates opening a separate window to fill in file details
struct FileAttachmentSheet: View {
    let urls: [URL]
    let onConfirm: ([ChatAttachment]) -> Void
    let onCancel: () -> Void

    @State private var attachments: [ChatAttachment] = []
    @State private var customText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Files")
                .font(.title2)
                .bold()

            if !urls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Files to attach:")
                        .font(.headline)

                    ForEach(urls, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.blue)
                            Text(url.lastPathComponent)
                                .font(.body)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Optional message:")
                    .font(.headline)

                TextEditor(text: $customText)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Confirm") {
                    // Create attachments from URLs
                    let newAttachments = urls.map { ChatAttachment(localURL: $0) }
                    onConfirm(newAttachments)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

#Preview {
    FileAttachmentSheet(
        urls: [
            URL(fileURLWithPath: "/tmp/test.txt"),
            URL(fileURLWithPath: "/tmp/image.png"),
        ],
        onConfirm: { _ in },
        onCancel: {}
    )
}
