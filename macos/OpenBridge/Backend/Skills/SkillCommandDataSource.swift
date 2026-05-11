//
//  SkillCommandDataSource.swift
//  OpenBridge
//

import AppKit
import ComposerEditor
import SwiftUI

/// Bridges SkillManager to ComposerEditor's CommandMenuDataSource
@MainActor
final class SkillCommandDataSource: CommandMenuDataSource {
    static let shared = SkillCommandDataSource()

    private init() {}

    func commandMenuItems() -> [CommandItem] {
        SkillManager.shared.skills
            .filter { !$0.disabled && $0.visibility != .hidden }
            .map { skill in
                let escapedName = skill.displayName.replacingOccurrences(of: "\"", with: "&quot;")
                let repoAttr = skill.sourceRepo.map { " source-repo=\"\($0)\"" } ?? ""
                return CommandItem(
                    id: skill.id,
                    name: skill.displayName,
                    description: skill.description,
                    iconImage: renderSkillIcon(for: skill),
                    plainTextContentRepresentation: "<use-skill display-name=\"\(escapedName)\"\(repoAttr)>\(skill.name)</use-skill>"
                )
            }
    }

    /// Render skill icon as NSImage (matching SkillRow style)
    func renderSkillIcon(for skill: Skill) -> NSImage {
        let size: CGFloat = 20
        let cornerRadius: CGFloat = 6

        let backgroundColor: Color = skill.color.map { Color(hex: $0) } ?? .black
        let isEmoji = skill.icon?.isEmojiOnly ?? false
        let iconContent = skill.icon ?? "document.badge.plus"

        let iconView = ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor.gradient)
                .frame(width: size, height: size)

            if isEmoji {
                Text(iconContent)
                    .font(.system(size: size * 0.5))
            } else {
                Image(systemName: iconContent)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: iconView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        }

        // Fallback: return empty image
        return NSImage(size: NSSize(width: size, height: size))
    }
}
