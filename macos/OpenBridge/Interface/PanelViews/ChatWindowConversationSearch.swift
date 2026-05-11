import Foundation
import Observation
import SwiftUI

enum ChatConversationSearchStatus: Equatable {
    case idle
    case loading
    case ready
    case error
}

enum ChatConversationSearchMetrics {
    static let leadingReservedSpacing: CGFloat = 8
    static let expandedInputHeight: CGFloat = 36
    static let dividerHeight: CGFloat = 1
    static let resultsMaxHeight: CGFloat = 360
    static let resultRowHeight: CGFloat = 58
    static let resultRowSpacing: CGFloat = 4
    static let resultsVerticalPadding: CGFloat = 8
    static let loadingHeight: CGFloat = 120
    static let emptyStateHeight: CGFloat = 132
    static let errorStateHeight: CGFloat = 144
    static let inlineErrorHeight: CGFloat = 42
    static let shellShadowRadius: CGFloat = 22
    static let shellShadowY: CGFloat = 12
}

@MainActor
@Observable
final class ChatConversationSearchModel {
    var isPresented = false
    var activationToken = 0
    var query = ""
    var results: [ConversationSearchResult] = []
    var selectedResultID: String?
    var status: ChatConversationSearchStatus = .idle
    var searchErrorMessage: String?
    var openErrorMessage: String?

    @ObservationIgnored
    private let messagesBridge: MessagesBridge

    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    @ObservationIgnored
    private var openTask: Task<Void, Never>?

    @ObservationIgnored
    private var requestSequence = 0

    @ObservationIgnored
    private let requiresPresentation: Bool

    @ObservationIgnored
    private let dismissesAfterOpen: Bool

    init(
        messagesBridge: MessagesBridge,
        requiresPresentation: Bool = true,
        dismissesAfterOpen: Bool = true
    ) {
        self.messagesBridge = messagesBridge
        self.requiresPresentation = requiresPresentation
        self.dismissesAfterOpen = dismissesAfterOpen
    }

    deinit {
        searchTask?.cancel()
        openTask?.cancel()
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var showsResultsPanel: Bool {
        isSearchEnabled && !trimmedQuery.isEmpty
    }

    private var isSearchEnabled: Bool {
        requiresPresentation ? isPresented : true
    }

    func present() {
        guard requiresPresentation else {
            activationToken += 1
            return
        }

        if !isPresented {
            isPresented = true
        }
        activationToken += 1
    }

    func dismiss() {
        searchTask?.cancel()
        openTask?.cancel()
        requestSequence += 1
        if requiresPresentation {
            isPresented = false
        }
        activationToken = 0
        query = ""
        results = []
        selectedResultID = nil
        status = .idle
        searchErrorMessage = nil
        openErrorMessage = nil
    }

    func updateQuery(_ value: String) {
        guard query != value else { return }
        query = value
        selectedResultID = nil
        openErrorMessage = nil

        guard isSearchEnabled else { return }
        scheduleSearch(immediate: false)
    }

    func performSearchNow() {
        guard isSearchEnabled else { return }
        scheduleSearch(immediate: true)
    }

    func retry() {
        guard isSearchEnabled else { return }
        scheduleSearch(immediate: true)
    }

    func open(_ result: ConversationSearchResult, onSuccess: (() -> Void)? = nil) {
        openTask?.cancel()
        openErrorMessage = nil
        selectedResultID = result.id

        openTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await messagesBridge.openConversationSearchResult(
                    result.conversationId,
                    messageId: result.messageId
                )
                guard !Task.isCancelled else { return }
                if dismissesAfterOpen {
                    dismiss()
                } else if selectedResultID == result.id {
                    selectedResultID = nil
                }
                onSuccess?()
            } catch {
                guard !Task.isCancelled else { return }
                if selectedResultID == result.id {
                    selectedResultID = nil
                }
                openErrorMessage = Self.errorMessage(for: error)
            }
        }
    }

    private func scheduleSearch(immediate: Bool) {
        searchTask?.cancel()
        requestSequence += 1
        let requestID = requestSequence
        let searchQuery = trimmedQuery

        guard !searchQuery.isEmpty else {
            resetSearchState()
            return
        }

        status = .loading
        searchErrorMessage = nil
        openErrorMessage = nil

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if !immediate {
                try? await Task.sleep(for: .milliseconds(180))
            }

            guard !Task.isCancelled else { return }

            do {
                let nextResults = try await messagesBridge.searchConversations(searchQuery)
                guard !Task.isCancelled else { return }
                guard requestSequence == requestID, isSearchEnabled, trimmedQuery == searchQuery else { return }

                results = nextResults
                status = .ready
                searchErrorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard requestSequence == requestID, isSearchEnabled, trimmedQuery == searchQuery else { return }

                results = []
                status = .error
                searchErrorMessage = Self.errorMessage(for: error)
            }
        }
    }

    private func resetSearchState() {
        results = []
        status = .idle
        searchErrorMessage = nil
        openErrorMessage = nil
    }

    private static func errorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(localized: "Search failed. Please try again.") : message
    }
}

