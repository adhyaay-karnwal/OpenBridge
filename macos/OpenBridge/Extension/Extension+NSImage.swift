//
//  Extension+NSImage.swift
//  OpenBridge
//
//  Created by qaq on 17/11/2025.
//

import AppKit

extension NSImage {
    /// Creates a tinted version of the image with the specified color
    func tinted(with color: NSColor) -> NSImage {
        guard cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
            return self
        }

        let tintedImage = NSImage(size: size)
        tintedImage.lockFocus()

        // Draw the image
        let imageRect = NSRect(origin: .zero, size: size)
        NSGraphicsContext.current?.imageInterpolation = .high

        // Draw original image
        draw(in: imageRect)

        // Apply color tint using blend mode
        color.setFill()
        imageRect.fill(using: .sourceAtop)

        tintedImage.unlockFocus()

        return tintedImage
    }
}
