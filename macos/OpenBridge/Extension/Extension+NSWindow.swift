//
//  Extension+NSWindow.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit

extension NSWindow {
    func focus() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func moveToCenter(of screen: NSScreen) {
        guard screen != self.screen else { return }

        let visibleFrame = screen.visibleFrame
        var frame = frame

        frame.size.width = min(frame.width, visibleFrame.width)
        frame.size.height = min(frame.height, visibleFrame.height)
        frame.origin.x = visibleFrame.midX - frame.size.width / 2
        frame.origin.y = visibleFrame.midY - frame.size.height / 2

        setFrame(frame, display: false)
    }
}
