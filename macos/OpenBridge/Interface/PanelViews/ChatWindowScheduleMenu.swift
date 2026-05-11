import AppKit
import Combine
import Foundation
import OSLog

private let scheduleMenuRowWidth: CGFloat = 360
private let scheduleMenuMaxHeight: CGFloat = 320
private let scheduleMenuRowSpacing: CGFloat = 2
private let scheduleMenuVerticalInset: CGFloat = 0
private let scheduleMenuRowHorizontalInset: CGFloat = 4
private let scheduleMenuRowHeight: CGFloat = 22
private let scheduleMenuRowCornerRadius: CGFloat = 6
private let scheduleMenuRowContentInsetHorizontal: CGFloat = 8
private let scheduleMenuRowContentInsetVertical: CGFloat = 1
private let scheduleMenuActionButtonSize: CGFloat = 16
private let scheduleMenuIconSize: CGFloat = 14
private let scheduleMenuTextLineHeight: CGFloat = 16
private let scheduleMenuLogger = Logger(subsystem: "openbridge", category: "ChatWindowScheduleMenu")

@MainActor
func makeScheduleMenuItem(items: [ScheduleStore.Item]) -> NSMenuItem {
    let item = NSMenuItem(
        title: String(localized: "Schedule"),
        action: nil,
        keyEquivalent: ""
    )
    item.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
        ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)

    let sortedItems = items.sorted { lhs, rhs in
        lhs.createdAt > rhs.createdAt
    }

    let submenu = NSMenu()
    submenu.minimumWidth = scheduleMenuRowWidth
    let handler = ScheduleMenuActionHandler()
    let contentItem = NSMenuItem()
    contentItem.view = ScheduleMenuHostingView(items: sortedItems, handler: handler)
    submenu.addItem(contentItem)

    item.submenu = submenu
    objc_setAssociatedObject(item, "scheduleHandler", handler, .OBJC_ASSOCIATION_RETAIN)
    return item
}

private final class ScheduleMenuHostingView: NSView {
    private let handler: ScheduleMenuActionHandler
    private let scrollView = NSScrollView()
    private let documentView = FlippedScheduleMenuContentView()
    private let stackView = NSStackView()
    private var cancellables: Set<AnyCancellable> = []

    init(items: [ScheduleStore.Item], handler: ScheduleMenuActionHandler) {
        self.handler = handler
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = scheduleMenuRowSpacing
        documentView.addSubview(stackView)

        ScheduleStore.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh(items: items)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func refresh(items: [ScheduleStore.Item] = ScheduleStore.shared.items) {
        let sortedItems = items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if sortedItems.isEmpty {
            let label = NSTextField(labelWithString: String(localized: "No schedules"))
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(label)
        } else {
            for item in sortedItems {
                stackView.addArrangedSubview(
                    ScheduleMenuRowView(
                        item: item,
                        handler: handler,
                        hostingView: self
                    )
                )
            }
        }

        let contentHeight = stackView.fittingSize.height + scheduleMenuVerticalInset * 2
        let visibleHeight = min(contentHeight, scheduleMenuMaxHeight)

        frame = NSRect(x: 0, y: 0, width: scheduleMenuRowWidth, height: visibleHeight)
        scrollView.frame = bounds
        scrollView.hasVerticalScroller = contentHeight > scheduleMenuMaxHeight
        documentView.frame = NSRect(x: 0, y: 0, width: scheduleMenuRowWidth, height: contentHeight)
        stackView.frame = NSRect(
            x: scheduleMenuRowHorizontalInset,
            y: scheduleMenuVerticalInset,
            width: scheduleMenuRowWidth - scheduleMenuRowHorizontalInset * 2,
            height: stackView.fittingSize.height
        )
        needsLayout = true
        needsDisplay = true
    }
}

private final class ScheduleMenuRowView: NSView {
    private let item: ScheduleStore.Item
    private let handler: ScheduleMenuActionHandler
    private weak var hostingView: ScheduleMenuHostingView?

