//
//  Extension+NSEdgeInset.swift
//  OpenBridge
//
//  Created by qaq on 13/11/2025.
//

import AppKit

extension NSEdgeInsets {
    static let zero = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    func isEqualTo(_ other: NSEdgeInsets) -> Bool {
        top == other.top &&
            left == other.left &&
            bottom == other.bottom &&
            right == other.right
    }
}
