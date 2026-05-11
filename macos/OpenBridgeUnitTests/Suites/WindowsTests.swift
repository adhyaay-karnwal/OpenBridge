//
//  WindowsTests.swift
//  OpenBridgeUnitTests
//
//  Created by qaq on 4/12/2025.
//

import AppKit
@testable import OpenBridge
import Testing

@MainActor
struct WindowsTests {
    // MARK: - Window Kind Tests

    @Test
    func `all window kinds are defined`() {
        let allKinds = Windows.Kind.allCases
        #expect(allKinds.contains(.chat))
        #expect(allKinds.contains(.backgroundTasks))
        #expect(allKinds.contains(.settings))
        #expect(allKinds.count == 3)
    }

    // MARK: - Chat Panel Tests

    @Test
    func `chat panel has correct configuration`() {
        let window = Windows.Factory.makeChatPanel()

        #expect(window.identifier?.rawValue == "com.openbridge.window.chat")
        #expect(window.level == .normal)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(!window.styleMask.contains(.nonactivatingPanel))
        #expect(window.isOpaque == false)
        #expect(window.backgroundColor == .clear)
        #expect(window.hasShadow == true)
        #expect(window.canBecomeKey == true)
        #expect(window.canBecomeMain == true)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
    }

    @Test
    func `chat main window has correct configuration`() {
        let window = Windows.Factory.makeChatMainWindow()

        #expect(window.identifier?.rawValue == "com.openbridge.window.chat.main")
        #expect(window.level == .normal)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.isOpaque == true)
        #expect(window.backgroundColor == .windowBackgroundColor)
        #expect(window.hasShadow == true)
        #expect(window.canBecomeKey == true)
        #expect(window.canBecomeMain == true)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == false)
        #expect(window.minSize == NSSize(width: 900, height: 640))
    }

    @Test
    func `chat presentation controller uses persisted preferred mode and routes windows`() {
        let originalMode = SettingsManager.shared.chatPresentationMode
        defer { SettingsManager.shared.chatPresentationMode = originalMode }

        let panelWindow = NSWindow()
        let mainWindow = NSWindow()
        let controller = ChatPresentationController(
            panelWindow: { panelWindow },
            mainWindow: { mainWindow }
        )

        SettingsManager.shared.chatPresentationMode = .panel
        #expect(controller.preferredMode == .panel)
        #expect(controller.resolvedMode() == .panel)
        #expect(controller.window(for: .panel) === panelWindow)
        #expect(controller.window(for: .window) === mainWindow)

        controller.preferredMode = .window
        #expect(SettingsManager.shared.chatPresentationMode == .window)
        #expect(controller.resolvedMode() == .window)
        #expect(controller.activeWindow() === mainWindow)
    }

    // MARK: - Background Panel Tests

    @Test
    func `background panel has correct configuration`() {
        let panel = Windows.Factory.makeBackgroundPanel()

        #expect(panel.identifier?.rawValue == "com.openbridge.window.background")
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.isMovable == false)
        #expect(panel.ignoresMouseEvents == false)
        #expect(panel.isExcludedFromWindowsMenu == true)
    }

    // MARK: - Settings Panel Tests

    @Test
    func `settings panel has correct configuration`() {
        let panel = Windows.Factory.makeSettingsWindow()

        #expect(panel.identifier?.rawValue == "com.openbridge.window.settings")
        #expect(panel.level == .normal)
        #expect(panel.styleMask.contains(.titled))
        #expect(panel.styleMask.contains(.closable))
        #expect(panel.styleMask.contains(.miniaturizable))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.isFloatingPanel == false)
        #expect(panel.titleVisibility == .visible)
        #expect(panel.titlebarAppearsTransparent == false)
        #expect(panel.isOpaque == true)
        #expect(panel.backgroundColor == .windowBackgroundColor)
        #expect(panel.isMovableByWindowBackground == false)
        #expect(panel.title == String(localized: "Settings"))
        #expect(panel.standardWindowButton(.closeButton)?.isHidden == false)
        #expect(panel.standardWindowButton(.miniaturizeButton)?.isHidden == false)
        #expect(panel.standardWindowButton(.zoomButton)?.isHidden == false)
    }

    // MARK: - Position Calculation Tests

    @Test
    func `position calculation respects screen offsets`() {
        let screenFrame = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let windowSize = CGSize(width: 400, height: 300)
        let padding: CGFloat = 10

        let centerOrigin = Windows.calculateOrigin(
            position: .center,
            screenFrame: screenFrame,
            windowSize: windowSize,
            padding: padding
        )
        #expect(centerOrigin.x == 3000) // 1920 + (2560 - 400) / 2
        #expect(centerOrigin.y == 570) // (1440 - 300) / 2

        let topLeftOrigin = Windows.calculateOrigin(
            position: .topLeft,
            screenFrame: screenFrame,
            windowSize: windowSize,
            padding: padding
        )
        #expect(topLeftOrigin.x == screenFrame.minX + padding)
        #expect(topLeftOrigin.y == screenFrame.maxY - windowSize.height - padding)
    }
}
