@preconcurrency import AVFoundation
import Foundation
import OSLog

private enum ChatVoiceWaveformPresentation {
    static let historySampleInterval: TimeInterval = 0.15
    static let maxStoredLevels = 240
}

private struct MicrophoneSettingsPromptError: Error {}

@MainActor
extension ChatEditorViewModel {
    var canStartVoiceRecording: Bool {
        false
    }

    var canAutoSendVoiceRecording: Bool {
        !isLoading && !canStop && !attachmentManager.hasPendingOrUploadingAttachments
    }

    func requestStartVoiceRecording() {
        resetVoiceInputPresentation()
        voiceAlert = .transcriptionError(
            message: String(localized: "Voice transcription is unavailable in the local app.")
        )
    }

    func requestStopVoiceRecording() {
        finalizeVoiceRecording(autoSend: false)
    }

    func requestSendVoiceRecording() {
        finalizeVoiceRecording(autoSend: true)
    }

    func requestCancelVoiceInput() {
        guard voiceInputState != .idle else { return }
        cancelVoiceInput()
    }

    func clearVoiceAlert() {
        voiceAlert = nil
    }

    func refreshMicrophonePermissionState() {
        isMicrophonePermissionAuthorizedForVoiceInput = MicrophonePermission().isAuthorized
    }

    func dismissMicrophoneSettingsPrompt() {
        isMicrophoneSettingsPromptPresented = false
    }

    func openMicrophoneSettings() {
        isMicrophoneSettingsPromptPresented = false
        MicrophonePermission().openSystemSettings()
    }

    func cancelVoiceInput() {
        voiceTask?.cancel()
        voiceTask = nil
        voiceRecorder.cancelAndDiscard()
        voiceAlert = nil
        resetVoiceInputPresentation()
    }

    private func finalizeVoiceRecording(autoSend: Bool) {
        guard voiceInputState == .recording else { return }

        let recordingURL: URL
        do {
            recordingURL = try voiceRecorder.stop()
        } catch {
            handleVoiceFailure(error)
            return
        }

        flushPendingVoiceWaveformPeak()

        let recordedDuration = voiceRecordedDuration
        voiceInputState = .transcribing(autoSend: autoSend)
        voiceTask?.cancel()
        voiceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                voiceTask = nil
                try? FileManager.default.removeItem(at: recordingURL)
            }

            do {
                let transcript = try await voiceTranscriptionService.transcribe(
                    fileURL: recordingURL,
                    durationSeconds: recordedDuration
                )
                try Task.checkCancellation()
                completeVoiceTranscription(transcript, autoSend: autoSend)
            } catch is CancellationError {
                resetVoiceInputPresentation()
            } catch {
                handleVoiceFailure(error)
            }
        }
    }

    private func completeVoiceTranscription(_ transcript: String, autoSend: Bool) {
        let mergedText = mergeTranscript(transcript, into: text)
        resetVoiceInputPresentation()

        guard autoSend else {
            text = mergedText
            isFocused = true
            return
        }

        let submission = currentSubmission(textOverride: mergedText)
        guard canSend(submission: submission) else {
            text = mergedText
            isFocused = true
            return
        }

        sendVoiceAutoSubmission(submission, fallbackText: mergedText)
    }

    private func sendVoiceAutoSubmission(_ submission: Submission, fallbackText: String) {
        withLoadingTask {
            do {
                try await AgentSessionManager.shared.waitUntilReady()
                let didStart = try await self.performSendOperation(
                    submission: submission,
                    skillOverride: nil
                )
                if !didStart {
                    self.text = fallbackText
                    self.isFocused = true
                }
            } catch is CancellationError {
                self.text = fallbackText
                self.isFocused = true
            } catch {
                self.text = fallbackText
                self.isFocused = true
                self.error = error
            }
        }
    }

    private func handleVoiceSample(level: Double, duration: TimeInterval) {
        guard voiceInputState == .recording else { return }

        let previousLevel = max(voiceCurrentAmplitude, voiceWaveformLevels.last ?? 0)
        let smoothedLevel: Double =
            if previousLevel > 0 {
                (previousLevel * 0.18) + (level * 0.82)
            } else {
                level
            }

        voiceRecordedDuration = duration
        voiceCurrentAmplitude = smoothedLevel
        voicePendingWaveformPeak = max(voicePendingWaveformPeak, smoothedLevel)

        let displayedDuration = TimeInterval(Int(duration.rounded(.down)))
        if displayedDuration != voiceRecordingDuration {
            voiceRecordingDuration = displayedDuration
        }

        let shouldAppendLevel: Bool =
            if let lastWaveformSampleTime = voiceLastWaveformSampleTime {
                duration - lastWaveformSampleTime >= ChatVoiceWaveformPresentation.historySampleInterval
            } else {
                true
            }

        guard shouldAppendLevel else { return }

        voiceLastWaveformSampleTime = duration
        appendVoiceWaveformLevel(voicePendingWaveformPeak)
        voicePendingWaveformPeak = 0
    }

    private func mergeTranscript(_ transcript: String, into draft: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return draft
        }

        guard !draft.isEmpty else {
            return trimmedTranscript
        }

        if let lastCharacter = draft.last, lastCharacter.isWhitespace {
            return draft + trimmedTranscript
        }

        return draft + " " + trimmedTranscript
    }

    private func handleVoiceFailure(_ error: Error) {
        voiceRecorder.cancelAndDiscard()
        resetVoiceInputPresentation()
        voiceAlert = ChatVoiceAlert.from(error: error)
    }

    private func resetVoiceInputPresentation() {
        voiceInputState = .idle
        voiceWaveformLevels.removeAll(keepingCapacity: true)
        voiceRecordingDuration = 0
        voiceCurrentAmplitude = 0
        voiceRecordedDuration = 0
        voiceLastWaveformSampleTime = nil
        voicePendingWaveformPeak = 0
    }

    private func flushPendingVoiceWaveformPeak() {
        guard voicePendingWaveformPeak > 0 else { return }
        appendVoiceWaveformLevel(voicePendingWaveformPeak)
        voiceLastWaveformSampleTime = voiceRecordedDuration
        voicePendingWaveformPeak = 0
    }

    private func appendVoiceWaveformLevel(_ level: Double) {
        voiceWaveformLevels.append(level)

        if voiceWaveformLevels.count > ChatVoiceWaveformPresentation.maxStoredLevels {
            voiceWaveformLevels.removeFirst(
                voiceWaveformLevels.count - ChatVoiceWaveformPresentation.maxStoredLevels
            )
        }
    }
}

