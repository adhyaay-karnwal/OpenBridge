import AppKit
import Foundation
import Observation

// MARK: - Menu Item Hosting View

@MainActor
final class MenuItemHostingView: NSView {
    private let contentView: ConversationLegacyMenuContentView
    var contentSize: NSSize {
        contentView.contentSize
    }

    init(
        controller: ConversationListViewController,
        currentConversationId: String?,
        streamingConversationIds: Set<String>,
        onSelect: @escaping (SessionListInfo) -> Void,
        onRename: ((SessionListInfo) -> Void)?,
        onDelete: ((SessionListInfo) -> Void)?,
        onShareLink: ((SessionListInfo) -> Void)?
    ) {
        contentView = ConversationLegacyMenuContentView(
            controller: controller,
            currentConversationId: currentConversationId,
            streamingConversationIds: streamingConversationIds,
            onSelect: onSelect,
            onRename: onRename,
            onDelete: onDelete,
            onShareLink: onShareLink
        )
        super.init(frame: .zero)

        addSubview(contentView)
        frame = NSRect(origin: .zero, size: contentView.contentSize)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        contentView.onSizeChange = { [weak self] size in
            guard let self else { return }
            frame = NSRect(origin: .zero, size: size)
            contentView.frame = bounds
            needsLayout = true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private typealias ConversationSessionGroup = (title: String, items: [SessionListInfo])

private func conversationSessionGroups(from sessions: [SessionListInfo]) -> [ConversationSessionGroup] {
    let options = LocalizedTimeOptions(
        relative: RelativeTimeOptions(
            accuracy: .day,
            weekday: true,
            yesterdayAndTomorrow: true
        )
    )

    let sortedSessions = sessions.sorted { $0.updatedAt > $1.updatedAt }

    var groups: [ConversationSessionGroup] = []
    var currentTitle: String?
    var currentItems: [SessionListInfo] = []

    for session in sortedSessions {
        let date = Date(timeIntervalSince1970: TimeInterval(session.updatedAt))
        let title = localizedTime(date, options: options)

        if title != currentTitle {
            if let currentTitle, !currentItems.isEmpty {
                groups.append((title: currentTitle, items: currentItems))
            }
            currentTitle = title
            currentItems = [session]
        } else {
            currentItems.append(session)
        }
    }

    if let currentTitle, !currentItems.isEmpty {
        groups.append((title: currentTitle, items: currentItems))
    }

    return groups
}

private func conversationSectionTitle(_ title: String) -> String {
    title.prefix(1).uppercased() + title.dropFirst()
}

private func conversationDisplayTitle(_ session: SessionListInfo) -> String {
    let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
}

@MainActor
private final class ConversationLegacyMenuContentView: NSView {
    let controller: ConversationListViewController
    let currentConversationId: String?
    let streamingConversationIds: Set<String>
    let onSelect: (SessionListInfo) -> Void
    let onRename: ((SessionListInfo) -> Void)?
    let onDelete: ((SessionListInfo) -> Void)?
    let onShareLink: ((SessionListInfo) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?

    private let style = ConversationListPresentationStyle.menu
    private let scrollView = NSScrollView()
    private let documentView = FlippedConversationMenuContentView()
    private let stackView = NSStackView()

    private(set) var contentSize: NSSize

    init(
        controller: ConversationListViewController,
        currentConversationId: String?,
        streamingConversationIds: Set<String>,
        onSelect: @escaping (SessionListInfo) -> Void,
        onRename: ((SessionListInfo) -> Void)?,
        onDelete: ((SessionListInfo) -> Void)?,
        onShareLink: ((SessionListInfo) -> Void)?
    ) {
        self.controller = controller
        self.currentConversationId = currentConversationId
        self.streamingConversationIds = streamingConversationIds
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
        self.onShareLink = onShareLink
        contentSize = NSSize(width: ConversationListPresentationStyle.menu.menuWidth, height: 88)

        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        documentView.addSubview(stackView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsDidChangeNotification),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        observeState()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    private func observeState() {
        withObservationTracking {
            _ = controller.state
            _ = controller.sessions
            _ = controller.hasMore
            _ = controller.isLoadingMore
            _ = controller.errorMessage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refresh()
                observeState()
            }
        }
    }

    private func refresh() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let sessions = controller.sessions
        if sessions.isEmpty {
            buildEmptyState()
        } else {
            buildSessionRows(groups: conversationSessionGroups(from: sessions))
        }

        let stackHeight = stackView.fittingSize.height
        let contentHeight = max(stackHeight + style.verticalPadding * 2, 1)
        let visibleHeight = min(contentHeight, style.maxHeight)
        let size = NSSize(width: style.menuWidth, height: visibleHeight)

        contentSize = size
        frame = NSRect(origin: .zero, size: size)
        scrollView.frame = bounds
        scrollView.hasVerticalScroller = contentHeight > style.maxHeight
        scrollView.verticalScroller?.controlSize = .small

        documentView.frame = NSRect(x: 0, y: 0, width: style.menuWidth, height: contentHeight)
        stackView.frame = NSRect(
            x: 0,
            y: style.verticalPadding,
            width: style.menuWidth,
            height: stackHeight
        )

        onSizeChange?(size)
        needsLayout = true
        needsDisplay = true

        maybeLoadMoreIfNeeded()
        refreshVisibleRowHoverStates()
    }

    private func buildEmptyState() {
        switch controller.state {
        case .idle, .loading:
            stackView.addArrangedSubview(
                ConversationLegacyMenuStatusView(
                    width: style.menuWidth,
                    minHeight: 88,
                    message: "Loading conversations…",
                    showsSpinner: true
                )
            )

        case .failed:
            stackView.addArrangedSubview(
                ConversationLegacyMenuStatusView(
                    width: style.menuWidth,
                    minHeight: 88,
                    message: controller.errorMessage ?? String(localized: "Failed to load conversations"),
                    actionTitle: String(localized: "Retry"),
                    action: { [weak controller] in
                        controller?.refresh(force: true, silent: false)
                    }
                )
            )

        case .loaded:
            stackView.addArrangedSubview(
                ConversationLegacyMenuStatusView(
                    width: style.menuWidth,
                    minHeight: 44,
                    message: String(localized: "No conversations")
                )
            )
        }
    }

    private func buildSessionRows(groups: [ConversationSessionGroup]) {
        for (sectionIndex, section) in groups.enumerated() {
            if sectionIndex > 0 {
                stackView.addArrangedSubview(
                    ConversationLegacyMenuDividerView(
                        width: style.menuWidth,
                        height: style.dividerHeight
                    )
                )
            }

            stackView.addArrangedSubview(
                ConversationLegacyMenuSectionHeaderView(
                    width: style.menuWidth,
                    height: style.sectionHeaderHeight,
                    title: conversationSectionTitle(section.title),
                    style: style
                )
            )

            for (itemIndex, session) in section.items.enumerated() {
                stackView.addArrangedSubview(
                    ConversationLegacyMenuRowView(
                        width: style.menuWidth,
                        height: style.rowHeight,
                        session: session,
                        isSelected: session.id == currentConversationId,
                        isStreaming: streamingConversationIds.contains(session.id),
                        style: style,
                        onSelect: onSelect,
                        onRename: onRename,
                        onDelete: onDelete,
                        onShareLink: onShareLink
                    )
                )

                if itemIndex < section.items.count - 1 {
                    stackView.addArrangedSubview(
                        ConversationLegacyMenuSpacerView(
                            width: style.menuWidth,
                            height: style.rowSpacing
                        )
                    )
                }
            }
        }

        if controller.isLoadingMore {
            stackView.addArrangedSubview(
                ConversationLegacyMenuLoadMoreView(
                    width: style.menuWidth,
                    height: 28
                )
            )
        }
    }

    private func handleScrollBoundsDidChange() {
        maybeLoadMoreIfNeeded()
        refreshVisibleRowHoverStates()
    }

    @objc
    private func handleScrollBoundsDidChangeNotification() {
        handleScrollBoundsDidChange()
    }

    private func maybeLoadMoreIfNeeded() {
        guard controller.hasMore, !controller.isLoadingMore else { return }

        let visibleHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.maxY
        let contentHeight = documentView.frame.height

        if contentHeight <= visibleHeight + 1 || contentHeight - offsetY < 36 {
            controller.loadMoreIfNeeded()
        }
    }

    private func refreshVisibleRowHoverStates() {
        for row in stackView.arrangedSubviews.compactMap({ $0 as? ConversationLegacyMenuRowView }) {
            row.refreshHoverState()
        }
    }
}

private final class FlippedConversationMenuContentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class ConversationLegacyMenuSpacerView: NSView {
    private let intrinsicSize: NSSize

    init(width: CGFloat, height: CGFloat) {
        intrinsicSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }
}

private final class ConversationLegacyMenuDividerView: NSView {
    private let intrinsicSize: NSSize

    init(width: CGFloat, height: CGFloat) {
        intrinsicSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let lineRect = NSRect(
            x: 16,
            y: floor((bounds.height - 1) / 2),
            width: bounds.width - 32,
            height: 1
        )
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }
}

private final class ConversationLegacyMenuSectionHeaderView: NSView {
    private let intrinsicSize: NSSize
    private let label = NSTextField(labelWithString: "")
    private let style: ConversationListPresentationStyle

    init(width: CGFloat, height: CGFloat, title: String, style: ConversationListPresentationStyle) {
        intrinsicSize = NSSize(width: width, height: height)
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))

        label.stringValue = title
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: style.rowHorizontalPadding + style.rowOuterHorizontalPadding,
            y: floor((bounds.height - 14) / 2),
            width: bounds.width - (style.rowHorizontalPadding + style.rowOuterHorizontalPadding) * 2,
            height: 14
        )
    }
}

