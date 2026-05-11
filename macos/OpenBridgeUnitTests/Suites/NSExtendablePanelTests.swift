//
//  NSExtendablePanelTests.swift
//  OpenBridgeUnitTests
//
//  Created by qaq on 6/12/2025.
//

import AppKit
@testable import OpenBridge
import Testing

@MainActor
struct NSExtendablePanelTests {
    private final class TestPanel: NSExtendablePanel {
        var recordedFrames: [NSRect] = []

        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            recordedFrames.append(frameRect)
            super.setFrame(frameRect, display: flag)
        }
    }

    @Test
    func `base content frame round trip with insets`() {
        let panel = TestPanel(
            contentRect: NSRect(origin: .init(x: 50, y: 80), size: .init(width: 200, height: 120)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.extendedEdgesInset = NSEdgeInsets(top: 12, left: 8, bottom: 10, right: 6)

        let baseFrame = NSRect(origin: .init(x: 100, y: 200), size: .init(width: 320, height: 180))
        panel.setBaseContentFrame(baseFrame)

        #expect(panel.baseContentFrame == baseFrame)
        let expectedExtended = NSRect(
            origin: .init(x: baseFrame.origin.x - 8, y: baseFrame.origin.y - 10),
            size: .init(width: 320 + 8 + 6, height: 180 + 12 + 10)
        )
        #expect(panel.frame == expectedExtended)
    }

    @Test
    func `set frame guard prevents external mutation`() {
        let panel = TestPanel(
            contentRect: NSRect(origin: .zero, size: .init(width: 100, height: 80)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.extendedEdgesInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        let originalFrame = panel.frame

        panel.setFrame(NSRect(origin: .init(x: 200, y: 200), size: .init(width: 400, height: 400)), display: true)

        #expect(panel.frame == originalFrame)
        #expect(panel.recordedFrames.count >= 1) // init path records internal frames
    }

    @Test
    func `set extended frame allows move with insets`() {
        let panel = TestPanel(
            contentRect: NSRect(origin: .zero, size: .init(width: 120, height: 90)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.extendedEdgesInset = NSEdgeInsets(top: 6, left: 10, bottom: 8, right: 4)

        let targetExtended = NSRect(origin: .init(x: 40, y: 30), size: .init(width: 200, height: 150))
        panel.setExtendedFrame(targetExtended)

        #expect(panel.frame == targetExtended)
        let expectedBase = NSRect(
            origin: .init(x: targetExtended.origin.x + 10, y: targetExtended.origin.y + 8),
            size: .init(width: 200 - 10 - 4, height: 150 - 6 - 8)
        )
        #expect(panel.baseContentFrame == expectedBase)
    }
}
