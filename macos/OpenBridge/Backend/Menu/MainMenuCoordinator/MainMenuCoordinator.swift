import AppKit

@MainActor
final class MainMenuCoordinator: NSObject {
    static let shared = MainMenuCoordinator()

    override init() {
        super.init()
    }

    var menu: NSMenu {
        buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let sections = allSections
        for section in sections {
            for item in section.sectionItems() {
                menu.addItem(item)
            }
        }
        return menu
    }
}
