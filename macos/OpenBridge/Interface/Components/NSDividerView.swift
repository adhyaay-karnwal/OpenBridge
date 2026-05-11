//
//  NSDividerView.swift
//  OpenBridge
//
//  Created by qaq on 4/12/2025.
//

import AppKit

class NSDividerView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    func updateColor() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }
}
