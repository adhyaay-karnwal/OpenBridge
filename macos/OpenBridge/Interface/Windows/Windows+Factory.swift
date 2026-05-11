import AppKit
import SwiftUI

extension Windows {
    @MainActor
    enum Factory {
        static func makeChatPanel() -> ChatWindow<ChatWindowView> {
            let panel = ChatWindow(
                preferredContentSize: NSSize(width: 640, height: 780),
                identifier: PanelIdentifier.chat.rawValue,
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                level: .normal,
                collectionBehavior: [.fullScreenAuxiliary, .moveToActiveSpace],
                content: { ChatWindowView() }
            )
            panel.contentView?.setContentHuggingPriority(.required, for: .vertical)
            panel.contentView?.setContentCompressionResistancePriority(.required, for: .vertical)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            applyContinuousCornerMask(to: panel, cornerRadius: 28)
            panel.setAccessibilityIdentifier(AccessibilityID.Chat.panelWindow)
            return panel
        }

        static func makeChatMainWindow() -> ChatMainWindow<ChatMainWindowView> {
            let window = ChatMainWindow(
                preferredContentSize: NSSize(width: 1100, height: 760),
                identifier: PanelIdentifier.chatMain.rawValue,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                level: .normal,
                collectionBehavior: [.fullScreenPrimary, .moveToActiveSpace],
                content: { ChatMainWindowView() }
            )
            window.minSize = NSSize(width: 900, height: 640)
            window.setAccessibilityIdentifier(AccessibilityID.Chat.mainWindow)
            return window
        }

        static func makeBackgroundPanel() -> Panel<TaskPanelView> {
            let panel = Panel(
                preferredContentSize: NSSize(width: 320, height: 200),
                identifier: PanelIdentifier.background.rawValue,
                styleMask: [.nonactivatingPanel, .borderless],
                level: .floating,
                collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
                content: { TaskPanelView() }
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.isMovable = false
            panel.ignoresMouseEvents = false
            panel.isExcludedFromWindowsMenu = true
            return panel
        }

        static func makeSettingsWindow() -> Panel<SettingsWindowView> {
            let panel = Panel(
                preferredContentSize: NSSize(width: 800, height: 600),
                identifier: PanelIdentifier.settings.rawValue,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                level: .normal,
                collectionBehavior: [.fullScreenAuxiliary, .moveToActiveSpace],
                content: { SettingsWindowView() }
            )
            panel.configureAsStandardWindow(title: String(localized: "Settings"))
            panel.isMovableByWindowBackground = false
            panel.setAccessibilityIdentifier(AccessibilityID.Settings.window)
            return panel
        }
    }

    private enum PanelIdentifier: String {
        case main = "com.openbridge.window.main"
        case chat = "com.openbridge.window.chat"
        case chatMain = "com.openbridge.window.chat.main"
        case background = "com.openbridge.window.background"
        case settings = "com.openbridge.window.settings"
    }
}

private extension Windows.Factory {
    static func applyContinuousCornerMask(to window: NSWindow, cornerRadius: CGFloat) {
        func configure(_ view: NSView?) {
            guard let view else { return }
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }

        configure(window.contentView)
        // AppKit renders sheet dimming above the content view on the frame view.
        // Match that container's mask to the chat window so sheet overlays respect the same radius.
        configure(window.contentView?.superview)
        window.invalidateShadow()
    }
}

private extension NSPanel {
    func configureAsStandardWindow(title: String) {
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        titleVisibility = .visible
        titlebarAppearsTransparent = false
        animationBehavior = .default
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false
        self.title = title
        center()
    }
}
