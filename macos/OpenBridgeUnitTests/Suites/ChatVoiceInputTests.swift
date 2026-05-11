@testable import OpenBridge
import KeyboardShortcuts
import Testing

@MainActor
struct ChatVoiceInputTests {
    @Test
    func `voice input shortcut stays cleared after initialization`() {
        let originalShortcut = KeyboardShortcuts.getShortcut(for: .voiceInputToggle)
        let originalInitializationState = UserDefaults.standard.object(forKey: VoiceInputShortcutHelper.initializationStateKey)

        defer {
            KeyboardShortcuts.setShortcut(originalShortcut, for: .voiceInputToggle)

            if let originalInitializationState {
                UserDefaults.standard.set(originalInitializationState, forKey: VoiceInputShortcutHelper.initializationStateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: VoiceInputShortcutHelper.initializationStateKey)
            }

            KeyboardShortcuts.disable(.voiceInputToggle)
        }

        UserDefaults.standard.removeObject(forKey: VoiceInputShortcutHelper.initializationStateKey)
        KeyboardShortcuts.setShortcut(nil, for: .voiceInputToggle)

        VoiceInputShortcutHelper.ensureShortcutRegistered()
        #expect(KeyboardShortcuts.getShortcut(for: .voiceInputToggle) == VoiceInputShortcutHelper.defaultShortcut)

        VoiceInputShortcutHelper.clearShortcut()
        #expect(KeyboardShortcuts.getShortcut(for: .voiceInputToggle) == nil)

        VoiceInputShortcutHelper.ensureShortcutRegistered()
        #expect(KeyboardShortcuts.getShortcut(for: .voiceInputToggle) == nil)
    }

    @Test
    func `requestSend ignores draft while transcription is in progress`() {
        let viewModel = ChatEditorViewModel(text: "draft")
        var didSubmit = false

        viewModel.onSubmit = { _ in
            didSubmit = true
        }
        viewModel.voiceInputState = .transcribing(autoSend: false)

        #expect(viewModel.canSend == false)

        viewModel.requestSend()

        #expect(didSubmit == false)
    }

    @Test
    func `voice transcription language normalization uses ISO-639 primary subtags`() {
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "en-US") == "en")
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "zh-Hans") == "zh")
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "fil-PH") == "fil")
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: " ja ") == "ja")
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "und") == nil)
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "English") == nil)
        #expect(ChatVoiceTranscriptionService.normalizedLanguageCode(from: "") == nil)
    }

    @Test
    func `voice transcription errors stay generic`() {
        let error = RuntimeError(localized: "Request failed with status code 402")

        guard case let .transcriptionError(message) = ChatVoiceAlert.from(error: error) else {
            Issue.record("Expected a generic transcription error alert.")
            return
        }

        #expect(message.contains("402"))
    }

    @Test
    func `non http voice errors stay generic`() {
        let alert = ChatVoiceAlert.from(error: RuntimeError(localized: "Network timed out."))

        guard case let .transcriptionError(message) = alert else {
            Issue.record("Expected a generic transcription error alert.")
            return
        }

        #expect(message == "Network timed out.")
    }
}
