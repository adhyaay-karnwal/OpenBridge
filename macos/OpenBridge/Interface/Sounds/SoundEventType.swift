//
//  SoundEventType.swift
//  OpenBridge
//

import Foundation
import SwiftUI

/// Defines the different sound events that can be configured in the app.
nonisolated enum SoundEventType: String, CaseIterable, Sendable, Identifiable, Codable {
    case copy
    case agentTaskComplete
    case agentTaskCreated
    case permission
    case schedule
    case error

    nonisolated var id: String {
        rawValue
    }

    /// Human-readable display name for the event
    nonisolated var displayName: String {
        switch self {
        case .copy: String(localized: "Copy to Clipboard")
        case .agentTaskComplete: String(localized: "Agent Task Complete")
        case .agentTaskCreated: String(localized: "Agent Task Created")
        case .permission: String(localized: "Permissions")
        case .schedule: String(localized: "Schedule")
        case .error: String(localized: "Error")
        }
    }

    /// Description of when this sound plays
    nonisolated var eventDescription: String {
        switch self {
        case .copy: String(localized: "Plays when content is copied to the clipboard")
        case .agentTaskComplete: String(localized: "Plays when an agent task completes successfully")
        case .agentTaskCreated: String(localized: "Plays when a new agent task is created")
        case .permission: String(localized: "Plays when a permission request appears")
        case .schedule: String(localized: "Plays when a schedule notification is shown")
        case .error: String(localized: "Plays when an error occurs (e.g., task failure, API error)")
        }
    }

    /// The default sound type for this event
    nonisolated var defaultSound: SoundType {
        switch self {
        case .copy: .clunk
        case .agentTaskComplete: .ding
        case .agentTaskCreated: .wave
        case .permission: .rumble
        case .schedule: .bloop
        case .error: .thump
        }
    }

    /// The SF Symbol icon name for this event
    nonisolated var iconName: String {
        switch self {
        case .copy: "document.on.document"
        case .agentTaskComplete: "checkmark.circle"
        case .agentTaskCreated: "checkmark.circle.dotted"
        case .permission: "checkerboard.shield"
        case .schedule: "calendar.badge.clock"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    nonisolated var iconBackground: AnyShapeStyle {
        switch self {
        case .copy:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "FEC748"),
                        Color(hex: "F67700"),
                        Color(hex: "F564F0"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .agentTaskComplete:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "45DC3D"),
                        Color(hex: "44AD10"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .agentTaskCreated:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "04CDFF"),
                        Color(hex: "2900F6"),
                        Color(hex: "3F004E"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .permission:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "34D399"),
                        Color(hex: "059669"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .schedule:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "60A5FA"),
                        Color(hex: "7C3AED"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .error:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "393939"),
                        Color(hex: "535353"),
                        Color(hex: "000000"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

/// Configuration for a single sound event
struct SoundEventConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var soundType: SoundType
}

/// Container for all sound event configurations
struct SoundEventSettings: Codable, Equatable, Sendable {
    var copy: SoundEventConfig
    var agentTaskComplete: SoundEventConfig
    var agentTaskCreated: SoundEventConfig
    var permission: SoundEventConfig
    var schedule: SoundEventConfig
    var error: SoundEventConfig

    private enum CodingKeys: String, CodingKey {
        case copy
        case agentTaskComplete
        case agentTaskCreated
        case permission
        case schedule
        case error
    }

    nonisolated init(
        copy: SoundEventConfig,
        agentTaskComplete: SoundEventConfig,
        agentTaskCreated: SoundEventConfig,
        permission: SoundEventConfig,
        schedule: SoundEventConfig,
        error: SoundEventConfig
    ) {
        self.copy = copy
        self.agentTaskComplete = agentTaskComplete
        self.agentTaskCreated = agentTaskCreated
        self.permission = permission
        self.schedule = schedule
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        copy = try container.decode(SoundEventConfig.self, forKey: .copy)
        agentTaskComplete = try container.decode(SoundEventConfig.self, forKey: .agentTaskComplete)
        agentTaskCreated = try container.decode(SoundEventConfig.self, forKey: .agentTaskCreated)
        permission = try container.decodeIfPresent(SoundEventConfig.self, forKey: .permission)
            ?? SoundEventConfig(isEnabled: true, soundType: SoundEventType.permission.defaultSound)
        schedule = try container.decodeIfPresent(SoundEventConfig.self, forKey: .schedule)
            ?? SoundEventConfig(isEnabled: true, soundType: SoundEventType.schedule.defaultSound)
        error = try container.decode(SoundEventConfig.self, forKey: .error)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(copy, forKey: .copy)
        try container.encode(agentTaskComplete, forKey: .agentTaskComplete)
        try container.encode(agentTaskCreated, forKey: .agentTaskCreated)
        try container.encode(permission, forKey: .permission)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(error, forKey: .error)
    }

    /// Get config for a specific event type
    func config(for event: SoundEventType) -> SoundEventConfig {
        switch event {
        case .copy: copy
        case .agentTaskComplete: agentTaskComplete
        case .agentTaskCreated: agentTaskCreated
        case .permission: permission
        case .schedule: schedule
        case .error: error
        }
    }

    /// Set config for a specific event type
    mutating func setConfig(_ config: SoundEventConfig, for event: SoundEventType) {
        switch event {
        case .copy: copy = config
        case .agentTaskComplete: agentTaskComplete = config
        case .agentTaskCreated: agentTaskCreated = config
        case .permission: permission = config
        case .schedule: schedule = config
        case .error: error = config
        }
    }

    /// Default settings with all events enabled
    nonisolated static var `default`: SoundEventSettings {
        SoundEventSettings(
            copy: SoundEventConfig(isEnabled: true, soundType: .ding),
            agentTaskComplete: SoundEventConfig(isEnabled: true, soundType: .chime),
            agentTaskCreated: SoundEventConfig(isEnabled: true, soundType: .ping),
            permission: SoundEventConfig(isEnabled: true, soundType: .rumble),
            schedule: SoundEventConfig(isEnabled: true, soundType: .bloop),
            error: SoundEventConfig(isEnabled: true, soundType: .boom)
        )
    }
}
