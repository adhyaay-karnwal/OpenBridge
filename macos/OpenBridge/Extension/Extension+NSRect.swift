//
//  Extension+NSRect.swift
//  OpenBridge
//
//  Created by qaq on 13/11/2025.
//

import AppKit

extension NSRect {
    func inset(by insets: NSEdgeInsets) -> NSRect {
        NSRect(
            x: origin.x + insets.left,
            y: origin.y + insets.bottom,
            width: width - insets.left - insets.right,
            height: height - insets.top - insets.bottom
        )
    }

    var componentsAreFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