private final class ConversationLegacyMenuStatusView: NSView {
    private let intrinsicSize: NSSize
    private let messageField = NSTextField(labelWithString: "")
    private var spinner: NSProgressIndicator?
    private var actionButton: ConversationLegacyMenuActionButton?

    init(
        width: CGFloat,
        minHeight: CGFloat,
        message: String,
        showsSpinner: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        intrinsicSize = NSSize(width: width, height: minHeight)
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))

        messageField.stringValue = message
        messageField.font = .systemFont(ofSize: 12)
        messageField.textColor = .secondaryLabelColor
        messageField.alignment = .center
        messageField.lineBreakMode = .byWordWrapping
        addSubview(messageField)

        if showsSpinner {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            addSubview(spinner)
            self.spinner = spinner
        }

        if let actionTitle, let action {
            let button = ConversationLegacyMenuActionButton(title: actionTitle, action: action)
            addSubview(button)
            actionButton = button
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }

    override func layout() {
        super.layout()

        let buttonHeight = actionButton?.intrinsicContentSize.height ?? 0
        let spinnerHeight: CGFloat = spinner == nil ? 0 : 16
        let contentSpacing: CGFloat =
            (spinner != nil && actionButton != nil) ? 8 :
            (spinner != nil || actionButton != nil) ? 8 : 0
        let totalHeight = spinnerHeight + 18 + buttonHeight + contentSpacing
        var currentY = floor((bounds.height - totalHeight) / 2)

        if let spinner {
            spinner.frame = NSRect(x: floor((bounds.width - 16) / 2), y: currentY, width: 16, height: 16)
            currentY += 16 + 8
        }

        messageField.frame = NSRect(x: 16, y: currentY, width: bounds.width - 32, height: 18)
        currentY += 18

        if let actionButton {
            currentY += 8
            let buttonSize = actionButton.intrinsicContentSize
            actionButton.frame = NSRect(
                x: floor((bounds.width - buttonSize.width) / 2),
                y: currentY,
                width: buttonSize.width,
                height: buttonSize.height
            )
        }
    }
}

