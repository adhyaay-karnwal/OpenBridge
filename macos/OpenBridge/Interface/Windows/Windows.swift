import AppKit
@preconcurrency import Combine
import SwiftUI

@MainActor
final class Windows: NSObject {
    static let shared: Windows = .init()

    private lazy var chatPanel: ChatWindow<ChatWindowView> = Factory.makeChatPanel()
    private lazy var chatMainWindow: ChatMainWindow<ChatMainWindowView> = Factory.makeChatMainWindow()
    private lazy var backgroundPanel: Panel<TaskPanelView> = Factory.makeBackgroundPanel()
    private lazy var settingsPanel: Panel<SettingsWindowView> = Factory.makeSettingsWindow()
    private lazy var chatPresentationController = ChatPresentationController(
        panelWindow: { self.chatPanel },
        mainWindow: { self.chatMainWindow }
    )

    private let genieAnimator = GenieEffectAnimator()
    private var isAnimatingChat = false
    private var chatHasBeenClosedWithGenie = false
    private var chatGenieSnapshot: GenieEffectAnimator.WindowSnapshot?
    private var pendingChatNotchBounce: DispatchWorkItem?

    @Published private var pinned: Set<Kind> = .init()
    private(set) lazy var pinnedWindowsPublishser: AnyPublisher<Set<Kind>, Never> = $pinned
        .ensureMainThread()
        .eraseToAnyPublisher()

    override init() {
        super.init()
    }

    func boot() {
        _ = chatPanel
        _ = chatMainWindow
        _ = backgroundPanel
        _ = settingsPanel

        closeAll()

        DispatchQueue.main.async {
            self.setupWindowTriggers()
        }
    }

    func closeAll() {
        closeChatWindowWithoutReset(mode: .panel)
        closeChatWindowWithoutReset(mode: .window)
        closeWithoutAnimation(window: backgroundPanel, kind: .backgroundTasks)
        closeWithoutAnimation(window: settingsPanel, kind: .settings)
    }

    func windowInstance(for kind: Kind) -> NSWindow {
        switch kind {
        case .chat: chatPresentationController.activeWindow()
        case .backgroundTasks: backgroundPanel
        case .settings: settingsPanel
        }
    }

    func open(_ kind: Kind, animated: Bool = true) {
        // Use genie effect for chat window
        if animated, shouldUseChatGenieEffect(for: kind) {
            openWithGenieEffect(kind)
            return
        }

        openWithoutAnimation(kind)
    }

    private func openWithoutAnimation(_ kind: Kind) {
        openWithoutAnimation(window: windowInstance(for: kind), kind: kind)
    }

    private func openWithoutAnimation(window: NSWindow, kind: Kind) {
        Logger.ui.info("opening window: \(kind)")
        AnalyticsManager.track(.init(do: .windowOpened(kind: String(describing: kind))))

        if kind == .chat {
            chatHasBeenClosedWithGenie = false
        }

        if let targetScreen = NSScreen.screenForCurrentInteraction,
           window.screen != targetScreen
        {
            window.moveToCenter(of: targetScreen)
        }

        bringWindowToFront(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.bringWindowToFront(window)
        }

        NotificationCenter.default.post(name: .windowDidOpen, object: kind)
    }

    func close(_ kind: Kind, animated: Bool = true, completion: (() -> Void)? = nil) {
        close(kind, animated: animated, preserveChatSurface: false, completion: completion)
    }

    private func close(
        _ kind: Kind,
        animated: Bool,
        preserveChatSurface: Bool,
        completion: (() -> Void)? = nil
    ) {
        // Use genie effect for chat window
        if animated, shouldUseChatGenieEffect(for: kind) {
            closeWithGenieEffect(kind, completion: completion)
            return
        }

        if kind == .chat {
            let window = windowInstance(for: kind)
            closeWithoutAnimation(window: window, kind: kind, preserveChatSurface: preserveChatSurface)
        } else {
            closeWithoutAnimation(window: windowInstance(for: kind), kind: kind)
        }
        completion?()
    }

    private func closeWithoutAnimation(
        window: NSWindow,
        kind: Kind,
        preserveChatSurface: Bool = false
    ) {
        Logger.ui.info("closing window: \(kind)")
        AnalyticsManager.track(.init(do: .windowClosed(kind: String(describing: kind))))

        if kind == .chat {
            chatHasBeenClosedWithGenie = false
            chatGenieSnapshot = nil
            cancelPendingChatNotchBounce()
        }

        if preserveChatSurface, let chatWindow = window as? any ChatSurfaceCloseControlling {
            chatWindow.closeWithoutReset()
            return
        }

        window.close()
    }

