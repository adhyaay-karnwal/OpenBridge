import AppKit
import ComposerEditor
import SwiftUI

@MainActor
protocol ChatWindowFileDropControlling: AnyObject {
    var onFileDrop: ((NSPasteboard) -> Bool)? { get set }
}

@MainActor
@Observable
final class ChatWindowFileDropState {
    var isDraggingFile = false
}

@MainActor
protocol ChatWindowFileDropRouting: AnyObject {
    func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation
    func fileDragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation
    func fileDragUpdated(_ pasteboard: NSPasteboard) -> NSDragOperation
    func fileDragExited()
    func performFileDrop(_ pasteboard: NSPasteboard) -> Bool
    func concludeFileDrop()
}

struct ChatWindowFileDropBindingView: NSViewRepresentable {
    let onDrop: (NSPasteboard) -> Bool

    func makeNSView(context _: Context) -> ChatWindowFileDropBindingNSView {
        let view = ChatWindowFileDropBindingNSView()
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: ChatWindowFileDropBindingNSView, context _: Context) {
        nsView.onDrop = onDrop
        nsView.bindToWindowIfNeeded()
    }
}

@MainActor
final class ChatWindowFileDropBindingNSView: NSView {
    var onDrop: ((NSPasteboard) -> Bool)?

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bindToWindowIfNeeded()
    }

    func bindToWindowIfNeeded() {
        guard let window else { return }
        guard let chatWindow = window as? any ChatWindowFileDropControlling else { return }
        chatWindow.onFileDrop = onDrop
    }
}

@MainActor
final class ChatWindowFileDropOverlayHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
final class ChatWindowRootContainerView: NSView {
    var onDrop: ((NSPasteboard) -> Bool)?

    private var isDraggingFile = false
    private var dragStatePollTimer: Timer?
    private var overlayHideWorkItem: DispatchWorkItem?
    private let fileDropState: ChatWindowFileDropState
    private let hostedContentView: NSView
    private let overlayView = ChatWindowFileDropOverlayHostingView(rootView: ChatWindowFileDropOverlay())

    init(content: AnyView, fileDropState: ChatWindowFileDropState) {
        self.fileDropState = fileDropState
        hostedContentView = NSHostingView(rootView: AnyView(content.environment(fileDropState)))
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setupSubviews()
    }

    init(contentView: NSView, fileDropState: ChatWindowFileDropState) {
        self.fileDropState = fileDropState
        hostedContentView = contentView
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileDragEntered(sender.draggingPasteboard)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileDragUpdated(sender.draggingPasteboard)
    }

    override func draggingExited(_: NSDraggingInfo?) {
        fileDragExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragOperation(for: sender.draggingPasteboard) != []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performFileDrop(sender.draggingPasteboard)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        super.concludeDragOperation(sender)
        concludeFileDrop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            resetDragState()
        }
    }

    func resetDragState() {
        stopDragStatePolling()
        updateDragState(false)
    }

    func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
        PasteboardImporter.containsImportableContent(in: pasteboard) ? .copy : []
    }

    func fileDragEntered(_ pasteboard: NSPasteboard) -> NSDragOperation {
        let operation = dragOperation(for: pasteboard)
        guard operation != [] else { return [] }
        updateDragState(true)
        startDragStatePolling()
        return operation
    }

    func fileDragUpdated(_ pasteboard: NSPasteboard) -> NSDragOperation {
        let operation = dragOperation(for: pasteboard)
        guard operation != [] else { return [] }
        updateDragState(true)
        return operation
    }

    func fileDragExited() {
        resetDragState()
    }

    func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard dragOperation(for: pasteboard) != [] else {
            resetDragState()
            return false
        }

        defer { resetDragState() }
        return onDrop?(pasteboard) ?? false
    }

    func concludeFileDrop() {
        resetDragState()
    }

    private func setupSubviews() {
        hostedContentView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isHidden = true
        overlayView.alphaValue = 0
        addSubview(hostedContentView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            hostedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedContentView.topAnchor.constraint(equalTo: topAnchor),
            hostedContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func startDragStatePolling() {
        guard dragStatePollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(pollDragState), userInfo: nil, repeats: true)
        dragStatePollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDragStatePolling() {
        dragStatePollTimer?.invalidate()
        dragStatePollTimer = nil
    }

    @objc
    private func pollDragState() {
        guard isDraggingFile else {
            stopDragStatePolling()
            return
        }

        if NSEvent.pressedMouseButtons == 0 {
            resetDragState()
        }
    }

    private func updateDragState(_ isDragging: Bool) {
        guard isDraggingFile != isDragging else { return }
        isDraggingFile = isDragging
        fileDropState.isDraggingFile = isDragging
        updateOverlayVisibility(isDragging)
    }

    private func updateOverlayVisibility(_ isVisible: Bool) {
        overlayHideWorkItem?.cancel()
        if isVisible {
            overlayView.isHidden = false
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayView.animator().alphaValue = isVisible ? 1 : 0
        }

        if !isVisible {
            let hideWorkItem = DispatchWorkItem { [weak self] in
                guard let self, !self.isDraggingFile else { return }
                overlayView.isHidden = true
            }
            overlayHideWorkItem = hideWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: hideWorkItem)
        }
    }
}

struct ChatWindowFileDropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }

            VStack(spacing: 18) {
                Image(systemName: "document.badge.plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)

                VStack(spacing: 6) {
                    Text(String(localized: "Drop files here to add to the chat"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