private final class ConversationLegacyMenuLoadMoreView: NSView {
    private let intrinsicSize: NSSize
    private let spinner = NSProgressIndicator()

    init(width: CGFloat, height: CGFloat) {
        intrinsicSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }

    override func layout() {
        super.layout()
        spinner.frame = NSRect(
            x: floor((bounds.width - 16) / 2),
            y: floor((bounds.height - 16) / 2),
            width: 16,
            height: 16
        )
    }
}

private final class ConversationLegacyMenuActionButton: NSButton {
    private let actionHandler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        actionHandler = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .inline
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .controlAccentColor
        target = self
        self.action = #selector(handleAction)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    @objc
    private func handleAction() {
        actionHandler()
    }
}

private final class ConversationLegacyMenuIconButton: NSButton {
    private let actionHandler: () -> Void

    init(symbolName: String, toolTip: String? = nil, action: @escaping () -> Void) {
        actionHandler = action
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        isBordered = false
        imageScaling = .scaleProportionallyDown
        contentTintColor = .secondaryLabelColor
        self.toolTip = toolTip
        target = self
        self.action = #selector(handleAction)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    @objc
    private func handleAction() {
        actionHandler()
    }
}

private final class ConversationLegacyMenuRowView: NSView {
    private let intrinsicSize: NSSize
    private let session: SessionListInfo
    private let isSelected: Bool
    private let isStreaming: Bool
    private let style: ConversationListPresentationStyle
    private let onSelect: (SessionListInfo) -> Void
    private let onRename: ((SessionListInfo) -> Void)?
    private let onDelete: ((SessionListInfo) -> Void)?
    private let onShareLink: ((SessionListInfo) -> Void)?