enum ChatConversationSearchResultFormatter {
    static func displayTitle(for result: ConversationSearchResult) -> String {
        let title = result.conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Untitled") : title
    }

    static func displaySnippet(for result: ConversationSearchResult) -> String {
        let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? String(localized: "No preview available") : snippet
    }

    static func formattedTimestamp(_ timestamp: Double) -> String {
        let normalizedTimestamp = normalizedTimestamp(timestamp)
        let date = Date(timeIntervalSince1970: normalizedTimestamp)
        return date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }

    static func highlightedSnippet(_ snippet: String) -> Text {
        splitSnippet(snippet).reduce(Text("")) { partial, segment in
            partial + Text(segment.text)
                .fontWeight(segment.isHighlighted ? .semibold : .regular)
        }
    }

    static func searchResultAccessibilityLabel(for result: ConversationSearchResult) -> String {
        let cleanedSnippet = displaySnippet(for: result)
            .replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
        return String(
            localized: "Open search result for \(displayTitle(for: result)). \(cleanedSnippet)"
        )
    }

    private static func normalizedTimestamp(_ timestamp: Double) -> Double {
        guard timestamp.isFinite else { return Date().timeIntervalSince1970 }
        return timestamp < 100_000_000_000 ? timestamp : timestamp / 1000
    }

    private static func splitSnippet(_ snippet: String) -> [(text: String, isHighlighted: Bool)] {
        var segments: [(String, Bool)] = []
        var buffer = ""
        var isHighlighted = false
        var index = snippet.startIndex

        while index < snippet.endIndex {
            let nextIndex = snippet.index(after: index)
            let character = String(snippet[index])

            if character == "«" {
                if !buffer.isEmpty {
                    segments.append((buffer, isHighlighted))
                    buffer = ""
                }
                isHighlighted = true
            } else if character == "»" {
                if !buffer.isEmpty {
                    segments.append((buffer, isHighlighted))
                    buffer = ""
                }
                isHighlighted = false
            } else {
                buffer.append(contentsOf: snippet[index ..< nextIndex])
            }

            index = nextIndex
        }

        if !buffer.isEmpty {
            segments.append((buffer, isHighlighted))
        }

        return segments.isEmpty ? [(snippet, false)] : segments
    }
}