    private let selectionEffectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let pauseButton = NSButton()
    private let deleteButton = NSButton()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    init(item: ScheduleStore.Item, handler: ScheduleMenuActionHandler, hostingView: ScheduleMenuHostingView) {
        self.item = item
        self.handler = handler
        self.hostingView = hostingView
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: scheduleMenuRowWidth - scheduleMenuRowHorizontalInset * 2,
            height: scheduleMenuRowHeight
        ))

        wantsLayer = true
        layer?.cornerRadius = scheduleMenuRowCornerRadius
        layer?.masksToBounds = true

        selectionEffectView.material = .selection
        selectionEffectView.blendingMode = .withinWindow
        selectionEffectView.state = .followsWindowActiveState
        selectionEffectView.isEmphasized = true
        selectionEffectView.isHidden = true
        addSubview(selectionEffectView, positioned: .below, relativeTo: nil)

        iconView.image = NSImage(systemSymbolName: scheduleSymbolName(for: item), accessibilityDescription: nil)
        iconView.contentTintColor = scheduleSymbolColor(for: item)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleField.stringValue = item.title
        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        detailField.stringValue = item.subtitle
        detailField.font = .systemFont(ofSize: 12)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.alignment = .left
        addSubview(detailField)

        if let pauseSymbolName = schedulePauseButtonSymbolName(for: item) {
            pauseButton.image = NSImage(
                systemSymbolName: pauseSymbolName,
                accessibilityDescription: schedulePauseButtonLabel(for: item)
            )
            pauseButton.isBordered = false
            pauseButton.contentTintColor = .secondaryLabelColor
            pauseButton.target = self
            pauseButton.action = #selector(handlePause)
            pauseButton.toolTip = schedulePauseButtonLabel(for: item)
            addSubview(pauseButton)
        }

        deleteButton.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: String(localized: "Delete schedule")
        )
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        deleteButton.toolTip = String(localized: "Delete schedule")
        addSubview(deleteButton)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: scheduleMenuRowWidth - scheduleMenuRowHorizontalInset * 2,
            height: scheduleMenuRowHeight
        )
    }

    override func layout() {
        super.layout()

        selectionEffectView.frame = bounds

        let contentRect = bounds.insetBy(
            dx: scheduleMenuRowContentInsetHorizontal,
            dy: scheduleMenuRowContentInsetVertical
        )
        let centerY = contentRect.midY
        let iconY = floor(centerY - scheduleMenuIconSize / 2)
        let titleHeight = scheduleMenuTextLineHeight
        let detailHeight = scheduleMenuTextLineHeight
        let controlY = floor(centerY - scheduleMenuActionButtonSize / 2)
        let titleY = floor(centerY - titleHeight / 2)
        let detailY = floor(centerY - detailHeight / 2)

        iconView.frame = NSRect(
            x: contentRect.minX,
            y: iconY,
            width: scheduleMenuIconSize,
            height: scheduleMenuIconSize
        )

        var trailingX = contentRect.maxX
        deleteButton.frame = NSRect(
            x: trailingX - scheduleMenuActionButtonSize,
            y: controlY,
            width: scheduleMenuActionButtonSize,
            height: scheduleMenuActionButtonSize
        )
        trailingX -= scheduleMenuActionButtonSize + 4

        if pauseButton.superview != nil {
            pauseButton.frame = NSRect(
                x: trailingX - scheduleMenuActionButtonSize,
                y: controlY,
                width: scheduleMenuActionButtonSize,
                height: scheduleMenuActionButtonSize
            )
            trailingX -= scheduleMenuActionButtonSize + 4
        }

        let titleX = iconView.frame.maxX + 8
        let minimumDetailWidth: CGFloat = 12
        let maximumTitleWidth = max(40, trailingX - titleX - 8 - minimumDetailWidth)
        let titleWidth = min(
            measuredTextWidth(titleField.stringValue, font: titleField.font ?? .systemFont(ofSize: 13)),
            maximumTitleWidth
        )
        titleField.frame = NSRect(
            x: titleX,
            y: titleY,
            width: max(40, titleWidth),
            height: titleHeight
        )

        detailField.frame = NSRect(
            x: titleField.frame.maxX + 8,
            y: detailY,
            width: max(24, trailingX - titleField.frame.maxX - 8),
            height: detailHeight
        )
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
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    @objc
    private func handlePause() {
        handler.togglePause(item, hostingView: hostingView)
    }

    @objc
    private func handleDelete() {
        handler.delete(item, hostingView: hostingView)
    }

    private func updateAppearance() {
        titleField.textColor = isHovered ? .selectedMenuItemTextColor : .labelColor
        detailField.textColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        iconView.contentTintColor = isHovered ? .selectedMenuItemTextColor : scheduleSymbolColor(for: item)
        pauseButton.contentTintColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        deleteButton.contentTintColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        selectionEffectView.isHidden = !isHovered
    }
}

