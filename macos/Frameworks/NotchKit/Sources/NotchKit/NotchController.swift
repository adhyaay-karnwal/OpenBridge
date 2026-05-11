import AppKit

@MainActor
public final class NotchController {
    public static let automationIdentifier = NotchWindowMetadata.automationIdentifier

    public var hasActivity: Bool {
        runtimeModel.scene.hasActivity
    }

    private var configuration: NotchConfiguration
    private let runtimeModel: NotchRuntimeModel
    private let windowManager = NotchWindowManager()
    private let interactionMonitor = NotchInteractionMonitor()

    private var screenObserver: NSObjectProtocol?
    private var hasStarted = false

    public init(configuration: NotchConfiguration = .init()) {
        self.configuration = configuration
        runtimeModel = NotchRuntimeModel(configuration: configuration)
        runtimeModel.onLayoutInvalidated = { [weak windowManager, weak runtimeModel] in
            guard let windowManager, let runtimeModel else { return }
            Task { @MainActor in
                windowManager.syncWindow(with: runtimeModel)
            }
        }
    }

    @MainActor
    deinit {
        stop()
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        interactionMonitor.onMouseDown = { [weak self] point in
            self?.runtimeModel.handleMouseDown(at: point)
        }
        interactionMonitor.onMouseMoved = { [weak self] point in
            self?.runtimeModel.handleMouseMoved(at: point)
        }
        interactionMonitor.start()

        observeScreenChanges()
        refreshScreen()
        windowManager.syncWindow(with: runtimeModel)
    }

    public func stop() {
        guard hasStarted else { return }
        hasStarted = false

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil

        interactionMonitor.onMouseDown = nil
        interactionMonitor.onMouseMoved = nil
        interactionMonitor.stop()
        windowManager.close()
    }

    public func update(scene: NotchScene) {
        runtimeModel.updateScene(scene)
        if hasStarted {
            refreshScreen()
            windowManager.syncWindow(with: runtimeModel)
        }
    }

    public func update(configuration: NotchConfiguration) {
        self.configuration = configuration
        runtimeModel.configuration = configuration

        guard hasStarted else { return }

        refreshScreen()
        windowManager.syncWindow(with: runtimeModel)
    }

    public func open() {
        runtimeModel.open()
        windowManager.syncWindow(with: runtimeModel)
    }

    public func close() {
        runtimeModel.close()
        windowManager.syncWindow(with: runtimeModel)
    }

    public func toggle() {
        runtimeModel.toggle()
        windowManager.syncWindow(with: runtimeModel)
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshScreen()
                self.windowManager.syncWindow(with: self.runtimeModel)
            }
        }
    }

    private func refreshScreen() {
        guard let screen = preferredScreen() else { return }
        runtimeModel.updateScreen(screen, fallbackSize: configuration.fallbackNotchSize)
    }

    private func preferredScreen() -> NSScreen? {
        switch configuration.screenSelectionPolicy {
        case .builtInFirst:
            if let builtIn = NSScreen.builtInNotchDisplay, builtIn.notchKitSize != .zero {
                return builtIn
            }
            return NSScreen.main ?? NSScreen.screens.first
        case .screenUnderPointer:
            return NSScreen.screenUnderPointer ?? NSScreen.main ?? NSScreen.screens.first
        case .mainScreen:
            return NSScreen.main ?? NSScreen.screens.first
        }
    }
}
