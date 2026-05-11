import Foundation

public struct ComposerVoiceRecordingState: Equatable, Sendable {
    public let levels: [Double]
    public let duration: TimeInterval
    public let currentAmplitude: Double

    public init(levels: [Double], duration: TimeInterval, currentAmplitude: Double = 0) {
        self.levels = levels
        self.duration = duration
        self.currentAmplitude = currentAmplitude
    }
}

public enum ComposerVoiceInputState: Equatable, Sendable {
    case idle
    case recording(ComposerVoiceRecordingState)
    case transcribing(ComposerVoiceRecordingState)
}

public enum ComposerVoiceIdleButtonStyle: Equatable, Sendable {
    case accent
    case warning
}

public struct ComposerVoiceInputConfig {
    public let state: ComposerVoiceInputState
    public let isButtonEnabled: Bool
    public let canAutoSendRecording: Bool
    public let disablesSendButton: Bool
    public let idleButtonStyle: ComposerVoiceIdleButtonStyle
    public let shortcutHint: String?
    public let onPrimaryAction: () -> Void
    public let onCancelVoiceInput: () -> Void
    public let onStopRecording: () -> Void
    public let onSendRecording: () -> Void

    public init(
        state: ComposerVoiceInputState,
        isButtonEnabled: Bool,
        canAutoSendRecording: Bool = true,
        disablesSendButton: Bool = false,
        idleButtonStyle: ComposerVoiceIdleButtonStyle = .accent,
        shortcutHint: String? = nil,
        onPrimaryAction: @escaping () -> Void,
        onCancelVoiceInput: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onSendRecording: @escaping () -> Void
    ) {
        self.state = state
        self.isButtonEnabled = isButtonEnabled
        self.canAutoSendRecording = canAutoSendRecording
        self.disablesSendButton = disablesSendButton
        self.idleButtonStyle = idleButtonStyle
        self.shortcutHint = shortcutHint
        self.onPrimaryAction = onPrimaryAction
        self.onCancelVoiceInput = onCancelVoiceInput
        self.onStopRecording = onStopRecording
        self.onSendRecording = onSendRecording
    }
}
