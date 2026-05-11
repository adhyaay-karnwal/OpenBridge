import AppKit
import SwiftUI

/// a text editor that grows its height to fit the content
///
/// - `maxLines` controls the maximum height, and scrolling is enabled when the content exceeds the limit
/// - supports custom placeholder text and font size
/// - provides `onSend` callback to respond to ⌘ + Enter shortcut
/// - optional autofocus and focus binding enable external focus management
/// - supports command menu triggered by "/" character when commandDataSource is provided
public struct VerticalExpendedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var fontWeight: NSFont.Weight
    var minLines: Int
    var maxLines: Int
    var onSend: ((String) -> Void)?
    var onPaste: ((NSPasteboard) -> Bool)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var isEditable: Bool
    var autoFocus: Bool
    var focusBinding: Binding<Bool>?
    var commandDataSource: CommandMenuDataSource?
    var onCommandSelected: ((CommandItem) -> Void)?

    public init(
        text: Binding<String>,
        placeholder: String = "",
        fontSize: CGFloat = 14,
        fontWeight: NSFont.Weight = .regular,
        minLines: Int = 1,
        maxLines: Int = 5,
        onSend: ((String) -> Void)? = nil,
        onPaste: ((NSPasteboard) -> Bool)? = nil,
        onDrop: ((NSPasteboard) -> Bool)? = nil,
        isEditable: Bool = true,
        autoFocus: Bool = false,
        focusBinding: Binding<Bool>? = nil,
        commandDataSource: CommandMenuDataSource? = nil,
        onCommandSelected: ((CommandItem) -> Void)? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        let normalizedMinLines = max(1, minLines)
        self.minLines = normalizedMinLines
        self.maxLines = max(normalizedMinLines, max(1, maxLines))
        self.onSend = onSend
        self.onPaste = onPaste
        self.onDrop = onDrop
        self.isEditable = isEditable
        self.autoFocus = autoFocus
        self.focusBinding = focusBinding
        self.commandDataSource = commandDataSource
        self.onCommandSelected = onCommandSelected
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> GrowingTextContainerView {
        let containerView = GrowingTextContainerView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        containerView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        containerView.setContentCompressionResistancePriority(.required, for: .vertical)
        containerView.updateFont(size: fontSize, weight: fontWeight)
        containerView.updatePlaceholder(placeholder)
        containerView.minLines = minLines
        containerView.maxLines = maxLines
        containerView.setText(text)
        containerView.onSend = { [weak coordinator = context.coordinator] text in
            coordinator?.handleSend(text: text)
        }
        containerView.onPaste = onPaste
        containerView.onDrop = onDrop
        containerView.commandDataSource = commandDataSource
        containerView.onCommandSelected = onCommandSelected
        context.coordinator.attach(to: containerView)
        containerView.isEditable = isEditable
        containerView.refreshHeight(force: true)
        context.coordinator.scheduleFocusEvaluation(on: containerView)
        return containerView
    }

    public func updateNSView(_ nsView: GrowingTextContainerView, context: Context) {
        context.coordinator.parent = self
        nsView.updateFont(size: fontSize, weight: fontWeight)
        nsView.updatePlaceholder(placeholder)
        nsView.minLines = minLines
        nsView.maxLines = maxLines
        nsView.onSend = { [weak coordinator = context.coordinator] text in
            coordinator?.handleSend(text: text)
        }
        nsView.onPaste = onPaste
        nsView.onDrop = onDrop
        nsView.commandDataSource = commandDataSource
        nsView.onCommandSelected = onCommandSelected
        context.coordinator.syncTextIfNeeded(text)
        nsView.isEditable = isEditable
        nsView.refreshHeight(force: false)
        context.coordinator.updateFocusState(on: nsView)
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VerticalExpendedTextField
        weak var container: GrowingTextContainerView?
        private var isUpdatingFromTextView = false
        private var hasAppliedAutoFocus = false
        private var isUpdatingFocusBinding = false

        init(parent: VerticalExpendedTextField) {
            self.parent = parent
        }

        func attach(to container: GrowingTextContainerView) {
            self.container = container
            container.textView.delegate = self
            hasAppliedAutoFocus = false
            container.onFocusChange = { [weak self] isFocused in
                self?.handleFocusChange(isFocused)
            }
        }

        func syncTextIfNeeded(_ newValue: String) {
            guard let container else { return }
            guard container.textView.string != newValue else { return }

            // Don't sync text while user is composing with IME (e.g., Chinese input)
            // This prevents breaking the IME composition state during view updates
            guard !container.textView.hasMarkedText() else { return }

            isUpdatingFromTextView = true
            container.textView.string = newValue
            container.refreshHeight(force: true)
            container.updatePlaceholderVisibility()
            isUpdatingFromTextView = false
        }

        func handleSend(text: String) {
            parent.onSend?(text)
        }

        func scheduleFocusEvaluation(on container: GrowingTextContainerView) {
            DispatchQueue.main.async { [weak self, weak container] in
                guard let self, let container else { return }
                updateFocusState(on: container)
            }
        }

        func updateFocusState(on container: GrowingTextContainerView) {
            if let focusBinding = parent.focusBinding {
                let desiredFocus = focusBinding.wrappedValue && parent.isEditable
                if desiredFocus {
                    container.focusTextView()
                } else {
                    container.blurTextView()
                }

                if focusBinding.wrappedValue != desiredFocus {
                    isUpdatingFocusBinding = true
                    focusBinding.wrappedValue = desiredFocus
                    isUpdatingFocusBinding = false
                }
            } else if parent.autoFocus {
                applyInitialFocusIfNeeded(on: container)
            }
        }

        private func applyInitialFocusIfNeeded(on container: GrowingTextContainerView) {
            guard parent.isEditable else { return }
            guard !hasAppliedAutoFocus else { return }
            hasAppliedAutoFocus = true
            container.focusTextView()
        }

        private func handleFocusChange(_ isFocused: Bool) {
            guard let focusBinding = parent.focusBinding else { return }
            guard !isUpdatingFocusBinding else { return }
            guard focusBinding.wrappedValue != isFocused else { return }
            isUpdatingFocusBinding = true
            focusBinding.wrappedValue = isFocused
            isUpdatingFocusBinding = false
        }

        public func textDidChange(_: Notification) {
            guard !isUpdatingFromTextView, let container else { return }
            parent.text = container.textView.string
            container.refreshHeight(force: true)
            container.updatePlaceholderVisibility()
        }
    }
}

