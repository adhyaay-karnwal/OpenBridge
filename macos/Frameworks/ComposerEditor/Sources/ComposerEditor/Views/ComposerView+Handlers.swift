import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ComposerView {
    func handlePaste(_ pasteboard: NSPasteboard) -> Bool {
        if let content = PasteboardImporter.extractContent(from: pasteboard) {
            switch content {
            case let .fileURLs(urls):
                return addFileURLsFromExternalSource(urls, source: .paste)
            case let .imageData(data, format):
                addImageAttachment(data: data, format: format, source: .paste)
                return true
            }
        }

        if let text = pasteboard.string(forType: .string),
           text.count > 500_000 || text.components(separatedBy: .newlines).count > 10000
        {
            saveLargeTextAsFile(text)
            return true
        }

        return false
    }

    func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                Task {
                    guard let data = try? await loadData(from: provider, typeIdentifier: UTType.image.identifier) else { return }
                    addImageAttachment(data: data, format: "png", source: .drop)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier) {
                Task {
                    guard let url = try? await loadFileURL(from: provider, typeIdentifier: UTType.folder.identifier) else { return }
                    addFileURLsFromExternalSource([url], source: .drop)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                Task {
                    guard let url = try? await loadFileURL(from: provider, typeIdentifier: UTType.fileURL.identifier) else { return }
                    addFileURLsFromExternalSource([url], source: .drop)
                }
            }
        }
    }

    @discardableResult
    private func addFileURLsFromExternalSource(_ urls: [URL], source: AttachmentSource) -> Bool {
        if let onFileURLsAdded, onFileURLsAdded(urls, source) {
            return true
        }
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
            viewModel.addFileURLs(urls, source: source)
        }
        return true
    }

    func addImageAttachment(data: Data, format: String, source: AttachmentSource) {
        let filenamePrefix = switch source {
        case .paste: "pasted-image"
        case .drop: "dropped-image"
        case .menu: "image"
        }
        let attachment = ChatAttachment(
            filename: "\(filenamePrefix)-\(UUID().uuidString).\(format)",
            contentType: "image/\(format)",
            data: data
        )
        if let onAttachmentAdded, onAttachmentAdded(attachment, source) {
            return
        }
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
            viewModel.addAttachment(attachment, source: source)
        }
    }

    func saveLargeTextAsFile(_ text: String) {
        let filename = "pasted-text-\(UUID().uuidString).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard let data = text.data(using: .utf8) else { return }
        try? data.write(to: tempURL)
        addFileURLsFromExternalSource([tempURL], source: .paste)
    }

    func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "ComposerEditor", code: -1))
                }
            }
        }
    }

    func loadFileURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
