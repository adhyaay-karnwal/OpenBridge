import AppKit

private let mainMenuSections: [MainMenuCoordinator.SectionBuilder] = [
    ApplicationMenuSection(),
    FileMenuSection(),
    EditMenuSection(),
]

extension MainMenuCoordinator {
    var allSections: [SectionBuilder] {
        mainMenuSections
    }

    protocol SectionBuilder {
        func sectionItems() -> [NSMenuItem]
    }
}
