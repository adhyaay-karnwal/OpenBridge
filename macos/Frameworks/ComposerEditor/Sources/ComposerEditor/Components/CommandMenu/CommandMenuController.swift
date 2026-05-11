//
//  CommandMenuController.swift
//  ComposerEditor
//

import AppKit

/// Controller that manages the command menu lifecycle
@MainActor
public final class CommandMenuController: NSObject, CommandMenuDelegate {
    public weak var dataSource: CommandMenuDataSource?

    public var onCommandSelected: ((CommandItem) -> Void)?
    public var onMenuDismissed: (() -> Void)?

    private var menuView: CommandMenuView?
    private var menuWindow: NSPanel?
    private weak var parentTextView: NSTextView?

    private var triggerRange: NSRange?
    private var currentQuery: String = ""

    private var clickMonitor: Any?
    private var windowObserver: NSObjectProtocol?

    public var isMenuVisible: Bool {
        menuWindow?.isVisible ?? false
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitors()
        }
    }

    public func showMenu(in textView: NSTextView, triggerRange: NSRange) {
        parentTextView = textView
        self.triggerRange = triggerRange
        currentQuery = ""

        let menuView = CommandMenuView()
        menuView.delegate = self
        self.menuView = menuView

        let commands = dataSource?.commandMenuItems() ?? []
        menuView.updateCommands(commands)

        let menuWindow = NSPanel(
            contentRect: NSRect(origin: .zero, size: menuView.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        menuWindow.isOpaque = false
        menuWindow.backgroundColor = .clear
        menuWindow.hasShadow = true
        menuWindow.level = .popUpMenu
        menuWindow.contentView = menuView

        if let parentWindow = textView.window {
            menuWindow.appearance = parentWindow.effectiveAppearance
        }

        self.menuWindow = menuWindow

        positionMenu()
        menuWindow.orderFront(nil)

        setupMonitors()
    }

    public func updateQuery(_ query: String) {
        currentQuery = query
        let commands = dataSource?.commandMenuItems(matching: query) ?? []
        menuView?.updateCommands(commands)

        if commands.isEmpty {
            hideMenu()
        } else if let menuView {
            menuWindow?.setContentSize(menuView.frame.size)
            positionMenu()
        }
    }

    public func hideMenu() {
        removeMonitors()
        menuWindow?.orderOut(nil)
        menuWindow = nil
        menuView = nil
        parentTextView = nil
        triggerRange = nil
        currentQuery = ""
    }

    public func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let menuView, isMenuVisible else { return false }
        return menuView.handleKeyEvent(event)
    }

    private func setupMonitors() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let menuWindow else { return event }
            guard event.window !== menuWindow else { return event }
            MainActor.assumeIsolated {
                self.onMenuDismissed?()
                self.hideMenu()
            }
            return event
        }

        // Monitor for parent window changes
        if let parentWindow = parentTextView?.window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onMenuDismissed?()
                    self?.hideMenu()
                }
            }
        }
    }

    private func removeMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
    }

    private func positionMenu() {
        guard let textView = parentTextView,
              let menuWindow,
              let triggerRange,
              let window = textView.window
        else { return }

        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!

        let glyphRange = layoutManager.glyphRange(forCharacterRange: triggerRange, actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x += textView.textContainerOrigin.x
        lineRect.origin.y += textView.textContainerOrigin.y

        let rectInWindow = textView.convert(lineRect, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)

        let menuSize = menuWindow.frame.size
        var menuOrigin = NSPoint(
            x: rectInScreen.origin.x,
            y: rectInScreen.origin.y - menuSize.height - 4
        )

        if let screen = window.screen {
            let screenFrame = screen.visibleFrame

            if menuOrigin.x + menuSize.width > screenFrame.maxX {
                menuOrigin.x = screenFrame.maxX - menuSize.width
            }
            if menuOrigin.x < screenFrame.minX {
                menuOrigin.x = screenFrame.minX
            }
            if menuOrigin.y < screenFrame.minY {
                menuOrigin.y = rectInScreen.maxY + 4
            }
        }

        menuWindow.setFrameOrigin(menuOrigin)
    }

    // MARK: - CommandMenuDelegate

    public func commandMenu(_: CommandMenuView, didSelectCommand command: CommandItem) {
        onCommandSelected?(command)
        hideMenu()
    }

    public func commandMenuDidCancel(_: CommandMenuView) {
        onMenuDismissed?()
        hideMenu()
    }
}
