import AppKit
import ComposerEditor
import SwiftUI

extension ChatEditorViewModel {
    @discardableResult
    func handleFileDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard let content = PasteboardImporter.extractContent(from: pasteboard) else { return false }

        switch content {
        case let .fileURLs(urls):
            withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                addFileURLs(urls, source: .drop)
            }
            return true
        case let .imageData(data, format):
            let attachment = ChatAttachment(
                filename: "dropped-image-\(UUID().uuidString).\(format)",
                contentType: "image/\(format)",
                data: data
            )
            withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                addAttachment(attachment, source: .drop)
            }
            return true
        }
    }
}
