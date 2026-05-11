//
//  NSExtendablePanel.swift
//  OpenBridge
//
//  Created by qaq on 4/12/2025.
//

import AppKit

@MainActor
class NSExtendablePanel: NSPanel {
    private var _extendedEdgesInset: NSEdgeInsets = .zero
    private var _extendedContentView: NSView?
    private var _contentViewContainer: NSView?
    private var _baseContentSize: NSSize = .zero
    private var _isInternalFrameUpdate: Bool = false

    var extendedEdgesInset: NSEdgeInsets {
        get { _extendedEdgesInset }
        set {
            guard !_extendedEdgesInset.isEqualTo(newValue) else { return }
            let oldInset = _extendedEdgesInset
            _extendedEdgesInset = newValue
            updateExtendedFrame(previousInset: oldInset)
        }
    }

    var extendedContentView: NSView {
        if let existing = _extendedContentView {
            return existing
        }
        let view = NSView()
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        _extendedContentView = view
        return view
    }

    override var contentView: NSView? {
        get {
            _contentViewContainer?.subviews.first
        }
        set {
            setupContentViewHierarchy(newContentView: newValue)
        }
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        _baseContentSize = contentRect.size
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setupExtendedContentView()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if _isInternalFrameUpdate {
            // Internal update: proceed normally
            super.setFrame(frameRect, display: flag)
            updateContentViewFrames()
        } else {
            // External update (user resize): handle based on extendedEdgesInset
            if _extendedEdgesInset.isEqualTo(.zero) {
                // No extended edges: allow normal resize
                _baseContentSize = frameRect.size
                super.setFrame(frameRect, display: flag)
                updateContentViewFrames()
            } else {
                // Has extended edges: prevent external size mutation.
                // External callers must use setExtendedFrame/setBaseContentFrame.
                // Still allow pure moves (origin changes) so panels can be positioned.
                if frameRect.size != frame.size {
                    return
                }
                super.setFrame(frameRect, display: flag)
                updateContentViewFrames()
            }
        }
    }

    override func setContentSize(_ size: NSSize) {
        _baseContentSize = size
        updateExtendedFrame(previousInset: _extendedEdgesInset)
    }

    var baseContentFrame: NSRect {
        let extendedFrame = frame
        return NSRect(
            origin: NSPoint(
                x: extendedFrame.origin.x + _extendedEdgesInset.left,
                y: extendedFrame.origin.y + _extendedEdgesInset.bottom
            ),
            size: _baseContentSize
        )
    }

    func setBaseContentFrame(_ frame: NSRect) {
        _baseContentSize = frame.size
        let extendedFrame = NSRect(
            origin: NSPoint(
                x: frame.origin.x - _extendedEdgesInset.left,
                y: frame.origin.y - _extendedEdgesInset.bottom
            ),
            size: NSSize(
                width: frame.size.width + _extendedEdgesInset.left + _extendedEdgesInset.right,
                height: frame.size.height + _extendedEdgesInset.top + _extendedEdgesInset.bottom
            )
        )
        _isInternalFrameUpdate = true
        super.setFrame(extendedFrame, display: true)
        _isInternalFrameUpdate = false
        updateContentViewFrames()
    }

    func setExtendedFrame(_ frame: NSRect, display flag: Bool = true) {
        _baseContentSize = NSSize(
            width: frame.size.width - _extendedEdgesInset.left - _extendedEdgesInset.right,
            height: frame.size.height - _extendedEdgesInset.top - _extendedEdgesInset.bottom
        )
        _isInternalFrameUpdate = true
        super.setFrame(frame, display: flag)
        _isInternalFrameUpdate = false
        updateContentViewFrames()
    }

    private func setupExtendedContentView() {
        let extendedView = extendedContentView
        extendedView.frame = NSRect(origin: .zero, size: frame.size)
        super.contentView = extendedView
        updateContentViewFrames()
    }

    private func setupContentViewHierarchy(newContentView: NSView?) {
        guard let extendedView = _extendedContentView else {
            super.contentView = newContentView
            return
        }

        if let oldContainer = _contentViewContainer {
            oldContainer.removeFromSuperview()
        }

        guard let newContentView else {
            return
        }

        let container = NSView()
        container.wantsLayer = true
        container.autoresizingMask = []
        _contentViewContainer = container
        extendedView.addSubview(container)
        container.addSubview(newContentView)
        newContentView.autoresizingMask = [.width, .height]
        newContentView.frame = container.bounds

        updateContentViewFrames()
    }

    private func updateExtendedFrame(previousInset: NSEdgeInsets) {
        let currentFrame = frame

        let newContentSize = _baseContentSize
        let newExtendedSize = NSSize(
            width: newContentSize.width + _extendedEdgesInset.left + _extendedEdgesInset.right,
            height: newContentSize.height + _extendedEdgesInset.top + _extendedEdgesInset.bottom
        )

        let insetDeltaLeft = _extendedEdgesInset.left - previousInset.left
        let insetDeltaBottom = _extendedEdgesInset.bottom - previousInset.bottom

        let newFrame = NSRect(
            origin: NSPoint(
                x: currentFrame.origin.x - insetDeltaLeft,
                y: currentFrame.origin.y - insetDeltaBottom
            ),
            size: newExtendedSize
        )

        _isInternalFrameUpdate = true
        super.setFrame(newFrame, display: true)
        _isInternalFrameUpdate = false
        updateContentViewFrames()
    }

    private func updateContentViewFrames() {
        guard let extendedView = _extendedContentView else { return }

        extendedView.frame = NSRect(origin: .zero, size: frame.size)

        if let container = _contentViewContainer {
            let contentFrame = NSRect(
                x: _extendedEdgesInset.left,
                y: _extendedEdgesInset.bottom,
                width: _baseContentSize.width,
                height: _baseContentSize.height
            )
            container.frame = contentFrame
        }
    }
}
