import AppKit
import Combine

/// Recent tasks section for the status bar menu.
/// Task display is now driven by session history — this section will be
/// reconnected to active sessions in a future update.
@MainActor
final class RecentTasksSection: BarMenuCoordinator.SectionBuilder {
    func sectionItems() -> [NSMenuItem] {
        // Task cards are driven by session history in the unified model.
        // Return empty until reconnected to active session state.
        []
    }
}