enum ChatVoiceInputState: Equatable {
    case idle
    case recording
    case transcribing(autoSend: Bool)

    var blocksManualSend: Bool {
        if case .transcribing = self {
            return true
        }
        return false
    }

    var disablesSendButton: Bool {
        if case .transcribing = self {
            return true
        }
        return false
    }
}

enum ChatVoiceAlert: Equatable {
    case transcriptionError(message: String)

    static func from(error: Error) -> Self {
        .transcriptionError(message: error.localizedDescription)
    }

    var title: String {
        switch self {
        case .transcriptionError:
            String(localized: "Voice Transcription Failed")
        }
    }

    var message: String {
        switch self {
        case let .transcriptionError(message):
            message
        }
    }
}

@MainActor
final class ChatVoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTask: Task<Void, Never>?

    func start(onSample: @escaping @MainActor (Double, TimeInterval) -> Void) async throws {
        let microphonePermission = MicrophonePermission()
        switch microphonePermission.authorizationStatus {
        case .authorized:
            break
        case .denied, .restricted:
            throw MicrophoneSettingsPromptError()
        case .notDetermined:
            let granted = await microphonePermission.requestAccess()
            try Task.checkCancellation()
            guard granted else {
                throw MicrophoneSettingsPromptError()
            }
        @unknown default:
            throw CancellationError()
        }

        cancelAndDiscard()

        let url = makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RuntimeError(localized: "Failed to start voice recording.")
        }

        self.recorder = recorder
        recordingURL = url
        onSample(0, 0)

        meterTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard let recorder = self.recorder, recorder.isRecording else { break }
                recorder.updateMeters()
                onSample(Self.normalizedLevel(from: recorder), recorder.currentTime)
            }
        }
    }

    func stop() throws -> URL {
        guard let recorder, let recordingURL else {
            throw RuntimeError(localized: "No active voice recording was found.")
        }

        meterTask?.cancel()
        meterTask = nil
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        return recordingURL
    }

    func cancelAndDiscard() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    private static func normalizedLevel(from recorder: AVAudioRecorder) -> Double {
        let peakPower = Double(max(recorder.peakPower(forChannel: 0), -48))
        let linearLevel = pow(10.0, peakPower / 20.0)
        return min(max((linearLevel - 0.02) / 0.98, 0.0), 1.0)
    }
}

final class ChatVoiceTranscriptionService {
    private let logger = Logger.network

    func transcribe(fileURL: URL, durationSeconds: TimeInterval) async throws -> String {
        _ = fileURL
        _ = durationSeconds
        throw RuntimeError(localized: "Voice transcription is unavailable in the local app.")
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "mp4":
            "audio/m4a"
        case "ogg", "opus":
            "audio/ogg"
        case "wav":
            "audio/wav"
        case "mp3":
            "audio/mpeg"
        default:
            "application/octet-stream"
        }
    }

    static func normalizedLanguageCode(from languageIdentifier: String?) -> String? {
        let trimmed = languageIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        guard let primarySubtag = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first else {
            return nil
        }

        let normalized = primarySubtag.lowercased()
        guard normalized != "und" else { return nil }
        guard (2 ... 3).contains(normalized.count) else { return nil }
        guard normalized.unicodeScalars.allSatisfy(CharacterSet.letters.contains(_:)) else {
            return nil
        }

        return normalized
    }
}
