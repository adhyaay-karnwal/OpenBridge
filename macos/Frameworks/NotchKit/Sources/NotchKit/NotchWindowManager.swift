import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    private var window: NotchWindow?
    private var hostingView: NotchPassthroughHostingView<NotchRootView>?

    func syncWindow(with model: NotchRuntimeModel) {
        guard model.overlayWindowFrame != .zero else { return }

        if window == nil || window?.screen?.notchDisplayID != model.selectedDisplayID {
            recreateWindow(with: model)
        }

        guard let window, let hostingView else { return }

        window.setFrame(model.overlayWindowFrame, display: false)
        hostingView.frame = .init(origin: .zero, size: model.overlayWindowFrame.size)
        hostingView.interactivePointProvider = { [weak model] point in
            model?.containsInteractivePoint(point) == true
        }

        if model.windowShouldBeVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func close() {
        window?.close()
        hostingView = nil
        window = nil
    }

    private func recreateWindow(with model: NotchRuntimeModel) {
        close()

        let window = NotchWindow(
            contentRect: model.overlayWindowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let hostingView = NotchPassthroughHostingView(
            rootView: NotchRootView(model: model)
        )
        hostingView.frame = .init(origin: .zero, size: model.overlayWindowFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.interactivePointProvider = { [weak model] point in
            model?.containsInteractivePoint(point) == true
        }

        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView
    }
}

private final class NotchPassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactivePointProvider: ((NSPoint) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: point)
        guard interactivePointProvider?(screenPoint) == true else { return nil }
        return super.hitTest(point) ?? self
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
