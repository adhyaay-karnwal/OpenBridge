@testable import OpenBridge
import ComposerEditor
import Foundation
import Testing

@MainActor
struct AttachmentManagerTests {
    @Test
    func `file attachments carry local environment reference`() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
        try "a,b\n1,2\n".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var attachment = ChatAttachment(localURL: tempURL)
        attachment.uploadState = .uploaded(localPath: tempURL.path)

        let content = AttachmentManager.buildInputContents(text: "inspect", attachments: [attachment])
        let fileContent = try #require(content.first(where: { $0.type == "file" }))
        let fileRef = try #require(fileContent.fileRef)

        #expect(fileRef.environmentId == "Local")
        #expect(fileRef.path == tempURL.path)
    }

    @Test
    func `image attachments carry local environment reference`() throws {
        var attachment = ChatAttachment(filename: "image.png", contentType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        attachment.uploadState = .uploaded(localPath: "/tmp/image.jpg")

        let content = AttachmentManager.buildInputContents(text: nil, attachments: [attachment])
        let imageContent = try #require(content.first(where: { $0.type == "image" }))
        let fileRef = try #require(imageContent.fileRef)

        #expect(fileRef.environmentId == "Local")
        #expect(fileRef.path == "/tmp/image.jpg")
    }

    @Test
    func `quote content is inserted before outbound text`() {
        let content = AttachmentManager.buildInputContents(
            text: "Draft a follow-up",
            attachments: [],
            quote: SessionHistoryMessage.Content(
                type: "quote",
                text: "Jason tomorrow at 4 PM",
                quoteRef: .init(
                    sourceMessageId: "msg-123",
                    startOffset: 12,
                    endOffset: 33
                )
            )
        )

        #expect(content.count == 2)
        #expect(content[0].type == "quote")
        #expect(content[0].text == "Jason tomorrow at 4 PM")
        #expect(content[1].type == "text")
        #expect(content[1].text == "Draft a follow-up")
    }
}
