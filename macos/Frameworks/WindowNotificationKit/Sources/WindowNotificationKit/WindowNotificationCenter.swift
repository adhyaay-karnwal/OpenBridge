import Observation
import SwiftUI

// swiftformat:disable opaqueGenericParameters
@MainActor
@Observable
public final class WindowNotificationCenter {
    var items: [HostedWindowNotification] = []

    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public var isEmpty: Bool {
        items.isEmpty
    }

    @discardableResult
    public func present<Content: View>(
        id: UUID = UUID(),
        duration: Duration? = nil,
        @ViewBuilder content: @escaping (WindowNotificationCardContext) -> Content
    ) -> UUID {
        present(id: id, duration: duration, render: { context in
            AnyView(content(context))
        })
    }

    @discardableResult
    public func present<Content: View>(
        id: UUID = UUID(),
        duration: Duration? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> UUID {
        present(id: id, duration: duration) { _ in
            content()
        }
    }

    public func dismiss(_ id: UUID) {
        dismissalTasks[id]?.cancel()
        dismissalTasks[id] = nil
        items.removeAll { $0.id == id }
    }

    public func dismissAll() {
        dismissalTasks.values.forEach { $0.cancel() }
        dismissalTasks.removeAll()
        items.removeAll()
    }

    @discardableResult
    func present(
        id: UUID = UUID(),
        duration: Duration? = nil,
        render: @escaping (WindowNotificationCardContext) -> AnyView
    ) -> UUID {
        upsert(
            HostedWindowNotification(
                id: id,
                render: render
            ),
            duration: duration
        )
        return id
    }

    private func upsert(_ item: HostedWindowNotification, duration: Duration?) {
        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            items[existingIndex] = item
            if existingIndex != 0 {
                let updated = items.remove(at: existingIndex)
                items.insert(updated, at: 0)
            }
        } else {
            items.insert(item, at: 0)
        }

        dismissalTasks[item.id]?.cancel()
        dismissalTasks[item.id] = nil

        guard let duration else { return }

        dismissalTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.dismiss(item.id)
        }
    }
}

struct HostedWindowNotification: Identifiable {
    let id: UUID
    let render: (WindowNotificationCardContext) -> AnyView
}

// swiftformat:enable opaqueGenericParameters