    private func closeWithGenieEffect(_ kind: Kind, completion: (() -> Void)? = nil) {
        let window = windowInstance(for: kind)

        guard window.isVisible else {
            completion?()
            return
        }

        guard !isAnimatingChat else {
            return
        }

        isAnimatingChat = true

        Logger.ui.info("closing window with genie effect: \(kind)")
        AnalyticsManager.track(.init(do: .windowClosed(kind: String(describing: kind))))

        let snapshot = genieAnimator.captureWindowSnapshot(of: window)
        chatGenieSnapshot = snapshot
        scheduleChatNotchBounce(after: genieAnimator.estimatedNotchContactDelay(for: window))

        genieAnimator.animate(window: window, direction: .toNotch, snapshot: snapshot) { [weak self] in
            self?.chatHasBeenClosedWithGenie = true
            window.close()
            self?.isAnimatingChat = false
            completion?()
        }
    }

    private func openWithGenieEffect(_ kind: Kind) {
        guard !isAnimatingChat else { return }

        let window = windowInstance(for: kind)

        if window.isVisible {
            bringWindowToFront(window)
            return
        }

        guard chatHasBeenClosedWithGenie else {
            openWithoutAnimation(kind)
            return
        }

        guard let snapshot = chatGenieSnapshot else {
            chatHasBeenClosedWithGenie = false
            openWithoutAnimation(kind)
            return
        }

        isAnimatingChat = true

        Logger.ui.info("opening window with genie effect: \(kind)")
        AnalyticsManager.track(.init(do: .windowOpened(kind: String(describing: kind))))

        if let targetScreen = NSScreen.screenForCurrentInteraction,
           window.screen != targetScreen
        {
            window.moveToCenter(of: targetScreen)
        }

        // Render the real window behind the animation window, then crossfade back to it.
        window.alphaValue = 0
        bringWindowToFront(window)
        window.displayIfNeeded()
        window.contentView?.displayIfNeeded()
        triggerChatNotchBounce()

        genieAnimator.animate(window: window, direction: .fromNotch, snapshot: snapshot) { [weak self] in
            window.alphaValue = 1
            self?.bringWindowToFront(window)
            self?.chatHasBeenClosedWithGenie = false
            self?.chatGenieSnapshot = nil
            self?.isAnimatingChat = false
            NotificationCenter.default.post(name: .windowDidOpen, object: kind)
        }
    }

    private func shouldUseChatGenieEffect(for kind: Kind) -> Bool {
        guard kind == .chat else { return false }
        return TaskViewModel.shared.hasActiveTasks
    }

    func handleChatPerformCloseRequest(from window: NSWindow) -> Bool {
        guard window == chatPanel || window == chatMainWindow else { return false }
        guard window.isVisible else { return false }
        close(.chat)
        return true
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.focus()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func scheduleChatNotchBounce(after delay: TimeInterval?) {
        cancelPendingChatNotchBounce()

        let work = DispatchWorkItem {
            NotchCenter.shared.triggerNotificationBounce()
        }
        pendingChatNotchBounce = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, delay ?? 0),
            execute: work
        )
    }

    private func triggerChatNotchBounce() {
        cancelPendingChatNotchBounce()
        NotchCenter.shared.triggerNotificationBounce()
    }

    private func cancelPendingChatNotchBounce() {
        pendingChatNotchBounce?.cancel()
        pendingChatNotchBounce = nil
    }

    func toggle(_ kind: Kind) {
        let window = windowInstance(for: kind)
        if window.isVisible {
            close(kind)
        } else {
            open(kind)
        }
    }

    func isPinned(_ kind: Kind) -> Bool {
        pinned.contains(kind)
    }

    func pin(_ kind: Kind) {
        Logger.ui.info("pinning window: \(kind)")
        pinned.insert(kind)
    }

    func unpin(_ kind: Kind) {
        Logger.ui.info("unpinning window: \(kind)")
        pinned.remove(kind)
    }

    func switchChatPresentationMode(to mode: ChatPresentationMode) {
        let previousVisibleMode = chatPresentationController.visibleMode
        chatPresentationController.preferredMode = mode

        guard previousVisibleMode != mode else {
            bringWindowToFront(chatPresentationController.window(for: mode))
            return
        }

        if let previousVisibleMode {
            closeChatWindowWithoutReset(mode: previousVisibleMode)
        }

        openWithoutAnimation(window: chatPresentationController.window(for: mode), kind: .chat)
    }

    var currentChatPresentationMode: ChatPresentationMode {
        chatPresentationController.resolvedMode()
    }

    var allManagedWindows: [NSWindow] {
        [
            chatPanel,
            chatMainWindow,
            backgroundPanel,
            settingsPanel,
        ]
    }

    private func closeChatWindowWithoutReset(mode: ChatPresentationMode) {
        let window = chatPresentationController.window(for: mode)
        closeWithoutAnimation(window: window, kind: .chat, preserveChatSurface: true)
    }
}
