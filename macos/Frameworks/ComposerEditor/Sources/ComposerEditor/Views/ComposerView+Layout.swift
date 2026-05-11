import GlassEffectKit
import SwiftUI

extension ComposerView {
    private var standardLayoutShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
    }

    private var standardLayoutPadding: EdgeInsets {
        let shouldIncreaseTopPadding = activeCommandBadge != nil
            && draftQuoteBadge == nil
            && viewModel.attachments.isEmpty

        return EdgeInsets(
            top: appearance.padding.top + (shouldIncreaseTopPadding ? 8 : 0),
            leading: appearance.padding.leading,
            bottom: appearance.padding.bottom,
            trailing: appearance.padding.trailing
        )
    }

    // MARK: - Shared Bindings

    private var focusBinding: Binding<Bool> {
        Binding(get: { viewModel.isFocused }, set: { viewModel.isFocused = $0 })
    }

    private var pasteHandler: (NSPasteboard) -> Bool {
        handlePaste
    }

    private var dropHandler: ((NSPasteboard) -> Bool)? {
        guard allowsExternalFileDrop else { return nil }
        return { pasteboard in
            handlePaste(pasteboard)
        }
    }

    private func handleSend(plainText: String) {
        viewModel.text = plainText

        if isRecordingVoice {
            voiceInput?.onSendRecording()
            return
        }

        if isTranscribingVoice {
            return
        }

        guard viewModel.canSend else { return }
        viewModel.requestSend()
    }

    // MARK: - Layouts

    var compactLayout: some View {
        VStack(spacing: 6) {
            if let badge = draftQuoteBadge {
                DraftQuoteBadgeView(badge: badge)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                if let voiceActivityState,
                   let voiceInput
                {
                    voiceActivityControls(voiceActivityState: voiceActivityState, voiceInput: voiceInput)
                } else {
                    uploadButton

                    HorizontalScrollableTextEditor(
                        text: $viewModel.text,
                        placeholder: placeholder,
                        fontSize: 15,
                        onSend: handleSend,
                        onPaste: pasteHandler,
                        onDrop: dropHandler,
                        focusBinding: focusBinding,
                        commandDataSource: commandDataSource,
                        onCommandSelected: onCommandSelected
                    )
                    .accessibilityIdentifier("chat.composer.input")
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .contentShape(.rect)
                }

                sendButton
            }
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .padding(appearance.padding)
        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
    }

    var standardLayout: some View {
        VStack(spacing: 8) {
            if let badge = draftQuoteBadge {
                DraftQuoteBadgeView(badge: badge)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 8)
            }

            if !viewModel.attachments.isEmpty {
                AttachmentPreviewRow(
                    attachments: viewModel.attachments,
                    onRemove: { viewModel.removeAttachment(id: $0) },
                    onRetry: { viewModel.retryAttachment($0) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let badge = activeCommandBadge {
                HStack {
                    ActiveCommandBadgeView(badge: badge)
                    Spacer()
                }
                .padding(.bottom, -4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VerticalExpendedTextField(
                text: $viewModel.text,
                placeholder: placeholder,
                fontSize: 15,
                onSend: handleSend,
                onPaste: pasteHandler,
                onDrop: dropHandler,
                isEditable: !isTranscribingVoice,
                autoFocus: false,
                focusBinding: focusBinding,
                commandDataSource: commandDataSource,
                onCommandSelected: onCommandSelected
            )
            .accessibilityIdentifier("chat.composer.input")

            HStack {
                if let voiceActivityState,
                   let voiceInput
                {
                    voiceActivityControls(voiceActivityState: voiceActivityState, voiceInput: voiceInput)
                } else {
                    preferencesGroup
                    Spacer()
                }
                sendButton
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: viewModel.attachments.isEmpty)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: activeCommandBadge != nil)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: draftQuoteBadge != nil)
        .frame(maxWidth: .infinity)
        .padding(standardLayoutPadding)
        .background {
            ZStack {
                if appearance.showBackground {
                    Color.primary.opacity(0.1)
                } else {
                    Color.clear
                }

                ComposerRecordingGlow(
                    isActive: isVoiceActivityVisible,
                    amplitude: voiceActivityState?.state.currentAmplitude ?? 0,
                    tint: accentColor
                )
            }
        }
        .modifier(ComposerContainerMaterialModifier(
            shape: standardLayoutShape,
            glassMaterial: appearance.glassMaterial
        ))
        .overlay(
            Group {
                if appearance.showBorder {
                    standardLayoutShape
                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                }
            }
        )
        .shadow(color: appearance.showShadow ? Color.gray.opacity(0.1) : .clear, radius: appearance.showShadow ? 8 : 0)
    }

    var uploadButton: some View {
        UploadMenuButton(
            disabled: viewModel.isStreaming,
            draggingFile: viewModel.isDraggingFile,
            onFileURLs: { urls in
                if let onFileURLsAdded, onFileURLsAdded(urls, .menu) {
                    return
                }
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    viewModel.addFileURLs(urls, source: .menu)
                }
            },
            additionalMenuItems: additionalMenuItems
        )
    }

    var sendButton: some View {
        Button {
            if showsVoiceAction {
                voiceInput?.onPrimaryAction()
            } else if isRecordingVoice {
                voiceInput?.onSendRecording()
            } else if viewModel.canStop {
                viewModel.requestStop()
            } else {
                viewModel.requestSend()
            }
        } label: {
            Image(systemName: sendButtonSystemImage)
                .font(.system(size: showsVoiceAction ? 14 : 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .foregroundStyle(sendButtonForegroundColor)
                .background {
                    if isWarningVoiceAction {
                        Circle()
                            .fill(Color.orange)
                    } else {
                        Color.clear
                            .safeGlassEffect(.regular.tint(sendButtonTintColor, opacity: 1.0), in: Circle())
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(sendButtonDisabled)
        .help(sendButtonHelpText)
        .accessibilityIdentifier("chat.composer.sendButton")
        .accessibilityLabel(sendButtonAccessibilityLabel)
    }
}

private struct ComposerContainerMaterialModifier<ContainerShape: Shape>: ViewModifier {
    let shape: ContainerShape
    let glassMaterial: SafeGlassMaterial?

    func body(content: Content) -> some View {
        if let glassMaterial {
            content.safeGlassEffect(glassMaterial, in: shape)
        } else {
            content.clipShape(shape)
        }
    }
}

// MARK: - Preferences Group

extension ComposerView {
    private var voiceState: ComposerVoiceInputState {
        voiceInput?.state ?? .idle
    }

    private var voiceActivityState: (phase: ComposerVoiceWaveformPhase, state: ComposerVoiceRecordingState)? {
        switch voiceState {
        case let .recording(state):
            (phase: .recording, state: state)
        case let .transcribing(state):
            (phase: .transcribing, state: state)
        case .idle:
            nil
        }
    }

    private var isRecordingVoice: Bool {
        voiceActivityState?.phase == .recording
    }

    private var isVoiceActivityVisible: Bool {
        voiceActivityState != nil
    }

    private var isTranscribingVoice: Bool {
        voiceActivityState?.phase == .transcribing
    }

    private var showsVoiceAction: Bool {
        !isVoiceActivityVisible
            && !viewModel.canStop
            && !viewModel.canSend
            && voiceInput != nil
    }

    private var sendButtonTintColor: Color {
        guard showsVoiceAction else { return accentColor }

        switch voiceInput?.idleButtonStyle ?? .accent {
        case .accent:
            return accentColor
        case .warning:
            return .orange
        }
    }

    private var isWarningVoiceAction: Bool {
        showsVoiceAction && voiceInput?.idleButtonStyle == .warning
    }

    private var sendButtonForegroundColor: Color {
        guard showsVoiceAction else { return accentForegroundColor }

        switch voiceInput?.idleButtonStyle ?? .accent {
        case .accent:
            return accentForegroundColor
        case .warning:
            return .white
        }
    }

    private var sendButtonSystemImage: String {
        if showsVoiceAction {
            return "mic.fill"
        }
        if isRecordingVoice || isTranscribingVoice {
            return "arrow.up"
        }
        return viewModel.canStop ? "stop.fill" : "arrow.up"
    }

    private var sendButtonDisabled: Bool {
        if showsVoiceAction {
            return !(voiceInput?.isButtonEnabled ?? false)
        }
        if isRecordingVoice {
            return !(voiceInput?.canAutoSendRecording ?? false)
        }
        if voiceInput?.disablesSendButton == true {
            return true
        }
        return viewModel.canStop ? false : !viewModel.canSend
    }

    private var sendButtonAccessibilityLabel: String {
        if showsVoiceAction {
            return "Record voice input"
        }
        if isRecordingVoice {
            return "Send recorded message"
        }
        if isTranscribingVoice {
            return "Transcribing voice input"
        }
        return viewModel.canStop ? "Stop generation" : "Send message"
    }

    private var sendButtonHelpText: String {
        if showsVoiceAction, let hint = voiceInput?.shortcutHint {
            return hint
        }
        return ""
    }

    var preferencesGroup: some View {
        HStack(spacing: 4) {
            uploadButton
                .fixedSize()
            leadingModelSelectorView
            modelSelectorView
                .layoutPriority(-1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    func voiceActivityControls(
        voiceActivityState: (phase: ComposerVoiceWaveformPhase, state: ComposerVoiceRecordingState),
        voiceInput: ComposerVoiceInputConfig
    ) -> some View {
        HStack(spacing: 12) {
            voiceCancelButton(
                action: voiceInput.onCancelVoiceInput,
                accessibilityLabel: voiceActivityState.phase == .recording
                    ? "Cancel voice recording"
                    : "Cancel voice transcription"
            )

            ComposerVoiceWaveformView(
                phase: voiceActivityState.phase,
                levels: voiceActivityState.state.levels,
                currentLevel: voiceActivityState.state.currentAmplitude,
                layoutMode: appearance.layoutMode
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("chat.composer.voiceWaveform")

            Text(formattedDuration(voiceActivityState.state.duration))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.72))

            Group {
                if voiceActivityState.phase == .recording {
                    Button(action: voiceInput.onStopRecording) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.primary)
                            .background(Color.primary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.composer.voiceStopButton")
                    .accessibilityLabel("Stop recording")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    func voiceCancelButton(
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary)
                .background(Color.primary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.composer.voiceCancelButton")
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    var modelSelectorView: some View {
        if let modelSelector {
            ComposerModelSelectorView(
                config: modelSelector,
                disabled: viewModel.isStreaming
            )
        }
    }

    @ViewBuilder
    var leadingModelSelectorView: some View {
        if let leadingModelSelector {
            ComposerModelSelectorView(
                config: leadingModelSelector,
                disabled: viewModel.isStreaming
            )
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes.formatted(.number.precision(.integerLength(2)))):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}

private struct ComposerRecordingGlow: View {
    let isActive: Bool
    let amplitude: Double
    let tint: Color

    private var clampedAmplitude: Double {
        min(max(amplitude, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * 1.45, 620)
            let height = max(proxy.size.height * 2.1, 260)
            let outerRadius = max(proxy.size.width * 0.52, 260)
            let innerRadius = max(proxy.size.width * 0.24, 130)
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height + (proxy.size.height * 0.22)

            let amp = clampedAmplitude

            ZStack {
                RadialGradient(
                    colors: [
                        tint.opacity(0.26 + amp * 0.14),
                        tint.opacity(0.14 + amp * 0.08),
                        tint.opacity(0.05),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: outerRadius
                )
                .frame(width: width, height: height)
                .scaleEffect(
                    x: isActive ? 1.0 + amp * 0.08 : 0.18,
                    y: isActive ? 1.0 + amp * 0.04 : 0.14,
                    anchor: .center
                )
                .opacity(isActive ? 0.8 + amp * 0.2 : 0)
                .blur(radius: isActive ? 26 + amp * 6 : 10)
                .position(x: centerX, y: centerY)

                RadialGradient(
                    colors: [
                        .white.opacity(0.16 + amp * 0.10),
                        tint.opacity(0.18 + amp * 0.12),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: innerRadius
                )
                .frame(width: width * 0.82, height: height * 0.88)
                .scaleEffect(
                    x: isActive ? 1.0 + amp * 0.06 : 0.12,
                    y: isActive ? 0.92 + amp * 0.04 : 0.12,
                    anchor: .center
                )
                .opacity(isActive ? 0.7 + amp * 0.3 : 0)
                .blur(radius: isActive ? 18 + amp * 6 : 8)
                .position(x: centerX, y: centerY - 6)
            }
            .animation(.spring(response: 0.58, dampingFraction: 0.86), value: isActive)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: amp)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
