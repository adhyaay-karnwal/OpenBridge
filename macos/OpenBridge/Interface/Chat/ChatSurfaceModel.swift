import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ChatSurfaceModel {
    static let shared = ChatSurfaceModel()

    let editorViewModel: ChatEditorViewModel
    let scheduleStore: ScheduleStore

    @ObservationIgnored
    private var visibleHostIDs: Set<UUID> = []

    init(editorViewModel: ChatEditorViewModel? = nil) {
        let resolvedEditorViewModel = editorViewModel ?? ChatEditorViewModel()
        self.editorViewModel = resolvedEditorViewModel
        scheduleStore = ScheduleStore.shared
    }

    func hostDidAppear(id: UUID) {
        let inserted = visibleHostIDs.insert(id).inserted
        guard inserted, visibleHostIDs.count == 1 else { return }
        ConversationListViewController.shared.start()
    }

    func hostDidDisappear(id: UUID) {
        let removed = visibleHostIDs.remove(id) != nil
        guard removed, visibleHostIDs.isEmpty else { return }
        ConversationListViewController.shared.stop()
    }

    func resetForClose() {
        editorViewModel.reset()
    }

    func openNewChat() {
        editorViewModel.openNewChat()
    }

    func activateSkill(_ skill: Skill) {
        editorViewModel.activateSkill(skill)
    }
}
