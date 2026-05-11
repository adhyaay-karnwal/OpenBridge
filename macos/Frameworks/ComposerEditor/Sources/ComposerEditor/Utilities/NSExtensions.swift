import AppKit

// MARK: - NSFont Extensions

extension NSFont {
    /// Calculate the default line height for this font
    var defaultLineHeight: CGFloat {
        let layoutManager = NSLayoutManager()
        return layoutManager.defaultLineHeight(for: self)
    }
}

// MARK: - NSEdgeInsets Extensions

extension NSEdgeInsets {
    /// Check if two NSEdgeInsets are equal
    func isEqualTo(_ other: NSEdgeInsets) -> Bool {
        top == other.top &&
            left == other.left &&
            bottom == other.bottom &&
            right == other.right
    }
}

// MARK: - NSPasteboard Extensions

extension NSPasteboard {
    func hasSupportedChatPasteContent() -> Bool {
        guard let types else { return false }
        return types.contains(where: {
            $0 == .png
                || $0 == .tiff
                || $0 == .fileURL
                || $0 == .string
                || $0 == .rtf
                || $0 == .rtfd
                || $0 == .html
                || $0 == .URL
        })
    }
}
