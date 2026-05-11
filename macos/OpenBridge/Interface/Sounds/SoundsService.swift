//
//  SoundsService.swift
//  OpenBridge
//

import AppKit

// MARK: - Sounds Service

/// A lightweight sound effect playback service.
///
/// Usage:
/// ```swift
/// SoundsService.play(.ding)
/// SoundsService.play(.chime, volume: 0.5)
/// ```
@MainActor
enum SoundsService {
    private nonisolated static let logger = Logger(subsystem: Logger.loggingSubsystem, category: "SoundsService")

    // MARK: - Cache

    private nonisolated(unsafe) static var soundCache: [SoundType: NSSound] = [:]
    private nonisolated(unsafe) static var activeSounds: Set<NSSound> = []

    // MARK: - Public API

    /// Play a sound effect.
    /// - Parameters:
    ///   - sound: The sound type to play
    ///   - volume: Volume level (0.0 - 1.0), defaults to 1.0
    ///   - overlap: If true, creates a new sound instance for overlapping playback.
    ///              If false, restarts the cached sound. Defaults to true.
    static func play(_ sound: SoundType, volume: Float = 1.0, overlap: Bool = true) {
        guard SettingsManager.shared.enableSoundEffects else { return }

        if overlap {
            playOverlapping(sound, volume: volume)
        } else {
            playRestarting(sound, volume: volume)
        }
    }

    /// Play a sound for a specific event type.
    /// This respects both the global sound setting and the individual event setting.
    /// - Parameters:
    ///   - event: The sound event type to play
    ///   - volume: Volume level (0.0 - 1.0), defaults to 1.0
    ///   - overlap: If true, creates a new sound instance for overlapping playback.
    ///              If false, restarts the cached sound. Defaults to true.
    static func play(event: SoundEventType, volume: Float = 1.0, overlap: Bool = true) {
        guard SettingsManager.shared.enableSoundEffects else { return }

        let config = SettingsManager.shared.soundEventSettings.config(for: event)
        guard config.isEnabled else { return }

        play(config.soundType, volume: volume, overlap: overlap)
    }

    /// Preload sounds into cache for faster playback.
    /// Call this at app launch for frequently used sounds.
    nonisolated static func preload(_ sounds: [SoundType]? = nil) {
        let soundsToPreload = sounds ?? SoundType.preloadList
        DispatchQueue.main.async {
            for sound in soundsToPreload {
                _ = getOrCreateSound(for: sound)
            }
            logger.debug("Preloaded \(soundsToPreload.count) sound effects")
        }
    }

    /// Clear all cached sounds.
    static func clearCache() {
        soundCache.removeAll()
        activeSounds.removeAll()
        logger.debug("Sound cache cleared")
    }

    // MARK: - Private Helpers

    private static func playOverlapping(_ soundType: SoundType, volume: Float) {
        guard let sound = createSound(for: soundType) else { return }
        sound.volume = volume

        // Keep reference until playback completes
        activeSounds.insert(sound)

        // Use notification to know when sound finishes
        NotificationCenter.default.addObserver(
            forName: nil,
            object: sound,
            queue: .main
        ) { [weak sound] _ in
            guard let sound else { return }
            if !sound.isPlaying {
                activeSounds.remove(sound)
            }
        }

        sound.play()

        // Fallback cleanup after a reasonable time (10 seconds max for any sound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak sound] in
            guard let sound else { return }
            activeSounds.remove(sound)
        }
    }

    private static func playRestarting(_ soundType: SoundType, volume: Float) {
        guard let sound = getOrCreateSound(for: soundType) else { return }
        sound.volume = volume
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private static func getOrCreateSound(for soundType: SoundType) -> NSSound? {
        if let cached = soundCache[soundType] {
            return cached
        }

        guard let sound = createSound(for: soundType) else { return nil }
        soundCache[soundType] = sound
        return sound
    }

    private static func createSound(for soundType: SoundType) -> NSSound? {
        guard let asset = NSDataAsset(name: soundType.assetName) else {
            assertionFailure("Sound asset not found: \(soundType.assetName)")
            logger.error("Sound asset not found: \(soundType.assetName)")
            return nil
        }

        guard let sound = NSSound(data: asset.data) else {
            logger.error("Failed to create NSSound for \(soundType.assetName)")
            return nil
        }

        return sound
    }
}