// MARK: - AppKit Backing View

@MainActor
public final class GrowingTextContainerView: NSView {
    // MARK: - Subviews

    fileprivate let scrollView: NSScrollView
    fileprivate let textView: GrowingNSTextView
    private let placeholderLabel: NSLabel

    // MARK: - Command Menu

    private let menuController: CommandMenuController
    private var triggerLocation: Int?
    private let triggerCharacter: Character = "/"

    // MARK: - Callbacks

    var onSend: ((String) -> Void)? {
        didSet { setupTextViewSendHandler() }
    }

    var onPaste: ((NSPasteboard) -> Bool)? {
        didSet { textView.onPaste = onPaste }
    }

    var onDrop: ((NSPasteboard) -> Bool)? {
        didSet { textView.onDrop = onDrop }
    }

    private func setupTextViewSendHandler() {
        textView.onSend = { [weak self] _ in
            guard let self, let onSend else { return }
            let plainText = getPlainTextContent()
            onSend(plainText)
        }
    }

    var onFocusChange: ((Bool) -> Void)?
    var onCommandSelected: ((CommandItem) -> Void)?

    weak var commandDataSource: CommandMenuDataSource? {
        didSet { menuController.dataSource = commandDataSource }
    }

    // MARK: - Configuration

    var minLines: Int = 1 {
        didSet {
            if minLines < 1 {
                minLines = 1
                return
            }
            if minLines > maxLines {
                maxLines = minLines
            }
            if minLines != oldValue {
                refreshHeight(force: true)
            }
        }
    }

    var maxLines: Int = 5 {
        didSet {
            if maxLines < 1 {
                maxLines = 1
                return
            }
            if maxLines < minLines {
                maxLines = minLines
                return
            }
            if maxLines != oldValue {
                refreshHeight(force: true)
            }
        }
    }

