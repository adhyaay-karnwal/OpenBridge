//
//  EventMonitor.swift
//  OpenBridgeInterface
//
//  Created by GitHub Copilot on 20/10/2025.
//

import AppKit

@MainActor
class EventMonitor {
    private var globalMonitor: AnyObject?
    private var localMonitor: AnyObject?
    private let event: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> NSEvent?
    private let shouldCaptureEvents: Bool

    init(
        event: NSEvent.EventTypeMask,
        shouldCaptureEvents: Bool = false,
        handler: @escaping (NSEvent?) -> NSEvent?
    ) {
        self.event = event
        self.shouldCaptureEvents = shouldCaptureEvents
        self.handler = handler
    }

    @MainActor
    deinit {
        stop()
    }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: event) { [weak self] event in
            _ = self?.handler(event)
        } as AnyObject?

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: event) { [weak self] event in
            guard let self else {
                return event
            }

            if shouldCaptureEvents {
                return handler(event)
            }

            return handler(event) ?? event
        } as AnyObject?
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    var isActive: Bool {
        globalMonitor != nil || localMonitor != nil
    }
}
