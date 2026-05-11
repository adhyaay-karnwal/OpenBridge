import AppKit
import SwiftUI

/// Controller for managing the skill import dialog window
@MainActor
final class SkillImportWindowController {
    static let shared = SkillImportWindowController()

    private var window: NSWindow?
    private var viewModel: SkillImportViewModel?

    private init() {}

    /// Whether the skill import window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// Show the skill import dialog for a given name
    /// - Parameters:
    ///   - name: The skill name to import
    ///   - source: The source of the skill (official or external)
    ///   - repo: Optional repository for disambiguation (external skills)
    ///   - onComplete: Called when import is complete with the imported skill info
    func show(name: String, source: SkillSource = .official, repo: String? = nil, onComplete: @escaping (SkillInfo?) -> Void) {
        // Close existing window if any
        close()

        let viewModel = SkillImportViewModel()
        self.viewModel = viewModel

        viewModel.onCancel = { [weak self] in
            self?.close()
            onComplete(nil)
        }

        viewModel.onImport = { [weak self] info in
            self?.close()
            onComplete(info)
        }

        let view = SkillImportView(viewModel: viewModel)
            .injectGlassMaterialMode()
            .environment(SettingsManager.shared)
        let hostingController = NSHostingController(rootView: AnyView(view))

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .fullSizeContentView]
        window.title = String(localized: "Import Skill")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .modalPanel
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Hide traffic light buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Configure corner radius (glass effect is applied in SwiftUI view)
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 16
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }

        // Set initial size and center on screen
        let windowHeight: CGFloat = source == .external ? 480 : 520
        window.setContentSize(NSSize(width: 420, height: windowHeight))
        window.center()

        self.window = window

        // Load skill info with source and optional repo
        viewModel.load(name: name, source: source, repo: repo)

        // Show window without bringing other windows to front
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() {
        window?.close()
        window = nil
        viewModel = nil
    }
}
