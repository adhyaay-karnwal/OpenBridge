import AppKit

/// A simple, non-interactive label view that doesn't accept first responder.
/// Unlike NSTextField, this view will not interfere with focus management.
@MainActor
final class NSLabel: NSView {
    // MARK: - Properties

    private var _text: String = ""
    private var _backgroundColor: NSColor = .clear
    private var drawingRect: NSRect = .zero

    var text: String {
        get { _text }
        set {
            _text = newValue
            setNeedsLayoutUpdate()
        }
    }

    var font: NSFont = .labelFont(ofSize: 12) {
        didSet { setNeedsLayoutUpdate() }
    }

    var textColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    var backgroundColor: NSColor {
        get { _backgroundColor }
        set {
            _backgroundColor = newValue
            needsDisplay = true
        }
    }

    var numberOfLines: Int = 1 {
        didSet { setNeedsLayoutUpdate() }
    }

    var textAlignment: NSTextAlignment = .left {
        didSet { setNeedsLayoutUpdate() }
    }

    var lineBreakMode: NSLineBreakMode = .byTruncatingTail {
        didSet { setNeedsLayoutUpdate() }
    }

    var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet { setNeedsLayoutUpdate() }
    }

    var cursor: NSCursor? {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Layout & Drawing

    override var isOpaque: Bool {
        _backgroundColor.alphaComponent == 1.0
    }

    override var baselineOffsetFromBottom: CGFloat {
        computedDrawingRect.origin.y
    }

    override var intrinsicContentSize: NSSize {
        computedDrawingRect.size
    }

    override func invalidateIntrinsicContentSize() {
        drawingRect = .zero
        super.invalidateIntrinsicContentSize()
    }

    override func draw(_: NSRect) {
        let bounds = bounds
        let drawRect = NSRect(origin: computedDrawingRect.origin, size: bounds.size)

        _backgroundColor.setFill()
        bounds.fill(using: .sourceOver)

        if !_text.isEmpty {
            attributedText.draw(with: drawRect, options: drawingOptions)
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let cursor else { return }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        false
    }

    // MARK: - Private

    private func setNeedsLayoutUpdate() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var attributedText: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = lineBreakMode

        return NSAttributedString(
            string: _text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .backgroundColor: _backgroundColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private var computedDrawingRect: NSRect {
        if drawingRect == .zero, !_text.isEmpty {
            let size = NSSize(width: preferredMaxLayoutWidth, height: 0)
            let rect = attributedText.boundingRect(with: size, options: drawingOptions)
            drawingRect = NSRect(
                x: ceil(-rect.origin.x),
                y: ceil(-rect.origin.y),
                width: ceil(rect.size.width),
                height: ceil(rect.size.height)
            )
        }
        return drawingRect
    }

    private var drawingOptions: NSString.DrawingOptions {
        var options: NSString.DrawingOptions = .usesFontLeading
        if numberOfLines != 1 {
            options.insert(.usesLineFragmentOrigin)
        }
        return options
    }
}
