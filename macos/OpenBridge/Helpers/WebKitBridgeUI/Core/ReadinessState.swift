import Foundation

actor ReadinessStateActor {
    private var navigationCompleted = false
    private var handshakeCompleted = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func reset() {
        navigationCompleted = false
        handshakeCompleted = false
    }

    func markNavigationCompleted() {
        navigationCompleted = true
        notifyIfReady()
    }

    func markHandshakeCompleted() {
        handshakeCompleted = true
        notifyIfReady()
    }

    func isReady() -> Bool {
        navigationCompleted && handshakeCompleted
    }

    func waitForReady() async throws {
        if isReady() {
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id)
            }
        }
    }

    func cancelWaiter(id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func notifyIfReady() {
        guard isReady() else { return }
        waiters.values.forEach { $0.resume() }
        waiters.removeAll()
    }
}
