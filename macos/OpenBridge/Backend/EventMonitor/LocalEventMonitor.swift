//
//  LocalEventMonitor.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import Cocoa

@MainActor
final class LocalEventMonitor {
    private let event: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private var monitor: Any?

    init(event: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.event = event
        self.handler = handler
    }

    @MainActor
    deinit {
        stop()
    }

    @discardableResult
    func start() -> Self {
        guard monitor == nil else { return self }
        monitor = NSEvent.addLocalMonitorForEvents(matching: event, handler: handler)
        return self
    }

    func stop() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
