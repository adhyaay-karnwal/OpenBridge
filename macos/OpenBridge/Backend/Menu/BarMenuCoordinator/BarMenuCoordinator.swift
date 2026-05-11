import AppKit
import Combine

@MainActor
final class BarMenuCoordinator: NSObject {
    let statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // hide by default, turn on when `rebuild()`
        item.isVisible = false
        return item
    }()

    static let shared = BarMenuCoordinator()

    private var cancellables: Set<AnyCancellable> = []
    private let taskViewModel = TaskViewModel.shared

    override init() {
        super.init()
        if SettingsManager.shared.showMenuBarIcon {
            rebuild()
        }
        setupTaskSubscription()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupTaskSubscription() {
        // Subscribe to update manager changes
        SparkleUpdateManager.shared.$menuState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuild()
            }
            .store(in: &cancellables)

        // Subscribe to task updates for reactive menu updates
        taskViewModel.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTaskBadge()
            }
            .store(in: &cancellables)
    }

    private func updateTaskBadge() {
        guard let button = statusItem.button else { return }
        let count = taskViewModel.liveInfo.count
        if count > 0 {
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            ]
            button.attributedTitle = NSAttributedString(
                string: "\(count)",
                attributes: attributes
            )
        } else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    func rebuild() {
        Logger.ui.info("rebuilding bar menu")
        configureButtonAppearance()
        statusItem.menu = buildMenu()
        statusItem.isVisible = true
        updateTaskBadge()
    }

    private func configureButtonAppearance() {
        guard let button = statusItem.button else { return }
        #if DEBUG
            button.image = .barIcon.tinted(with: .systemRed)
        #else
            button.image = .barIcon
        #endif
        button.imagePosition = .imageLeading
        button.alphaValue = 1.0
    }

    func hide() {
        Logger.ui.log("hide bar menu")
        statusItem.isVisible = false
    }

    private func buildMenu() -> NSMenu {
        let entry = NSMenu()
        entry.delegate = self
        let allItems = allSections.map { $0.sectionItems() }
        for (idx, items) in allItems.enumerated() {
            for item in items {
                entry.addItem(item)
            }
            if idx < allItems.count - 1 {
                entry.addItem(NSMenuItem.separator())
            }
        }
        return entry
    }
}
