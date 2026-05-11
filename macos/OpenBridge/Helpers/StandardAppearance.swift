//
//  StandardAppearance.swift
//  OpenBridge
//
//  Created on 8/1/2026.
//

import AppKit

enum StandardAppearance {
    static func createVisualEffectViewForMainBackground() -> NSView {
//        if #available(macOS 26.0, *) {
//            let glass = NSGlassEffectView()
//            glass.style = .regular
//            return glass
//        }
        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
//        effectView.alphaValue = 0.9975
        return effectView
    }
}
