import AppKit

@MainActor
final class ChatPresentationController {
    private let panelWindow: () -> NSWindow
    private let mainWindow: () -> NSWindow

    init(
        panelWindow: @escaping () -> NSWindow,
        mainWindow: @escaping () -> NSWindow
    ) {
        self.panelWindow = panelWindow
        self.mainWindow = mainWindow
    }

    var preferredMode: ChatPresentationMode {
        get { SettingsManager.shared.chatPresentationMode }
        set { SettingsManager.shared.chatPresentationMode = newValue }
    }

    var visibleMode: ChatPresentationMode? {
        if panelWindow().isVisible {
            return .panel
        }
        if mainWindow().isVisible {
            return .window
        }
        return nil
    }

    func resolvedMode() -> ChatPresentationMode {
        visibleMode ?? preferredMode
    }

    func activeWindow() -> NSWindow {
        window(for: resolvedMode())
    }

    func visibleWindow() -> NSWindow? {
        guard let visibleMode else { return nil }
        return window(for: visibleMode)
    }

    func window(for mode: ChatPresentationMode) -> NSWindow {
        switch mode {
        case .panel:
            panelWindow()
        case .window:
            mainWindow()
        }
    }

    func inactiveWindow(for mode: ChatPresentationMode) -> NSWindow {
        switch mode {
        case .panel:
            mainWindow()
        case .window:
            panelWindow()
        }
    }
}