    var isEditable: Bool {
        didSet {
            textView.isEditable = isEditable
            if !isEditable {
                blurTextView()
            }
        }
    }

    // MARK: - Internal State

    private var cachedHeight: CGFloat
    private var lastKnownWidth: CGFloat = 0
    private var placeholderText: String = ""
    private var font: NSFont
    private var fontWeight: NSFont.Weight = .regular
    private let verticalInset: CGFloat = 8
    private var isInLayout: Bool = false
    private var hasScheduledRefresh: Bool = false
    private var lastSafeAreaOverrides: (scroll: NSEdgeInsets, text: NSEdgeInsets)?
    private var pendingFocusRequest: Bool = false

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        let scrollView = NSScrollView(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = GrowingNSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.allowsUndo = true
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.insertionPointColor = .labelColor

        let placeholderLabel = NSLabel(frame: .zero)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textColor = NSColor.placeholderTextColor
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.numberOfLines = 0
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.cursor = .iBeam

        scrollView.documentView = textView

        self.scrollView = scrollView
        self.textView = textView
        self.placeholderLabel = placeholderLabel
        menuController = CommandMenuController()
        font = NSFont.systemFont(ofSize: 14)
        cachedHeight = ceil(CGFloat(minLines) * font.defaultLineHeight + verticalInset * 2)
        placeholderLabel.font = font
        isEditable = true
        super.init(frame: frameRect)

        setupMenuController()
        setupTextViewCallbacks()

        textView.onCompositionStateChanged = { [weak self] in
            self?.updatePlaceholderVisibility()
        }
        textView.onFocusChange = { [weak self] isFocused in
            self?.handleFocusChange(isFocused)
        }

        wantsLayer = false
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 2),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -2),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: verticalInset),
        ])
        updatePlaceholderVisibility()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight)
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else { return nil }
        if hitView === placeholderLabel {
            return textView
        }
        return hitView
    }

    override public func layout() {
        isInLayout = true
        super.layout()
        applySafeAreaOverridesIfNeeded()
        refreshHeight(force: false)
        isInLayout = false
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySafeAreaOverridesIfNeeded()
    }

    // MARK: - Text & Font

    func setText(_ newValue: String) {
        textView.string = newValue
        updatePlaceholderVisibility()
    }

    private func applySafeAreaOverridesIfNeeded() {
        let overrides = computeSafeAreaOverrides()
        if let lastSafeAreaOverrides,
           lastSafeAreaOverrides.scroll.isEqualTo(overrides.scroll),
           lastSafeAreaOverrides.text.isEqualTo(overrides.text)
        {
            return
        }
        scrollView.additionalSafeAreaInsets = overrides.scroll
        textView.additionalSafeAreaInsets = overrides.text
        lastSafeAreaOverrides = overrides
    }

    @available(macOS 11.0, *)
    private func computeSafeAreaOverrides() -> (scroll: NSEdgeInsets, text: NSEdgeInsets) {
        (ignoreSafeAreaInsets(for: scrollView), ignoreSafeAreaInsets(for: textView))
    }

    @available(macOS 11.0, *)
    private func ignoreSafeAreaInsets(for view: NSView) -> NSEdgeInsets {
        let insets = view.safeAreaInsets
        return NSEdgeInsets(top: -insets.top, left: -insets.left, bottom: -insets.bottom, right: -insets.right)
    }

    private var currentParagraphStyle: NSParagraphStyle {
        textView.defaultParagraphStyle ?? NSParagraphStyle.default
    }

    func updateFont(size: CGFloat, weight: NSFont.Weight) {
        let constrainedSize = max(size, 10)
        guard abs(font.pointSize - constrainedSize) > .ulpOfOne || fontWeight != weight else { return }
        fontWeight = weight
        font = NSFont.systemFont(ofSize: constrainedSize, weight: weight)
        textView.font = font
        textView.typingAttributes[.font] = font

        placeholderLabel.font = font
        updatePlaceholder(placeholderText)
        refreshHeight(force: true)
    }

    func updatePlaceholder(_ text: String) {
        placeholderText = text
        placeholderLabel.text = text
        updatePlaceholderVisibility()
        placeholderLabel.cursor = .iBeam
    }

    func updatePlaceholderVisibility() {
        let hasComposingText = textView.hasMarkedText()
        let shouldShow = textView.string.isEmpty && !hasComposingText && !placeholderText.isEmpty
        placeholderLabel.isHidden = !shouldShow
        placeholderLabel.alphaValue = shouldShow ? 1 : 0
    }

    // MARK: - Focus

    var isTextViewFocused: Bool {
        textView.window?.firstResponder === textView
    }

    func focusTextView() {
        guard isEditable else {
            pendingFocusRequest = false
            return
        }

        guard let targetWindow = window ?? textView.window else {
            scheduleFocusRetry()
            return
        }

        if targetWindow.firstResponder === textView {
            pendingFocusRequest = false
            return
        }

        if targetWindow.makeFirstResponder(textView) == false {
            scheduleFocusRetry()
        } else {
            pendingFocusRequest = false
        }
    }

    func blurTextView() {
        pendingFocusRequest = false
        guard let targetWindow = window ?? textView.window else { return }
        guard targetWindow.firstResponder === textView else { return }
        targetWindow.makeFirstResponder(nil)
    }

    private func scheduleFocusRetry() {
        guard !pendingFocusRequest else { return }
        pendingFocusRequest = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pendingFocusRequest = false
            focusTextView()
        }
    }

    private func handleFocusChange(_ isFocused: Bool) {
        if isFocused {
            pendingFocusRequest = false
        }
        onFocusChange?(isFocused)
    }

    // MARK: - Command Menu

    private func setupMenuController() {
        menuController.onCommandSelected = { [weak self] command in
            guard let self else { return }
            if let onCommandSelected {
                clearTriggerText()
                onCommandSelected(command)
            } else {
                insertCommandToken(command)
            }
        }
        menuController.onMenuDismissed = { [weak self] in
            self?.cancelTrigger()
        }
    }

    private func clearTriggerText() {
        guard let triggerLoc = triggerLocation else { return }
        let cursorLocation = textView.selectedRange().location
        let rangeToReplace = NSRange(location: triggerLoc, length: cursorLocation - triggerLoc)
        if textView.shouldChangeText(in: rangeToReplace, replacementString: "") {
            textView.textStorage?.replaceCharacters(in: rangeToReplace, with: "")
            textView.didChangeText()
        }
        triggerLocation = nil
    }

    private func setupTextViewCallbacks() {
        textView.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        textView.onTextDidChange = { [weak self] in
            self?.checkForTrigger()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard menuController.isMenuVisible else { return false }
        return menuController.handleKeyEvent(event)
    }

    private func checkForTrigger() {
        guard commandDataSource != nil else { return }

        let text = textView.string
        let cursorLocation = textView.selectedRange().location

        if let triggerLoc = triggerLocation, menuController.isMenuVisible {
            guard cursorLocation > triggerLoc else { cancelTrigger(); return }
            let queryStart = String.Index(utf16Offset: triggerLoc + 1, in: text)
            let queryEnd = String.Index(utf16Offset: min(cursorLocation, text.utf16.count), in: text)
            guard queryStart <= queryEnd else { return }
            menuController.updateQuery(String(text[queryStart ..< queryEnd]))
            return
        }

        guard cursorLocation > 0 else { return }
        let charIndex = cursorLocation - 1
        let char = text[String.Index(utf16Offset: charIndex, in: text)]
        guard char == triggerCharacter else { return }

        let isAtLineStart = charIndex == 0 || {
            let prev = text[String.Index(utf16Offset: charIndex - 1, in: text)]
            return prev.isWhitespace || prev.isNewline
        }()
        guard isAtLineStart else { return }

        triggerLocation = charIndex
        menuController.showMenu(in: textView, triggerRange: NSRange(location: charIndex, length: 1))
    }

    private func cancelTrigger() {
        triggerLocation = nil
        menuController.hideMenu()
    }

    private func insertCommandToken(_ command: CommandItem) {
        guard let triggerLoc = triggerLocation else { return }

        let selectedRange = textView.selectedRange()
        let rangeToReplace = NSRange(location: triggerLoc, length: selectedRange.location - triggerLoc)

        let attachment = CommandTokenAttachment(command: command)
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttribute(.paragraphStyle, value: currentParagraphStyle, range: fullRange)

        let spaceString = NSAttributedString(string: " ", attributes: [
            .font: font,
            .paragraphStyle: currentParagraphStyle,
        ])
        attachmentString.append(spaceString)

        if textView.shouldChangeText(in: rangeToReplace, replacementString: attachmentString.string) {
            textView.textStorage?.replaceCharacters(in: rangeToReplace, with: attachmentString)
            textView.didChangeText()

            let newLocation = triggerLoc + attachmentString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }

        triggerLocation = nil
    }

    /// Get plain text with command tokens converted to their text representation
    func getPlainTextContent() -> String {
        convertCommandsToPlainText(textView.attributedString())
    }

    // MARK: - Height Calculation

    func refreshHeight(force: Bool) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

        let effectiveWidth = max(bounds.width, 0)
        guard effectiveWidth > 0 else {
            scheduleRefreshIfNeeded(force: force)
            return
        }

        hasScheduledRefresh = false

        if force || abs(effectiveWidth - lastKnownWidth) > 0.5 {
            lastKnownWidth = effectiveWidth
            textContainer.containerSize = NSSize(width: effectiveWidth, height: .greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
        }

        layoutManager.ensureLayout(for: textContainer)

        let baseLineHeight = layoutManager.defaultLineHeight(for: font)
        let minHeight = ceil(CGFloat(max(1, minLines)) * baseLineHeight + verticalInset * 2)
        let maxAllowedHeight = ceil(CGFloat(max(1, maxLines)) * baseLineHeight + verticalInset * 2)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height + verticalInset * 2)
        let targetHeight = textView.string.isEmpty ? minHeight : min(max(usedHeight, minHeight), maxAllowedHeight)

        if abs(targetHeight - cachedHeight) > 0.5 {
            cachedHeight = targetHeight
            if isInLayout {
                DispatchQueue.main.async { [weak self] in self?.invalidateIntrinsicContentSize() }
            } else {
                invalidateIntrinsicContentSize()
            }
        }

        let needsScrolling = usedHeight > maxAllowedHeight + 0.5
        if scrollView.hasVerticalScroller != needsScrolling {
            scrollView.hasVerticalScroller = needsScrolling
        }
        scrollView.verticalScrollElasticity = needsScrolling ? .automatic : .none
        updatePlaceholderVisibility()
    }

    private func scheduleRefreshIfNeeded(force: Bool) {
        guard !hasScheduledRefresh else { return }
        hasScheduledRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            hasScheduledRefresh = false
            refreshHeight(force: force)
        }
    }
}

// MARK: - NSTextView Subclass

@MainActor
final class GrowingNSTextView: ComposerTextView {
    var onSend: ((String) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onTextDidChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76

        guard isReturnKey else { super.keyDown(with: event); return }
        guard !flags.contains(.command), !flags.contains(.shift) else { insertNewline(nil); return }
        guard !hasMarkedText() else { super.keyDown(with: event); return }
        guard let onSend else { super.keyDown(with: event); return }
        onSend(string)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextDidChange?()
    }

    private func hasFileOrImageDrag(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(where: { $0 == .fileURL || $0 == .png || $0 == .tiff }) ?? false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileOrImageDrag(sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        guard onDrop != nil else { return super.draggingEntered(sender) }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileOrImageDrag(sender.draggingPasteboard) else { return super.draggingUpdated(sender) }
        guard onDrop != nil else { return super.draggingUpdated(sender) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let sender, hasFileOrImageDrag(sender.draggingPasteboard) else {
            super.draggingExited(sender)
            return
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard hasFileOrImageDrag(pasteboard) else { return super.performDragOperation(sender) }
        guard let onDrop else { return super.performDragOperation(sender) }
        return onDrop(pasteboard)
    }
}
