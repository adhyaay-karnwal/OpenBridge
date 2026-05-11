import AppKit
import SwiftUI

public struct AttachmentPreviewRow: View {
    let attachments: [ChatAttachment]
    let onRemove: (UUID) -> Void
    let onRetry: (ChatAttachment) -> Void

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentPreviewItem(
                        attachment: attachment,
                        onRemove: {
                            withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                                onRemove(attachment.id)
                            }
                        },
                        onRetry: { onRetry(attachment) }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0.2), value: attachments.map(\.id))
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
        }
        .frame(height: ComposerLayout.previewSize + 16)
    }
}
