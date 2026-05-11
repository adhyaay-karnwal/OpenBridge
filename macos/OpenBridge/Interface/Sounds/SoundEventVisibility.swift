//
//  SoundEventVisibility.swift
//  OpenBridge
//

import Foundation

/// Manages visibility of sound events based on feature flags and local settings
@MainActor
struct SoundEventVisibility {
    /// Checks if a specific sound event should be available/visible
    static func isAvailable(_ eventType: SoundEventType) -> Bool {
        switch eventType {
        case .copy:
            false
        default:
            true
        }
    }

    /// Returns all available sound event types based on current flags and settings
    static var availableEvents: [SoundEventType] {
        SoundEventType.allCases.filter { isAvailable($0) }
    }
}
