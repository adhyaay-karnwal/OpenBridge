import AppKit

@MainActor
final class PinnedSkillsSection: BarMenuCoordinator.SectionBuilder {
    private let maxVisibleItems = 5

    func sectionItems() -> [NSMenuItem] {
        let pinnedSkills = SkillManager.shared.skills
            .filter(\.pinned)
            .sorted { lastUsedTime(for: $0) > lastUsedTime(for: $1) }
        guard !pinnedSkills.isEmpty else { return [] }

        var items: [NSMenuItem] = []

        let headerItem = NSMenuItem()
        headerItem.view = createHeaderView(String(localized: "Pinned Skills"))
        items.append(headerItem)

        let primarySkills = Array(pinnedSkills.prefix(maxVisibleItems))
        for skill in primarySkills {
            items.append(createMenuItem(for: skill))
        }

        let remainingSkills = Array(pinnedSkills.dropFirst(maxVisibleItems))
        if !remainingSkills.isEmpty {
            let moreItem = NSMenuItem(
                title: String(localized: "More Pinned Skills (\(remainingSkills.count))"),
                action: nil,
                keyEquivalent: ""
            )

            let submenu = NSMenu()
            for skill in remainingSkills {
                submenu.addItem(createMenuItem(for: skill))
            }
            moreItem.submenu = submenu
            items.append(moreItem)
        }

        return items
    }

    private func createHeaderView(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .disabledControlTextColor

        let padding = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        let labelSize = label.fittingSize
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: labelSize.width + padding.left + padding.right,
            height: labelSize.height + padding.top + padding.bottom
        ))
        label.frame = NSRect(
            x: padding.left, y: padding.bottom,
            width: labelSize.width, height: labelSize.height
        )
        container.addSubview(label)

        return container
    }

    private func createMenuItem(for skill: Skill) -> NSMenuItem {
        let icon = skill.icon ?? "📌"

        let item = NSMenuItem(
            title: skill.displayName,
            action: #selector(handleSkillClick(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = skill.id

        if let repo = skill.sourceRepo {
            let attributed = NSMutableAttributedString(
                string: skill.displayName,
                attributes: [.font: NSFont.menuFont(ofSize: 0)]
            )
            attributed.append(NSAttributedString(
                string: "  \(repo)",
                attributes: [
                    .font: NSFont.menuFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
            item.attributedTitle = attributed
        }

        if icon.isEmojiOnly {
            item.image = emojiImage(icon)
        } else {
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: skill.displayName)
        }

        return item
    }

    private func emojiImage(_ emoji: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 12)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributedString = NSAttributedString(string: emoji, attributes: attributes)
            let stringSize = attributedString.size()
            let drawPoint = NSPoint(
                x: (rect.width - stringSize.width) / 2,
                y: (rect.height - stringSize.height) / 2
            )
            attributedString.draw(at: drawPoint)
            return true
        }
    }

    private func lastUsedTime(for skill: Skill) -> Date {
        SkillManager.shared.lastUsedTime(for: skill.name)
    }

    @objc private func handleSkillClick(_ sender: NSMenuItem) {
        guard let skillID = sender.representedObject as? String else { return }
        guard let skill = SkillManager.shared.skills.first(where: { $0.id == skillID }) else { return }

        AnalyticsManager.track(.init(do: .pinnedSkillClicked(name: skill.name)))
        ChatSurfaceModel.shared.activateSkill(skill)
        Windows.shared.open(.chat)
    }
}