private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width) + 16
}

private final class ScheduleMenuActionHandler: NSObject {
    func togglePause(_ item: ScheduleStore.Item, hostingView: ScheduleMenuHostingView?) {
        Task { @MainActor in
            do {
                if item.isPaused {
                    try await ScheduleStore.shared.resume(scheduleID: item.scheduleID)
                } else {
                    try await ScheduleStore.shared.pause(scheduleID: item.scheduleID)
                }
                hostingView?.refresh()
            } catch {
                presentActionError(error)
            }
        }
    }

    func delete(_ item: ScheduleStore.Item, hostingView: ScheduleMenuHostingView?) {
        Task { @MainActor in
            scheduleMenuLogger.notice("delete tapped scheduleID=\(item.scheduleID, privacy: .public)")
            let displayTitle = item.title.isEmpty ? String(localized: "Untitled") : item.title
            let alert = NSAlert()
            alert.messageText = String(localized: "Delete schedule")
            alert.informativeText = String(
                format: String(localized: "Are you sure you want to delete \"%@\"? This action cannot be undone."),
                displayTitle
            )
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Delete"))
            alert.addButton(withTitle: String(localized: "Cancel"))

            let runDelete: () -> Void = { [item] in
                scheduleMenuLogger.notice("delete confirmed scheduleID=\(item.scheduleID, privacy: .public)")
                _ = Task { @MainActor in
                    do {
                        try await ScheduleStore.shared.delete(scheduleID: item.scheduleID)
                        scheduleMenuLogger.notice("delete succeeded scheduleID=\(item.scheduleID, privacy: .public)")
                        hostingView?.refresh()
                    } catch {
                        scheduleMenuLogger.error("delete failed scheduleID=\(item.scheduleID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                        self.presentActionError(error)
                    }
                }
            }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()
                scheduleMenuLogger.notice("delete modal response=\(response.rawValue, privacy: .public) scheduleID=\(item.scheduleID, privacy: .public)")
                if response == .alertFirstButtonReturn {
                    runDelete()
                }
            }
        }
    }

    @MainActor
    private func presentActionError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}

private func scheduleSymbolName(for item: ScheduleStore.Item) -> String {
    if item.hasError {
        return "exclamationmark.triangle.fill"
    }
    if item.isRunningNow {
        return "progress.indicator"
    }
    if item.isPaused {
        return "pause.circle"
    }
    return item.nextRunAt == nil ? "checkmark.circle.fill" : "timer"
}

private func scheduleSymbolColor(for item: ScheduleStore.Item) -> NSColor {
    if item.hasError {
        return .systemRed
    }
    if item.isRunningNow {
        return .labelColor
    }
    if item.nextRunAt == nil {
        return .secondaryLabelColor
    }
    return .labelColor
}

private func schedulePauseButtonSymbolName(for item: ScheduleStore.Item) -> String? {
    if item.nextRunAt == nil, !item.isPaused {
        return nil
    }
    return item.isPaused ? "play.circle" : "pause.circle"
}

private func schedulePauseButtonLabel(for item: ScheduleStore.Item) -> String {
    item.isPaused ? String(localized: "Resume schedule") : String(localized: "Pause schedule")
}

private final class FlippedScheduleMenuContentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
