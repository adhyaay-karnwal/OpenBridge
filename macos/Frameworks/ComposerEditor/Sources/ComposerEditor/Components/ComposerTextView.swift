import AppKit

@MainActor
class ComposerTextView: NSTextView {
    var onCompositionStateChanged: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onPaste: ((NSPasteboard) -> Bool)?
    var onDrop: ((NSPasteboard) -> Bool)?

    // MARK: - Paste Handling

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), onPaste != nil {
            let pasteboard = NSPasteboard.general
            if pasteboard.hasSupportedChatPasteContent() {
                return true
            }
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let handler = onPaste, handler(pasteboard) {
            return
        }
        super.paste(sender)
    }

    // MARK: - Focus Management

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onFocusChange?(false) }
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceForCurrentTraits()
    }

    // MARK: - Input Method (IME)

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionStateChanged?()
    }

    // MARK: - Private

    private func updateAppearanceForCurrentTraits() {
        textColor = .labelColor
        insertionPointColor = .labelColor

        var updatedTypingAttributes = typingAttributes
        updatedTypingAttributes[.foregroundColor] = NSColor.labelColor
        typingAttributes = updatedTypingAttributes

        refreshCommandTokenAppearance()
    }

    private func refreshCommandTokenAppearance() {
        guard let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        var didUpdate = false
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, _, _ in
            if let attachment = value as? CommandTokenAttachment {
                attachment.refreshAppearance()
                didUpdate = true
            }
        }

        if didUpdate {
            textStorage.edited(.editedAttributes, range: fullRange, changeInLength: 0)
        }
    }
}
