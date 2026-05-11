//
//  SoundType.swift
//  OpenBridge
//

import Foundation

/// Sound effect types mapped to asset catalog names.
/// Maintain this enum manually when adding/removing sound assets.
nonisolated enum SoundType: String, CaseIterable, Sendable, Identifiable, Codable {
    case bloop
    case boom
    case chime
    case clunk
    case crack
    case ding
    case gong
    case ping
    case plonk
    case rumble
    case shimmer
    case snap
    case sparkle
    case thud
    case thump
    case tick
    case tinkle
    case wave

    nonisolated var id: String {
        rawValue
    }

    /// The asset catalog dataset name
    nonisolated var assetName: String {
        rawValue
    }

    /// Human-readable display name for the sound
    nonisolated var displayName: String {
        switch self {
        case .bloop: "Bloop"
        case .boom: "Boom"
        case .chime: "Chime"
        case .clunk: "Clunk"
        case .crack: "Crack"
        case .ding: "Ding"
        case .gong: "Gong"
        case .ping: "Ping"
        case .plonk: "Plonk"
        case .rumble: "Rumble"
        case .shimmer: "Shimmer"
        case .snap: "Snap"
        case .sparkle: "Sparkle"
        case .thud: "Thud"
        case .thump: "Thump"
        case .tick: "Tick"
        case .tinkle: "Tinkle"
        case .wave: "Wave"
        }
    }

    /// Commonly used sounds that should be preloaded at launch
    nonisolated static var preloadList: [SoundType] {
        [.clunk, .ding, .wave, .thump]
    }
}
