//
//  KeyboardKeyView+Layout.swift
//  OpenBridge
//
//  Created by qaq on 19/12/2025.
//

import AppKit

extension KeyboardKeyView {
    override func layout() {
        super.layout()
        switch variant {
        case .symbol: layoutSymbolVariant()
        case .text: layoutTextVariant()
        }
    }

    func layoutSymbolVariant() {
        let validWidth = bounds.width.isFinite && bounds.width > 0 ? bounds.width : size
        let validHeight = bounds.height.isFinite && bounds.height > 0 ? bounds.height : size
        let squareSize = min(validWidth, validHeight)
        guard squareSize > 0 else { return }

        let squareFrame = NSRect(
            x: (validWidth - squareSize) / 2,
            y: (validHeight - squareSize) / 2,
            width: squareSize,
            height: squareSize
        )
        let insetFrame = squareFrame.insetBy(dx: 4, dy: 4)
        guard insetFrame.width > 0, insetFrame.height > 0 else { return }

        containerView.frame = insetFrame
        layoutSymbolContent()
    }

    func layoutSymbolContent() {
        let containerBounds = containerView.bounds
        guard !containerBounds.isEmpty else { return }

        let contentSize = min(containerBounds.width, containerBounds.height)
        let centerX = containerBounds.midX
        let centerY = containerBounds.midY

        // Layout modifiers
        if !modifierImageViews.isEmpty {
            let modifierSize = contentSize * 0.4
            let modifierSpacing: CGFloat = 1
            let totalWidth = CGFloat(modifierImageViews.count) * modifierSize +
                CGFloat(modifierImageViews.count - 1) * modifierSpacing
            var currentX = centerX - totalWidth / 2

            for imageView in modifierImageViews {
                imageView.frame = NSRect(
                    x: currentX,
                    y: containerBounds.maxY - modifierSize - 1,
                    width: modifierSize,
                    height: modifierSize
                )
                currentX += modifierSize + modifierSpacing
            }
        }

        // Layout key view
        if let keyView {
            let hasModifiers = !modifierImageViews.isEmpty
            let keySize = contentSize * (hasModifiers ? 0.5 : 0.7)
            let keyY = hasModifiers ? centerY - keySize * 0.3 : centerY
            keyView.frame = NSRect(
                x: centerX - keySize / 2,
                y: keyY - keySize / 2,
                width: keySize,
                height: keySize
            )
        }
    }

    func layoutTextVariant() {
        let padding: CGFloat = 4
        guard bounds.width > padding else {
            containerView.frame = .zero
            return
        }
        containerView.frame = bounds.insetBy(dx: padding, dy: 0)
        if let label = keyView as? NSTextField {
            let h = label.intrinsicContentSize.height
            label.frame = NSRect(x: 0, y: (containerView.bounds.height - h) / 2, width: containerView.bounds.width, height: h)
        }
    }

    func rebuildViews() {
        modifierImageViews.forEach { $0.removeFromSuperview() }
        modifierImageViews.removeAll()
        keyView?.removeFromSuperview()
        keyView = nil

        guard let shortcut else { return }

        // Modifiers
        for modifier in shortcut.modifiers {
            let imageView = NSImageView(frame: .zero)
            imageView.image = NSImage(systemSymbolName: modifier.symbolName, accessibilityDescription: nil)
            imageView.image?.isTemplate = true
            imageView.contentTintColor = .secondaryLabelColor
            imageView.imageScaling = .scaleProportionallyDown
            containerView.addSubview(imageView)
            modifierImageViews.append(imageView)
        }

        // Key
        switch variant {
        case .symbol:
            if shortcut.key.isSymbol {
                let imageView = NSImageView(frame: .zero)
                imageView.image = NSImage(systemSymbolName: shortcut.key.displayValue, accessibilityDescription: nil)
                imageView.image?.isTemplate = true
                imageView.contentTintColor = .secondaryLabelColor
                imageView.imageScaling = .scaleProportionallyDown
                containerView.addSubview(imageView)
                keyView = imageView
            } else {
                let label = NSTextField(labelWithString: shortcut.key.displayValue)
                label.backgroundColor = .clear
                label.alignment = .center
                label.font = .systemFont(ofSize: 9, weight: .medium)
                label.textColor = .secondaryLabelColor
                containerView.addSubview(label)
                keyView = label
            }
        case .text:
            let label = NSTextField(labelWithString: shortcut.key.displayValue)
            label.backgroundColor = .clear
            label.alignment = .center
            label.font = .systemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            containerView.addSubview(label)
            keyView = label
        }

        needsLayout = true
    }
}
