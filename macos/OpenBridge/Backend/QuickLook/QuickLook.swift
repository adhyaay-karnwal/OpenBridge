//
//  QuickLook.swift
//  OpenBridge
//
//  Created by CatsJuice on 2025/11/6.
//

import AppKit
import QuickLookUI
import UniformTypeIdentifiers

private struct QuickLookTransitionContext {
    let itemURL: URL
    let sourceFrameOnScreen: CGRect
    let transitionImage: QuickLookTransitionImage?
}

private struct QuickLookTransitionImage {
    let image: NSImage
    let contentRect: CGRect
}

private enum QuickLookPreheatResult {
    case completed(success: Bool)
    case timedOut
}

@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private let logger = Logger.app
    var items: [URL] = []
    private var transitionContext: QuickLookTransitionContext?
    private var showTask: Task<Void, Never>?

    override nonisolated var acceptsFirstResponder: Bool {
        true
    }

    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel?.dataSource = self
            panel?.delegate = self
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            panel?.delegate = nil
        }
    }

    // MARK: - DataSource

    func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }

    func previewPanel(_: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let transitionContext,
              previewItemURL(from: item) == transitionContext.itemURL
        else {
            return .zero
        }

        return transitionContext.sourceFrameOnScreen
    }

    func previewPanel(
        _: QLPreviewPanel!,
        transitionImageFor item: QLPreviewItem!,
        contentRect: UnsafeMutablePointer<NSRect>!
    ) -> Any! {
        guard let transitionContext,
              previewItemURL(from: item) == transitionContext.itemURL,
              let transitionImage = transitionContext.transitionImage
        else {
            return nil
        }

        contentRect?.pointee = transitionImage.contentRect
        logger.info(
            """
            Quick Look transition image: \
            url=\(transitionContext.itemURL.path(percentEncoded: false), privacy: .public) \
            imageSize=\(transitionImage.image.size.debugDescription, privacy: .public) \
            contentRect=\(transitionImage.contentRect.debugDescription, privacy: .public)
            """
        )
        return transitionImage.image
    }

    func show(
        urls: [URL],
        sourceFrameOnScreen: CGRect? = nil,
        transitionImage: NSImage? = nil
    ) {
        showTask?.cancel()

        let transitionContext = makeTransitionContext(
            urls: urls,
            sourceFrameOnScreen: sourceFrameOnScreen,
            transitionImage: transitionImage
        )

        showTask = Task { @MainActor [weak self] in
            guard let self else { return }

            items = urls
            self.transitionContext = transitionContext
            await preheatPreviewIfNeeded(
                urls: urls,
                sourceFrameOnScreen: sourceFrameOnScreen
            )

            guard !Task.isCancelled else { return }
            presentPanel()
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
        transitionContext = nil
    }
}

private extension QuickLookController {
    func presentPanel() {
        guard let panel = QLPreviewPanel.shared() else { return }
        guard let keyWindow = NSApp.keyWindow else {
            logger.error("No key window available to set as first responder. QuickLook panel may not function correctly.")
            return
        }

        keyWindow.makeFirstResponder(self)
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func makeTransitionContext(
        urls: [URL],
        sourceFrameOnScreen: CGRect?,
        transitionImage: NSImage?
    ) -> QuickLookTransitionContext? {
        guard let sourceFrameOnScreen,
              sourceFrameOnScreen.width > 0,
              sourceFrameOnScreen.height > 0,
              let itemURL = urls.first
        else {
            return nil
        }

        let preparedTransitionImage = makeTransitionImage(
            for: itemURL,
            providedImage: transitionImage,
            targetSize: sourceFrameOnScreen.size
        )
        logger.info(
            """
            Quick Look transition context: \
            url=\(itemURL.path(percentEncoded: false), privacy: .public) \
            sourceFrameOnScreen=\(sourceFrameOnScreen.debugDescription, privacy: .public) \
            transitionImageSize=\(String(describing: preparedTransitionImage?.image.size), privacy: .public) \
            transitionContentRect=\(String(describing: preparedTransitionImage?.contentRect), privacy: .public)
            """
        )

        return QuickLookTransitionContext(
            itemURL: itemURL,
            sourceFrameOnScreen: sourceFrameOnScreen,
            transitionImage: preparedTransitionImage
        )
    }

    func previewItemURL(from item: QLPreviewItem?) -> URL? {
        item?.previewItemURL as URL?
    }

    func preheatPreviewIfNeeded(
        urls: [URL],
        sourceFrameOnScreen: CGRect?
    ) async {
        guard let itemURL = urls.first else {
            return
        }

        let size = preheatSize(sourceFrameOnScreen: sourceFrameOnScreen)
        let scale = preheatScale()
        let startTime = Date()
        let result = await withTaskGroup(of: QuickLookPreheatResult.self) { group in
            group.addTask {
                let success = await QuickLookPreviewProvider.warmUp(
                    for: itemURL,
                    size: size,
                    scale: scale
                )
                return .completed(success: success)
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(120))
                return .timedOut
            }

            let result = await group.next() ?? .timedOut
            group.cancelAll()
            return result
        }
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startTime) * 1000)

        switch result {
        case let .completed(success):
            logger.info(
                """
                Quick Look preview preheat completed: \
                url=\(itemURL.path(percentEncoded: false), privacy: .public) \
                success=\(success, privacy: .public) \
                size=\(size.debugDescription, privacy: .public) \
                scale=\(scale, privacy: .public) \
                elapsedMs=\(elapsedMilliseconds, privacy: .public)
                """
            )
        case .timedOut:
            logger.info(
                """
                Quick Look preview preheat timed out: \
                url=\(itemURL.path(percentEncoded: false), privacy: .public) \
                size=\(size.debugDescription, privacy: .public) \
                scale=\(scale, privacy: .public) \
                elapsedMs=\(elapsedMilliseconds, privacy: .public)
                """
            )
        }
    }

    func makeTransitionImage(
        for url: URL,
        providedImage: NSImage?,
        targetSize: CGSize
    ) -> QuickLookTransitionImage? {
        if let providedImage {
            return QuickLookTransitionImage(
                image: providedImage,
                contentRect: CGRect(origin: .zero, size: providedImage.size)
            )
        }

        return fallbackTransitionImage(for: url, targetSize: targetSize)
    }

    func fallbackTransitionImage(for url: URL, targetSize: CGSize) -> QuickLookTransitionImage? {
        guard let contentType = UTType(filenameExtension: url.pathExtension),
              contentType.conforms(to: .image)
        else {
            return nil
        }

        guard targetSize.width > 0,
              targetSize.height > 0,
              let originalImage = NSImage(contentsOf: url)
        else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let contentRect = aspectFitRect(for: originalImage.size, inside: canvasRect)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        originalImage.draw(in: contentRect)
        image.unlockFocus()
        return QuickLookTransitionImage(image: image, contentRect: contentRect)
    }

    func aspectFitRect(for imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else {
            return bounds
        }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let scale = min(widthScale, heightScale)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: bounds.minX + (bounds.width - fittedSize.width) / 2,
            y: bounds.minY + (bounds.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func preheatSize(sourceFrameOnScreen: CGRect?) -> CGSize {
        let baseSize = sourceFrameOnScreen?.size ?? CGSize(width: 960, height: 720)
        return CGSize(
            width: min(max(baseSize.width * 2.5, 768), 1600),
            height: min(max(baseSize.height * 2.5, 768), 1600)
        )
    }

    func preheatScale() -> CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
