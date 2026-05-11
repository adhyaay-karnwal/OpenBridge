//
//  CommandMenuView.swift
//  ComposerEditor
//

import AppKit
import GlassEffectKit
import SwiftUI

/// Delegate protocol for command menu events
@MainActor
public protocol CommandMenuDelegate: AnyObject {
    func commandMenu(_ menu: CommandMenuView, didSelectCommand command: CommandItem)
    func commandMenuDidCancel(_ menu: CommandMenuView)
}

/// A pure AppKit menu view for displaying and selecting commands.
/// Supports keyboard navigation (up/down arrows, enter, escape).
@MainActor
public final class CommandMenuView: NSView {
    public weak var delegate: CommandMenuDelegate?

    // MARK: - Layout Constants

    private let cornerRadius: CGFloat = 18
    private let itemHeight: CGFloat = 32
    private let maxVisibleItems: Int = 8
    private let menuWidth: CGFloat = 200
    private let verticalPadding: CGFloat = 12

    // MARK: - Subviews

    private var backgroundView: NSView!
    private var backgroundConstraints: [NSLayoutConstraint] = []
    private var usesMacOS26Background = false
    private var userDefaultsObserver: NSObjectProtocol?
    private let scrollView: NSScrollView
    private let stackView: NSStackView
    private var itemViews: [CommandMenuItemView] = []
    private var commands: [CommandItem] = []
    private var selectedIndex: Int = 0

    // MARK: - Initialization

    override public init(frame frameRect: NSRect) {
        scrollView = NSScrollView()
        stackView = NSStackView()

        super.init(frame: frameRect)

        setupView()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    deinit {
        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowColor = NSColor.black.cgColor

        configureBackgroundView()
        observeMacOS26UISettingChanges()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: verticalPadding, left: 2, bottom: verticalPadding, right: 2)

        let clipView = NSClipView()
        clipView.translatesAutoresizingMaskIntoConstraints = false
        clipView.drawsBackground = false
        clipView.documentView = stackView

        scrollView.contentView = clipView

        addSubview(backgroundView)
        addSubview(scrollView)

        backgroundConstraints = makeBackgroundConstraints(for: backgroundView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])
        NSLayoutConstraint.activate(backgroundConstraints)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        itemViews.forEach { $0.updateAppearance() }
    }

    // MARK: - Public API

    public func updateCommands(_ commands: [CommandItem]) {
        self.commands = commands
        selectedIndex = commands.isEmpty ? -1 : 0

        for view in itemViews {
            view.removeFromSuperview()
        }
        itemViews.removeAll()

        for (index, command) in commands.enumerated() {
            let itemView = CommandMenuItemView(command: command)
            itemView.translatesAutoresizingMaskIntoConstraints = false
            itemView.onSelect = { [weak self] in
                self?.selectItem(at: index)
            }
            itemView.onHover = { [weak self] in
                self?.highlightItem(at: index)
            }

            stackView.addArrangedSubview(itemView)
            itemViews.append(itemView)

            NSLayoutConstraint.activate([
                itemView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                itemView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
                itemView.heightAnchor.constraint(equalToConstant: itemHeight),
            ])
        }

        updateSelection()
        updateFrameSize()
    }

    private func updateFrameSize() {
        let itemCount = min(commands.count, maxVisibleItems)
        let insetHeight = verticalPadding * 2
        let height = CGFloat(itemCount) * itemHeight + insetHeight
        frame.size = NSSize(width: menuWidth, height: max(height, itemHeight + insetHeight))
    }

    // MARK: - Selection

    private func highlightItem(at index: Int) {
        guard index >= 0, index < commands.count else { return }
        selectedIndex = index
        updateSelection()
    }

    private func selectItem(at index: Int) {
        guard index >= 0, index < commands.count else { return }
        delegate?.commandMenu(self, didSelectCommand: commands[index])
    }

    private func updateSelection() {
        for (index, itemView) in itemViews.enumerated() {
            itemView.isHighlighted = index == selectedIndex
        }
    }

    // MARK: - Keyboard Navigation

    public func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !commands.isEmpty else { return false }

        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
            return true
        case 126: // Up arrow
            moveSelection(by: -1)
            return true
        case 36, 76: // Return / Enter
            confirmSelection()
            return true
        case 53: // Escape
            delegate?.commandMenuDidCancel(self)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !commands.isEmpty else { return }
        var newIndex = selectedIndex + delta
        if newIndex < 0 {
            newIndex = commands.count - 1
        } else if newIndex >= commands.count {
            newIndex = 0
        }
        selectedIndex = newIndex
        updateSelection()
        scrollToSelectedItem()
    }

    private func scrollToSelectedItem() {
        guard selectedIndex >= 0, selectedIndex < itemViews.count else { return }
        let itemView = itemViews[selectedIndex]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            itemView.scrollToVisible(itemView.bounds)
        }
    }

    private func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < commands.count else { return }
        delegate?.commandMenu(self, didSelectCommand: commands[selectedIndex])
    }

    override public var intrinsicContentSize: NSSize {
        frame.size
    }

    private func configureBackgroundView() {
        usesMacOS26Background = MacOS26UICompatibility.shouldUseMacOS26UI()
        backgroundView = makeBackgroundView(usingMacOS26Background: usesMacOS26Background)
    }

    private func observeMacOS26UISettingChanges() {
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBackgroundViewIfNeeded()
            }
        }
    }

    private func updateBackgroundViewIfNeeded() {
        let shouldUseMacOS26Background = MacOS26UICompatibility.shouldUseMacOS26UI()
        guard shouldUseMacOS26Background != usesMacOS26Background else { return }

        let newBackgroundView = makeBackgroundView(usingMacOS26Background: shouldUseMacOS26Background)
        addSubview(newBackgroundView, positioned: .below, relativeTo: scrollView)

        NSLayoutConstraint.deactivate(backgroundConstraints)
        backgroundConstraints = makeBackgroundConstraints(for: newBackgroundView)
        NSLayoutConstraint.activate(backgroundConstraints)

        backgroundView.removeFromSuperview()
        backgroundView = newBackgroundView
        usesMacOS26Background = shouldUseMacOS26Background
    }

    private func makeBackgroundView(usingMacOS26Background: Bool) -> NSView {
        if usingMacOS26Background, #available(macOS 26.0, *) {
            let glassView = NSHostingView(rootView: GlassBackgroundView(cornerRadius: cornerRadius))
            glassView.translatesAutoresizingMaskIntoConstraints = false
            return glassView
        }

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        return effectView
    }

    private func makeBackgroundConstraints(for backgroundView: NSView) -> [NSLayoutConstraint] {
        [
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
    }
}