    private let selectionEffectView = NSVisualEffectView()
    private let titleField = NSTextField(labelWithString: "")
    private var streamingIndicator: NSProgressIndicator?
    private var checkmarkView: NSImageView?
    private var shareButton: ConversationLegacyMenuIconButton?
    private var renameButton: ConversationLegacyMenuIconButton?
    private var deleteButton: ConversationLegacyMenuIconButton?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    init(
        width: CGFloat,
        height: CGFloat,
        session: SessionListInfo,
        isSelected: Bool,
        isStreaming: Bool,
        style: ConversationListPresentationStyle,
        onSelect: @escaping (SessionListInfo) -> Void,
        onRename: ((SessionListInfo) -> Void)?,
        onDelete: ((SessionListInfo) -> Void)?,
        onShareLink: ((SessionListInfo) -> Void)?
    ) {
        intrinsicSize = NSSize(width: width, height: height)
        self.session = session
        self.isSelected = isSelected
        self.isStreaming = isStreaming
        self.style = style
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
        self.onShareLink = onShareLink
        super.init(frame: NSRect(origin: .zero, size: intrinsicSize))

        wantsLayer = true

        selectionEffectView.material = .selection
        selectionEffectView.blendingMode = .withinWindow
        selectionEffectView.state = .followsWindowActiveState
        selectionEffectView.isEmphasized = true
        selectionEffectView.isHidden = true
        addSubview(selectionEffectView, positioned: .below, relativeTo: nil)

        titleField.stringValue = conversationDisplayTitle(session)
        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        if isStreaming {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.controlSize = .mini
            indicator.startAnimation(nil)
            addSubview(indicator)
            streamingIndicator = indicator
        }

        if isSelected {
            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            imageView.contentTintColor = .secondaryLabelColor
            imageView.imageScaling = .scaleProportionallyDown
            addSubview(imageView)
            checkmarkView = imageView
        }

        if let onShareLink {
            let button = ConversationLegacyMenuIconButton(
                symbolName: "link",
                toolTip: String(localized: "Copy link")
            ) { [weak self] in
                guard let self else { return }
                onShareLink(self.session)
            }
            addSubview(button)
            shareButton = button
        }

        if let onRename {
            let button = ConversationLegacyMenuIconButton(symbolName: "pencil.and.scribble") { [weak self] in
                guard let self else { return }
                onRename(self.session)
            }
            addSubview(button)
            renameButton = button
        }

        if let onDelete {
            let button = ConversationLegacyMenuIconButton(symbolName: "trash") { [weak self] in
                guard let self else { return }
                onDelete(self.session)
            }
            addSubview(button)
            deleteButton = button
        }

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        intrinsicSize
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        refreshHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        refreshHoverState()
    }

    override func mouseDown(with _: NSEvent) {
        onSelect(session)
    }

    override func layout() {
        super.layout()

        let rowRect = bounds.insetBy(dx: style.rowOuterHorizontalPadding, dy: 0)
        selectionEffectView.frame = rowRect
        selectionEffectView.layer?.cornerRadius = style.rowCornerRadius

        let contentRect = rowRect.insetBy(dx: style.rowHorizontalPadding, dy: style.rowVerticalPadding)
        let iconSize: CGFloat = 16
        var leadingX = contentRect.minX

        if let streamingIndicator {
            streamingIndicator.frame = NSRect(
                x: leadingX,
                y: floor(contentRect.midY - iconSize / 2),
                width: iconSize,
                height: iconSize
            )
            leadingX += iconSize + 8
        }

        var trailingX = contentRect.maxX

        if isHovered {
            for button in [deleteButton, renameButton, shareButton].compactMap(\.self) {
                button.frame = NSRect(
                    x: trailingX - iconSize,
                    y: floor(contentRect.midY - iconSize / 2),
                    width: iconSize,
                    height: iconSize
                )
                trailingX -= iconSize + 4
            }
        } else if let checkmarkView, isSelected {
            checkmarkView.frame = NSRect(
                x: trailingX - 12,
                y: floor(contentRect.midY - 12 / 2),
                width: 12,
                height: 12
            )
            trailingX -= 16
        }

        titleField.frame = NSRect(
            x: leadingX,
            y: floor(contentRect.midY - 16 / 2),
            width: max(24, trailingX - leadingX),
            height: 16
        )
    }

    func refreshHoverState() {
        guard let window else {
            isHovered = false
            return
        }

        let locationInWindow = window.mouseLocationOutsideOfEventStream
        let locationInView = convert(locationInWindow, from: nil)
        isHovered = bounds.contains(locationInView)
    }

    private func updateAppearance() {
        titleField.textColor = isHovered ? .selectedMenuItemTextColor : .labelColor
        selectionEffectView.isHidden = !isHovered
        checkmarkView?.isHidden = !isSelected || isHovered
        checkmarkView?.contentTintColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor

        for button in [shareButton, renameButton, deleteButton].compactMap(\.self) {
            button.isHidden = !isHovered
            button.contentTintColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        }

        needsLayout = true
        needsDisplay = true
    }
}