struct ChatConversationSearchControl: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.colorScheme) private var colorScheme

    let model: ChatConversationSearchModel
    let isExpanded: Bool
    let collapsedFrame: CGRect
    let expandedLeadingX: CGFloat

    @FocusState private var isFocused: Bool
    @State private var hoveredResultID: String?

    private var usesLiquidGlass: Bool {
        if settingsManager.shouldUseMacOS26UI {
            if #available(macOS 26.0, *) {
                return true
            }
        }
        return false
    }

    private var expandedWidth: CGFloat {
        max(collapsedFrame.width, collapsedFrame.maxX - expandedLeadingX)
    }

    private var currentWidth: CGFloat {
        isExpanded ? expandedWidth : collapsedFrame.width
    }

    private var currentX: CGFloat {
        isExpanded ? expandedLeadingX : collapsedFrame.minX
    }

    private var currentY: CGFloat {
        if !isExpanded {
            return collapsedFrame.minY
        }

        return collapsedFrame.midY - ChatConversationSearchMetrics.expandedInputHeight / 2
    }

    private var shellCornerRadius: CGFloat {
        if !isExpanded {
            return collapsedFrame.height / 2
        }
        if model.showsResultsPanel {
            return 20
        }
        return ChatConversationSearchMetrics.expandedInputHeight / 2
    }

    private var currentHeight: CGFloat {
        if !isExpanded {
            return collapsedFrame.height
        }
        return ChatConversationSearchMetrics.expandedInputHeight + resultsContainerHeight
    }

    private var searchRetryBackground: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.08)
        default:
            Color.black.opacity(0.06)
        }
    }

    private func searchResultRowFill(isHovered: Bool, isSelected: Bool) -> Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity((isSelected || isHovered) ? 0.05 : 0)
        default:
            Color.black.opacity((isSelected || isHovered) ? 0.05 : 0)
        }
    }

    private var resultsContainerHeight: CGFloat {
        guard isExpanded, model.showsResultsPanel else { return 0 }
        return ChatConversationSearchMetrics.dividerHeight + visibleResultsHeight
    }

    private var visibleResultsHeight: CGFloat {
        let inlineErrorHeight = model.openErrorMessage == nil ? 0 : ChatConversationSearchMetrics.inlineErrorHeight

        switch model.status {
        case .idle:
            return 0
        case .loading:
            return ChatConversationSearchMetrics.loadingHeight
        case .error:
            return ChatConversationSearchMetrics.errorStateHeight
        case .ready:
            if model.results.isEmpty {
                return ChatConversationSearchMetrics.emptyStateHeight
            }

            let rowsHeight =
                CGFloat(model.results.count) * ChatConversationSearchMetrics.resultRowHeight +
                CGFloat(max(0, model.results.count - 1)) * ChatConversationSearchMetrics.resultRowSpacing +
                ChatConversationSearchMetrics.resultsVerticalPadding * 2 +
                inlineErrorHeight

            return min(rowsHeight, ChatConversationSearchMetrics.resultsMaxHeight)
        }
    }

    var body: some View {
        let shellShape = RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)

        searchShell
            .frame(width: currentWidth, height: currentHeight, alignment: .topLeading)
            .chatHeaderLiquidGlassChrome(
                in: shellShape,
                usesLiquidGlass: usesLiquidGlass,
                isFocused: isFocused
            )
            .offset(x: currentX, y: currentY)
            .shadow(
                color: .black.opacity(model.isPresented ? 0.18 : 0.08),
                radius: ChatConversationSearchMetrics.shellShadowRadius,
                y: ChatConversationSearchMetrics.shellShadowY
            )
            .animation(.spring(duration: 0.34, bounce: 0.14), value: isExpanded)
            .animation(.spring(duration: 0.34, bounce: 0.14), value: model.showsResultsPanel)
            .animation(.easeInOut(duration: 0.18), value: visibleResultsHeight)
            .task(id: model.activationToken) {
                guard model.isPresented else { return }
                isFocused = false
                isFocused = true
            }
            .onChange(of: isExpanded) { _, expanded in
                if !expanded {
                    isFocused = false
                }
            }
    }

    private var searchShell: some View {
        VStack(spacing: 0) {
            inputRow

            if isExpanded, model.showsResultsPanel {
                Rectangle()
                    .fill(ChatHeaderLiquidGlassStyle.dividerColor(usesLiquidGlass: usesLiquidGlass))
                    .frame(height: ChatConversationSearchMetrics.dividerHeight)

                resultsPanel
                    .frame(height: visibleResultsHeight, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var inputRow: some View {
        if isExpanded {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "Search conversations"),
                    text: Binding(
                        get: { model.query },
                        set: { model.updateQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { model.performSearchNow() }
                .accessibilityIdentifier("Search conversations")

                if !model.query.isEmpty {
                    Button {
                        model.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear search"))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ChatConversationSearchMetrics.expandedInputHeight)
            .onExitCommand {
                model.dismiss()
            }
        } else {
            Button {
                model.present()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Search conversations (⌘F)"))
            .accessibilityIdentifier(AccessibilityID.Chat.searchButton)
            .accessibilityLabel(String(localized: "Search conversations"))
        }
    }

    private var resultsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChatConversationSearchMetrics.resultRowSpacing) {
                if let openErrorMessage = model.openErrorMessage {
                    Text(openErrorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                switch model.status {
                case .loading:
                    searchStateView(
                        title: String(localized: "Searching..."),
                        subtitle: nil,
                        showSpinner: true
                    )
                case .error:
                    searchStateView(
                        title: model.searchErrorMessage ?? String(localized: "Search failed. Please try again."),
                        subtitle: nil,
                        retryAction: model.retry
                    )
                case .ready where model.results.isEmpty:
                    searchStateView(
                        title: String(localized: "No matches found"),
                        subtitle: String(localized: "Try a shorter phrase or a different keyword.")
                    )
                case .ready:
                    ForEach(model.results) { result in
                        resultRow(result)
                    }
                case .idle:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, ChatConversationSearchMetrics.resultsVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .clipped()
    }

    private func resultRow(_ result: ConversationSearchResult) -> some View {
        let isSelected = model.selectedResultID == result.id
        let isHovered = hoveredResultID == result.id

        return Button {
            model.open(result)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(displayTitle(for: result))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formattedTimestamp(result.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                highlightedSnippet(displaySnippet(for: result))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(searchResultRowFill(isHovered: isHovered, isSelected: isSelected))
            )
            .opacity(isSelected ? 0.55 : 1)
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
        .accessibilityLabel(searchResultAccessibilityLabel(for: result))
    }

    private func searchStateView(
        title: String,
        subtitle: String?,
        showSpinner: Bool = false,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(showSpinner ? .secondary : .primary)
                .multilineTextAlignment(.center)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction {
                Button(String(localized: "Try again")) {
                    retryAction()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(searchRetryBackground, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: visibleResultsHeight, alignment: .center)
    }

    private func displayTitle(for result: ConversationSearchResult) -> String {
        ChatConversationSearchResultFormatter.displayTitle(for: result)
    }

    private func displaySnippet(for result: ConversationSearchResult) -> String {
        ChatConversationSearchResultFormatter.displaySnippet(for: result)
    }

    private func formattedTimestamp(_ timestamp: Double) -> String {
        ChatConversationSearchResultFormatter.formattedTimestamp(timestamp)
    }

    private func highlightedSnippet(_ snippet: String) -> Text {
        ChatConversationSearchResultFormatter.highlightedSnippet(snippet)
    }

    private func searchResultAccessibilityLabel(for result: ConversationSearchResult) -> String {
        ChatConversationSearchResultFormatter.searchResultAccessibilityLabel(for: result)
    }
}
