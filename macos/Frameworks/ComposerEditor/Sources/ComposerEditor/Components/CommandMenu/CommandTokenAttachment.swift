//
//  CommandTokenAttachment.swift
//  ComposerEditor
//

import AppKit

/// Custom NSTextAttachment for displaying command tokens inline in text
@MainActor
public final class CommandTokenAttachment: NSTextAttachment {
    public let command: CommandItem

    private static let horizontalPadding: CGFloat = 6
    private static let verticalPadding: CGFloat = 3
    private static let iconSize: CGFloat = 16
    private static let iconSpacing: CGFloat = 4
    private static let fontSize: CGFloat = 12

    /// The rendered token height, used by text editors to set minimumLineHeight.
    static let tokenHeight: CGFloat = iconSize + verticalPadding * 2

    public init(command: CommandItem) {
        self.command = command
        super.init(data: nil, ofType: nil)
        updateRenderedImage()
    }

    public func refreshAppearance() {
        updateRenderedImage()
    }

    private func updateRenderedImage() {
        image = Self.renderTokenImage(for: command)
        if let image {
            bounds = CGRect(x: 0, y: -image.size.height / 4, width: image.size.width, height: image.size.height)
        }
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func renderTokenImage(for command: CommandItem) -> NSImage {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let text = command.name

        // Use labelColor to match input field text color (works in both light/dark mode)
        let textColor = NSColor.labelColor
        let bgColor = NSColor.quaternaryLabelColor

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSize = text.size(withAttributes: textAttributes)

        let hasIcon = command.iconImage != nil
        let iconWidth = hasIcon ? iconSize + iconSpacing : 0
        let width = iconWidth + textSize.width + horizontalPadding * 2
        let height = max(iconSize, textSize.height) + verticalPadding * 2

        let size = NSSize(width: ceil(width), height: ceil(height))
        // Capsule corner radius
        let cornerRadius = size.height / 2

        return NSImage(size: size, flipped: false) { rect in
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            bgColor.setFill()
            bgPath.fill()

            var textX = horizontalPadding

            // Draw icon if available
            if let iconImage = command.iconImage {
                let iconRect = NSRect(
                    x: horizontalPadding,
                    y: (rect.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                iconImage.draw(in: iconRect)
                textX += iconSize + iconSpacing
            }

            let textRect = NSRect(
                x: textX,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: textAttributes)

            return true
        }
    }
}

// MARK: - Helper Extension

public extension NSMutableAttributedString {
    @MainActor
    func insertCommandToken(_ command: CommandItem, at index: Int) {
        let attachment = CommandTokenAttachment(command: command)
        let attachmentString = NSAttributedString(attachment: attachment)
        insert(attachmentString, at: index)
    }

    @MainActor
    func appendCommandToken(_ command: CommandItem) {
        let attachment = CommandTokenAttachment(command: command)
        let attachmentString = NSAttributedString(attachment: attachment)
        append(attachmentString)
    }
}

/// Extracts command items from an attributed string
@MainActor
public func extractCommands(from attributedString: NSAttributedString) -> [CommandItem] {
    var commands: [CommandItem] = []
    attributedString.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: attributedString.length)
    ) { value, _, _ in
        if let attachment = value as? CommandTokenAttachment {
            commands.append(attachment.command)
        }
    }
    return commands
}

/// Converts attributed string with command tokens to plain text
@MainActor
public func convertCommandsToPlainText(_ attributedString: NSAttributedString) -> String {
    var result = ""
    attributedString.enumerateAttributes(
        in: NSRange(location: 0, length: attributedString.length)
    ) { attrs, range, _ in
        if let attachment = attrs[.attachment] as? CommandTokenAttachment {
            result += attachment.command.plainTextContentRepresentation
        } else {
            result += attributedString.attributedSubstring(from: range).string
        }
    }
    return result
}
