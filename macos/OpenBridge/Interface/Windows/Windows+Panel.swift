import AppKit
import SwiftUI

@MainActor
protocol ChatSurfaceCloseControlling: AnyObject {
    func closeWithoutReset()
}

extension Windows {
    @MainActor
    final class Panel<Content: View>: NSExtendablePanel {
        private var stateController: WindowStateController?

        init(
            preferredContentSize: NSSize,
            identifier: String,
            styleMask: NSWindow.StyleMask,
            level: NSWindow.Level,
            collectionBehavior: NSWindow.CollectionBehavior,
            content: @escaping () -> Content
        ) {
            super.init(
                contentRect: NSRect(origin: .zero, size: preferredContentSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )

            configurePanel(identifier: identifier, level: level, collectionBehavior: collectionBehavior)

            let controller = NSHostingController(
                rootView: AnyView(
                    PanelLocalizedRoot {
                        content()
                            .ignoresSafeArea()
                    }
                    .environment(SettingsManager.shared)
                )
            )
            controller.view.frame = .init(origin: .zero, size: preferredContentSize)
            contentViewController = controller
            contentView = controller.view

            stateController = makeStateController(
                for: self,
                preferredContentSize: preferredContentSize,
                styleMask: styleMask
            )
        }

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            true
        }
    }

    @MainActor
    final class ChatWindow<Content: View>: NSWindow, ChatWindowFileDropControlling, ChatWindowFileDropRouting, ChatSurfaceCloseControlling {
        private var stateController: WindowStateController?
        private var suppressResetOnClose = false
        var onFileDrop: ((NSPasteboard) -> Bool)? {
            didSet {
                rootContentView.onDrop = onFileDrop
            }
        }

        private let fileDropState = ChatWindowFileDropState()
        private let rootContentView: ChatWindowRootContainerView

        init(
            preferredContentSize: NSSize,
            identifier: String,
            styleMask: NSWindow.StyleMask,
            level: NSWindow.Level,
            collectionBehavior: NSWindow.CollectionBehavior,
            content: @escaping () -> Content
        ) {
            rootContentView = ChatWindowRootContainerView(
                content: AnyView(
                    PanelLocalizedRoot {
                        content()
                            .injectGlassMaterialMode()
                            .ignoresSafeArea()
                    }
                    .environment(SettingsManager.shared)
                ),
                fileDropState: fileDropState
            )
            super.init(
                contentRect: NSRect(origin: .zero, size: preferredContentSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )

            configureChatWindow(identifier: identifier, level: level, collectionBehavior: collectionBehavior)

            rootContentView.frame = .init(origin: .zero, size: preferredContentSize)
            rootContentView.autoresizingMask = [.width, .height]
            contentView = rootContentView

            stateController = WindowStateController(
                window: self,
                preferredContentSize: preferredContentSize
            )
        }

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            true
        }

        override func performClose(_ sender: Any?) {
            guard !Windows.shared.handleChatPerformCloseRequest(from: self) else { return }
            super.performClose(sender)
        }

        override func close() {
            rootContentView.resetDragState()
            let shouldResetSurface = !suppressResetOnClose
            suppressResetOnClose = false
            super.close()

            if shouldResetSurface {
                ChatSurfaceModel.shared.resetForClose()
            }
        }

        func closeWithoutReset() {
            suppressResetOnClose = true
            close()
        }

        func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView.dragOperation(for: pasteboard)
        }

