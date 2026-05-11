//
//  BarMenuCoordinator+SectionBuilder.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit

private let barMenuSections: [BarMenuCoordinator.SectionBuilder] = [
    RecentTasksSection(),
    PinnedSkillsSection(),
    ShortcutItemsSection(),
    SettingsSection(),
]

extension BarMenuCoordinator {
    var allSections: [SectionBuilder] {
        barMenuSections
    }

    protocol SectionBuilder {
        /// must return distinct menu items each time a section is built
        func sectionItems() -> [NSMenuItem]
    }
}
