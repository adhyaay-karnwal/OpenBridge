import AppKit

@MainActor
final class KeyboardEventCenter {
    static let shared = KeyboardEventCenter()

    private var monitor: EventMonitor?
    private var keyDownHandlers: [UUID: (NSEvent) -> NSEvent?] = [:]

    private init() {}

    func registerKeyDownHandler(_ handler: @escaping (NSEvent) -> NSEvent?) -> UUID {
        let id = UUID()
        keyDownHandlers[id] = handler
        ensureMonitoring()
        return id
    }

    func unregisterKeyDownHandler(_ id: UUID) {
        keyDownHandlers.removeValue(forKey: id)
        stopIfNeeded()
    }

    private func ensureMonitoring() {
        guard monitor == nil else { return }
        monitor = EventMonitor(event: [.keyDown], shouldCaptureEvents: true) { [weak self] event in
            self?.handleKeyDown(event)
        }
        monitor?.start()
    }

    private func stopIfNeeded() {
        guard keyDownHandlers.isEmpty else { return }
        monitor?.stop()
        monitor = nil
    }

    private func handleKeyDown(_ event: NSEvent?) -> NSEvent? {
        guard let event else { return nil }
        var currentEvent: NSEvent? = event

        for handler in keyDownHandlers.values {
            guard let nextEvent = currentEvent else { break }
            currentEvent = handler(nextEvent)
        }

        return currentEvent
    }
}