        func fileDragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView.fileDragEntered(pasteboard)
        }

        func fileDragUpdated(_ pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView.fileDragUpdated(pasteboard)
        }

        func fileDragExited() {
            rootContentView.fileDragExited()
        }

        func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
            rootContentView.performFileDrop(pasteboard)
        }

        func concludeFileDrop() {
            rootContentView.concludeFileDrop()
        }

        @MainActor
        deinit {}
    }

    @MainActor
    final class ChatMainWindow<Content: View>: NSWindow, ChatWindowFileDropControlling, ChatWindowFileDropRouting, ChatSurfaceCloseControlling {
        private var stateController: WindowStateController?
        private var suppressResetOnClose = false
        var onFileDrop: ((NSPasteboard) -> Bool)? {
            didSet {
                contentController.onDrop = onFileDrop
            }
        }

        private let fileDropState = ChatWindowFileDropState()
        private let contentController: ChatMainWindowContentController

        init(
            preferredContentSize: NSSize,
            identifier: String,
            styleMask: NSWindow.StyleMask,
            level: NSWindow.Level,
            collectionBehavior: NSWindow.CollectionBehavior,
            content: @escaping () -> Content
        ) {
            contentController = ChatMainWindowContentController(
                fileDropState: fileDropState,
                content: content
            )
            super.init(
                contentRect: NSRect(origin: .zero, size: preferredContentSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )

            configureMainChatWindow(
                identifier: identifier,
                level: level,
                collectionBehavior: collectionBehavior
            )
            configureStandardCloseButton()

            contentController.view.frame = .init(origin: .zero, size: preferredContentSize)
            contentViewController = contentController
            contentView = contentController.view

            stateController = WindowStateController(
                window: self,
                preferredContentSize: preferredContentSize
            )
        }

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            true
        }

        override func performClose(_ sender: Any?) {
            guard !Windows.shared.handleChatPerformCloseRequest(from: self) else { return }
            super.performClose(sender)
        }

        @objc
        private func handleStandardCloseButton(_ sender: Any?) {
            guard !Windows.shared.handleChatPerformCloseRequest(from: self) else { return }
            super.performClose(sender)
        }

        private func configureStandardCloseButton() {
            guard let closeButton = standardWindowButton(.closeButton) else { return }
            closeButton.target = self
            closeButton.action = #selector(handleStandardCloseButton(_:))
        }

        override func close() {
            contentController.resetDragState()
            let shouldResetSurface = !suppressResetOnClose
            suppressResetOnClose = false
            super.close()

            if shouldResetSurface {
                ChatSurfaceModel.shared.resetForClose()
            }
        }

        func closeWithoutReset() {
            suppressResetOnClose = true
            close()
        }

        func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
            contentController.dragOperation(for: pasteboard)
        }

        func fileDragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation {
            contentController.fileDragEntered(pasteboard)
        }

        func fileDragUpdated(_ pasteboard: NSPasteboard) -> NSDragOperation {
            contentController.fileDragUpdated(pasteboard)
        }

        func fileDragExited() {
            contentController.fileDragExited()
        }

        func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
            contentController.performFileDrop(pasteboard)
        }

        func concludeFileDrop() {
            contentController.concludeFileDrop()
        }

        @MainActor
        deinit {}
    }

    @MainActor
    final class ChatMainWindowContentController: NSHostingController<AnyView> {
        private let fileDropState: ChatWindowFileDropState
        private var rootContentView: ChatWindowRootContainerView?

        var onDrop: ((NSPasteboard) -> Bool)? {
            didSet {
                rootContentView?.onDrop = onDrop
            }
        }

        init(fileDropState: ChatWindowFileDropState, content: @escaping () -> some View) {
            self.fileDropState = fileDropState
            super.init(
                rootView: AnyView(
                    PanelLocalizedRoot {
                        content()
                            .environment(fileDropState)
                    }
                    .environment(SettingsManager.shared)
                )
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            super.loadView()

            let hostedView = view
            let rootContentView = ChatWindowRootContainerView(
                contentView: hostedView,
                fileDropState: fileDropState
            )
            rootContentView.onDrop = onDrop
            view = rootContentView
            self.rootContentView = rootContentView
        }

        func resetDragState() {
            rootContentView?.resetDragState()
        }

        func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView?.dragOperation(for: pasteboard) ?? []
        }

        func fileDragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView?.fileDragEntered(pasteboard) ?? []
        }

        func fileDragUpdated(_ pasteboard: NSPasteboard) -> NSDragOperation {
            rootContentView?.fileDragUpdated(pasteboard) ?? []
        }

        func fileDragExited() {
            rootContentView?.fileDragExited()
        }

        func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
            rootContentView?.performFileDrop(pasteboard) ?? false
        }

        func concludeFileDrop() {
            rootContentView?.concludeFileDrop()
        }
    }

    @MainActor
    final class ControllerPanel: NSExtendablePanel {
        private var stateController: WindowStateController?

        init(
            preferredContentSize: NSSize,
            identifier: String,
            styleMask: NSWindow.StyleMask,
            level: NSWindow.Level,
            collectionBehavior: NSWindow.CollectionBehavior,
            viewController: NSViewController
        ) {
            super.init(
                contentRect: NSRect(origin: .zero, size: preferredContentSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )

            configurePanel(identifier: identifier, level: level, collectionBehavior: collectionBehavior)

            viewController.view.frame = .init(origin: .zero, size: preferredContentSize)
            contentViewController = viewController
            contentView = viewController.view

            stateController = makeStateController(
                for: self,
                preferredContentSize: preferredContentSize,
                styleMask: styleMask
            )
        }

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            true
        }

        @MainActor
        deinit {}
    }
}

private func makeStateController(
    for window: NSExtendablePanel,
    preferredContentSize: NSSize,
    styleMask: NSWindow.StyleMask
) -> WindowStateController {
    let controller = WindowStateController(window: window, preferredContentSize: preferredContentSize)
    if !styleMask.contains(.resizable) {
        controller.resetWindowFrameToPreferredContentSize()
    }
    return controller
}

private extension NSExtendablePanel {
    func configurePanel(
        identifier: String,
        level: NSWindow.Level,
        collectionBehavior: NSWindow.CollectionBehavior
    ) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.level = level
        self.collectionBehavior = collectionBehavior

        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = true
        worksWhenModal = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}

private extension NSWindow {
    func configureChatWindow(
        identifier: String,
        level: NSWindow.Level,
        collectionBehavior: NSWindow.CollectionBehavior
    ) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.level = level
        self.collectionBehavior = collectionBehavior

        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .default
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // 保持无交通灯的自定义外观
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    func configureMainChatWindow(
        identifier: String,
        level: NSWindow.Level,
        collectionBehavior: NSWindow.CollectionBehavior
    ) {
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.level = level
        self.collectionBehavior = collectionBehavior

        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        animationBehavior = .default
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = true
        toolbarStyle = .unified
        titlebarSeparatorStyle = .automatic
        title = String(localized: "Chat")

        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false
    }
}

private struct PanelLocalizedRoot<Content: View>: View {
    @Environment(SettingsManager.self) private var settings
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: settings.language))
    }
}
