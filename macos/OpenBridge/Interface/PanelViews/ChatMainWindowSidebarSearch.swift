import SwiftUI

private enum ChatMainWindowSidebarSearchMetrics {
    static let fieldHeight: CGFloat = 34
    static let fieldCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 12
    static let rowSpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 8
    static let listVerticalPadding: CGFloat = 4
}

struct ChatMainWindowSidebarSearchField: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: ChatConversationSearchModel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                String(localized: "Search conversations"),
                text: Binding(
                    get: { model.query },
                    set: { model.updateQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isFocused)
            .focusEffectDisabled()
            .onSubmit {
                model.performSearchNow()
            }

            if !model.query.isEmpty {
                Button {
                    model.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ChatMainWindowSidebarSearchMetrics.fieldHeight)
        .background(
            RoundedRectangle(
                cornerRadius: ChatMainWindowSidebarSearchMetrics.fieldCornerRadius,
                style: .continuous
            )
            .fill(fieldBackgroundColor)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ChatMainWindowSidebarSearchMetrics.fieldCornerRadius,
                style: .continuous
            )
            .strokeBorder(fieldBorderColor, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .accessibilityIdentifier("chat.mainWindow.sidebar.searchField")
    }

    private var fieldBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(isFocused ? 0.1 : 0.06)
        default:
            Color.black.opacity(isFocused ? 0.055 : 0.035)
        }
    }

    private var fieldBorderColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.08)
        }
    }
}

struct ChatMainWindowSidebarSearchResultsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: ChatConversationSearchModel

    @State private var hoveredResultID: String?

    var body: some View {
        Group {
            switch model.status {
            case .loading:
                stateContainer {
                    stateView(
                        title: String(localized: "Searching..."),
                        subtitle: nil,
                        showSpinner: true
                    )
                }
            case .error:
                stateContainer {
                    stateView(
                        title: model.searchErrorMessage ?? String(localized: "Search failed. Please try again."),
                        subtitle: nil,
                        retryAction: model.retry
                    )
                }
            case .ready where model.results.isEmpty:
                stateContainer {
                    stateView(
                        title: String(localized: "No matches found"),
                        subtitle: String(localized: "Try a shorter phrase or a different keyword.")
                    )
                }
            case .ready:
                ScrollView {
                    VStack(alignment: .leading, spacing: ChatMainWindowSidebarSearchMetrics.rowSpacing) {
                        if let openErrorMessage = model.openErrorMessage {
                            Text(openErrorMessage)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color.red.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }

                        ForEach(model.results) { result in
                            resultRow(result)
                        }
                    }
                    .padding(.vertical, ChatMainWindowSidebarSearchMetrics.listVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resultRow(_ result: ConversationSearchResult) -> some View {
        let isSelected = model.selectedResultID == result.id
        let isHovered = hoveredResultID == result.id

        return Button {
            model.open(result)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ChatConversationSearchResultFormatter.displayTitle(for: result))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ChatConversationSearchResultFormatter.formattedTimestamp(result.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ChatConversationSearchResultFormatter.highlightedSnippet(
                    ChatConversationSearchResultFormatter.displaySnippet(for: result)
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, ChatMainWindowSidebarSearchMetrics.rowHorizontalPadding)
            .padding(.vertical, ChatMainWindowSidebarSearchMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: ChatMainWindowSidebarSearchMetrics.rowCornerRadius,
                    style: .continuous
                )
                .fill(rowFillColor(isHovered: isHovered, isSelected: isSelected))
            )
            .opacity(isSelected ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
        .onHover { isHovering in
            guard !isSelected else {
                if hoveredResultID == result.id {
                    hoveredResultID = nil
                }
                return
            }

            if isHovering {
                hoveredResultID = result.id
            } else if hoveredResultID == result.id {
                hoveredResultID = nil
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(ChatConversationSearchResultFormatter.searchResultAccessibilityLabel(for: result))
    }

    private func stateContainer(@ViewBuilder content: () -> some View) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateView(
        title: String,
        subtitle: String?,
        showSpinner: Bool = false,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            if showSpinner {
                AnimatedLogo(config: loadingLogoConfig)
                    .frame(width: 27, height: 24)
            }

            if showSpinner {
                ThinkingHighlightText(
                    text: title,
                    font: .system(size: 12.5, weight: .regular),
                    baseColor: loadingTextBaseColor,
                    highlightColor: loadingTextHighlightColor,
                    alignment: .center
                )
                .multilineTextAlignment(.center)
            } else {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction {
                Button(String(localized: "Try again")) {
                    retryAction()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(retryBackgroundColor, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
    }

    private func rowFillColor(isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            switch colorScheme {
            case .dark:
                return Color.white.opacity(isHovered ? 0.12 : 0.09)
            default:
                return Color.black.opacity(isHovered ? 0.09 : 0.065)
            }
        }

        return ConversationListRowOverlayStyle.fillColor(
            isHovered: isHovered,
            presentationStyle: .menu,
            colorScheme: colorScheme
        )
    }

    private var retryBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.06)
        }
    }

    private var loadingTextBaseColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.42)
        default:
            Color.black.opacity(0.38)
        }
    }

    private var loadingTextHighlightColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.92)
        default:
            Color.black.opacity(0.82)
        }
    }

    private var loadingLogoConfig: AnimatedLogoConfig {
        var config = AnimatedLogoConfig.default
        config.strokeColor = .secondary
        config.strokeWidth = 1.8
        config.enterDrawDuration = 1.1
        return config
    }
}
