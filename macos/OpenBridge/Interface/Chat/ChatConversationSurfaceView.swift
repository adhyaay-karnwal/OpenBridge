import AppKit
import SwiftUI
import WindowNotificationKit

struct ChatConversationSurfaceView: View {
    @Environment(ChatWindowFileDropState.self) private var fileDropState

    let surfaceModel: ChatSurfaceModel
    let messagesBridge: MessagesBridge
    let chatPresentationMode: ChatPresentationMode
    let messagePaddingTop: CGFloat
    let onFileDrop: (NSPasteboard) -> Bool
    var showsFileDropOverlay = false

    private let fileDropAnimation = Animation.easeInOut(duration: 0.18)

    private var notificationConfiguration: WindowNotificationStackConfiguration {
        var configuration = WindowNotificationStackConfiguration.sonner
        configuration.expansionBehavior = .collapsed
        configuration.expandsOnHover = false
        configuration.maximumWidth = 640
        configuration.maximumCollapsedCards = 1
        configuration.maximumExpandedCards = 1
        configuration.allowsExpandedScrolling = false
        configuration.overlayInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.offset = CGSize(width: 0, height: messagePaddingTop + 8)
        return configuration
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MessageView(
                    editorViewModel: surfaceModel.editorViewModel,
                    messagesBridge: messagesBridge,
                    chatPresentationMode: chatPresentationMode,
                    paddingTop: messagePaddingTop
                )

                ChatWindowComposerSection(
                    editorViewModel: surfaceModel.editorViewModel,
                    scheduleStore: surfaceModel.scheduleStore,
                    chatPresentationMode: chatPresentationMode
                )
            }
            .windowNotificationHost(
                center: ChatWindowNotificationController.shared.center,
                configuration: notificationConfiguration
            )
            .compositingGroup()
            .blur(radius: fileDropState.isDraggingFile ? 10 : 0, opaque: false)
            .animation(fileDropAnimation, value: fileDropState.isDraggingFile)

            ChatWindowFileDropBindingView(onDrop: onFileDrop)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if showsFileDropOverlay, fileDropState.isDraggingFile {
                ChatWindowFileDropOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: fileDropState.isDraggingFile, initial: true) { _, isDragging in
            withAnimation(fileDropAnimation) {
                surfaceModel.editorViewModel.isDraggingFile = isDragging
            }
        }
        .windowNotificationCenter(ChatWindowNotificationController.shared.center)
        .animation(fileDropAnimation, value: fileDropState.isDraggingFile)
    }
}
