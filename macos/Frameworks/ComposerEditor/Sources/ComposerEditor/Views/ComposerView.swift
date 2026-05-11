import AppKit
import GlassEffectKit
import SwiftUI
import UniformTypeIdentifiers

public enum ComposerLayoutMode: Sendable {
    case standard
    case compact
}

public struct ComposerAppearance: Sendable {
    public let showBackground: Bool
    public let showBorder: Bool
    public let showShadow: Bool
    public let glassMaterial: SafeGlassMaterial?
    public let cornerRadius: CGFloat
    public let padding: EdgeInsets
    public let layoutMode: ComposerLayoutMode

    public init(
        showBackground: Bool,
        showBorder: Bool,
        showShadow: Bool,
        glassMaterial: SafeGlassMaterial? = nil,
        cornerRadius: CGFloat,
        padding: EdgeInsets,
        layoutMode: ComposerLayoutMode = .standard
    ) {
        self.showBackground = showBackground
        self.showBorder = showBorder
        self.showShadow = showShadow
        self.glassMaterial = glassMaterial
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.layoutMode = layoutMode
    }

    public static let standalone = ComposerAppearance(
        showBackground: true,
        showBorder: true,
        showShadow: true,
        cornerRadius: 16,
        padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12),
        layoutMode: .standard
    )

    public static let standaloneTransparent = ComposerAppearance(
        showBackground: false,
        showBorder: false,
        showShadow: false,
        cornerRadius: 16,
        padding: EdgeInsets(top: 4, leading: 12, bottom: 10, trailing: 12),
        layoutMode: .standard
    )

    public static let compact = ComposerAppearance(
        showBackground: false,
        showBorder: false,
        showShadow: false,
        cornerRadius: 20,
        padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
        layoutMode: .compact
    )
}

public struct ComposerView<ViewModel: ComposerEditing>: View {
    @Bindable var viewModel: ViewModel
    let accentColor: Color
    let accentForegroundColor: Color
    let placeholder: String
    let appearance: ComposerAppearance
    let leadingModelSelector: ComposerModelSelectorConfig?
    let modelSelector: ComposerModelSelectorConfig?
    let voiceInput: ComposerVoiceInputConfig?
    let onFileURLsAdded: (([URL], AttachmentSource) -> Bool)?
    let onAttachmentAdded: ((ChatAttachment, AttachmentSource) -> Bool)?
    let compactMode: Bool
    let commandDataSource: CommandMenuDataSource?
    let onCommandSelected: ((CommandItem) -> Void)?
    let activeCommandBadge: ActiveCommandBadge?
    let draftQuoteBadge: DraftQuoteBadge?
    let additionalMenuItems: (() -> [NSMenuItem])?
    let allowsExternalFileDrop: Bool

    public init(
        viewModel: ViewModel,
        accentColor: Color = .blue,
        accentForegroundColor: Color = .white,
        placeholder: String = "Ask anything",
        appearance: ComposerAppearance = .standalone,
        leadingModelSelector: ComposerModelSelectorConfig? = nil,
        modelSelector: ComposerModelSelectorConfig? = nil,
        voiceInput: ComposerVoiceInputConfig? = nil,
        onFileURLsAdded: (([URL], AttachmentSource) -> Bool)? = nil,
        onAttachmentAdded: ((ChatAttachment, AttachmentSource) -> Bool)? = nil,
        commandDataSource: CommandMenuDataSource? = nil,
        onCommandSelected: ((CommandItem) -> Void)? = nil,
        activeCommandBadge: ActiveCommandBadge? = nil,
        draftQuoteBadge: DraftQuoteBadge? = nil,
        additionalMenuItems: (() -> [NSMenuItem])? = nil,
        allowsExternalFileDrop: Bool = true
    ) {
        self.viewModel = viewModel
        self.accentColor = accentColor
        self.accentForegroundColor = accentForegroundColor
        self.placeholder = placeholder
        self.appearance = appearance
        self.leadingModelSelector = leadingModelSelector
        self.modelSelector = modelSelector
        self.voiceInput = voiceInput
        self.onFileURLsAdded = onFileURLsAdded
        self.onAttachmentAdded = onAttachmentAdded
        compactMode = appearance.layoutMode == .compact
        self.commandDataSource = commandDataSource
        self.onCommandSelected = onCommandSelected
        self.activeCommandBadge = activeCommandBadge
        self.draftQuoteBadge = draftQuoteBadge
        self.additionalMenuItems = additionalMenuItems
        self.allowsExternalFileDrop = allowsExternalFileDrop
    }

    public var body: some View {
        Group {
            if compactMode {
                compactLayout
            } else {
                standardLayout
            }
        }
        .contentShape(Rectangle())
        .modifier(ComposerExternalFileDropModifier(
            enabled: allowsExternalFileDrop,
            isDraggingFile: $viewModel.isDraggingFile,
            handleDrop: handleDrop(providers:)
        ))
        .onExitCommand {
            viewModel.requestEscape()
        }
    }
}

private struct ComposerExternalFileDropModifier: ViewModifier {
    let enabled: Bool
    @Binding var isDraggingFile: Bool
    let handleDrop: ([NSItemProvider]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.image, .fileURL, .folder], isTargeted: $isDraggingFile) { providers in
                handleDrop(providers)
                return true
            }
        } else {
            content
        }
    }
}

private struct ComposerViewPreviewSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack {
            Spacer()

            content
                .frame(width: 560)

            Spacer()
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("Composer View") {
    @Previewable @State var viewModel = ComposerViewModel(
        text: "Write a short release note for the latest improvements to the macOS chat experience."
    )

    ComposerViewPreviewSurface {
        ComposerView(
            viewModel: viewModel,
            accentColor: .accentColor,
            accentForegroundColor: .white,
            placeholder: "Ask anything",
            appearance: .standalone,
            allowsExternalFileDrop: false
        )
    }
}

#Preview("Composer View — With Quote") {
    @Previewable @State var viewModel = ComposerViewModel(
        text: "Rewrite this in a warmer tone, but keep it concise."
    )

    ComposerViewPreviewSurface {
        ComposerView(
            viewModel: viewModel,
            accentColor: .accentColor,
            accentForegroundColor: .white,
            placeholder: "Ask anything",
            appearance: .standalone,
            draftQuoteBadge: DraftQuoteBadge(
                text: "The current onboarding message feels too formal for first-time users and doesn't clearly explain the value right away.",
                onActivate: {},
                onDismiss: {}
            ),
            allowsExternalFileDrop: false
        )
    }
}
