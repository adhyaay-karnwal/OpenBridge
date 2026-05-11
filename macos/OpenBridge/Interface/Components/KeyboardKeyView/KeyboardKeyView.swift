//
//  KeyboardKeyView.swift
//  OpenBridge
//
//  Created by qaq on 19/12/2025.
//

import AppKit

final class KeyboardKeyView: NSView {
    enum Variant { case symbol, text }

    let containerView = NSView(frame: .zero)
    var modifierImageViews: [NSImageView] = []
    var keyView: NSView?

    var variant: Variant = .symbol {
        didSet {
            updateAppearance()
            invalidateIntrinsicContentSize()
        }
    }

    var shortcut: KeyboardShortcutDisplay? {
        didSet {
            rebuildViews()
            invalidateIntrinsicContentSize()
        }
    }

    let size: CGFloat = 20
    let textVariantWidth: CGFloat = 56

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        addSubview(containerView)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        switch variant {
        case .symbol: NSSize(width: size, height: size)
        case .text: NSSize(width: textVariantWidth, height: size)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.2).cgColor
    }
}