// MARK: - Menu Item View

@MainActor
final class CommandMenuItemView: NSView {
    let command: CommandItem
    var onSelect: (() -> Void)?
    var onHover: (() -> Void)?

    var isHighlighted: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private let iconView: NSImageView?
    private let nameLabel: NSTextField
    private let backgroundLayer: CALayer
    private var trackingArea: NSTrackingArea?

    private let horizontalPadding: CGFloat = 12
    private let iconSize: CGFloat = 20
    private let iconSpacing: CGFloat = 6

    init(command: CommandItem) {
        self.command = command

        // Create icon view if icon image is provided
        if let iconImage = command.iconImage {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = iconImage
            imageView.imageScaling = .scaleProportionallyUpOrDown
            iconView = imageView
        } else {
            iconView = nil
        }

        nameLabel = NSTextField(labelWithString: command.name)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail

        backgroundLayer = CALayer()

        super.init(frame: .zero)

        wantsLayer = true
        layer?.addSublayer(backgroundLayer)

        if let iconView {
            addSubview(iconView)
        }
        addSubview(nameLabel)

        if let iconView {
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),

                nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconSpacing),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalPadding),
                nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalPadding),
                nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance() {
        if isHighlighted {
            backgroundLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.2).cgColor
            nameLabel.textColor = .labelColor
        } else {
            backgroundLayer.backgroundColor = nil
            nameLabel.textColor = .labelColor
        }
    }

    override func layout() {
        super.layout()
        let insetBounds = bounds.insetBy(dx: 4, dy: 0)
        backgroundLayer.frame = insetBounds
        // Capsule corner radius = half of the height
        backgroundLayer.cornerRadius = insetBounds.height / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with _: NSEvent) {
        onHover?()
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onSelect?()
        }
    }
}

// MARK: - Glass Background View (macOS 26+)

@available(macOS 26.0, *)
private struct GlassBackgroundView: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .safeGlassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
