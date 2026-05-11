import SwiftUI
import WebKit

/// View model for skill import dialog
@MainActor
@Observable
final class SkillImportViewModel {
    enum State {
        case loading
        case loaded(SkillInfo)
        case error(String)
        case importing
    }

    private(set) var state: State = .loading
    private(set) var name: String = ""
    private(set) var source: SkillSource = .official
    private(set) var repo: String?
    private(set) var isAlreadyImported: Bool = false

    var onImport: ((SkillInfo) -> Void)?
    var onCancel: (() -> Void)?

    func load(name: String, source: SkillSource = .official, repo: String? = nil) {
        self.name = name
        self.source = source
        self.repo = repo
        state = .loading
        updateImportedState()

        Task {
            try? await SkillLockManager.shared.ensureLoaded()
            updateImportedState()

            do {
                let info = try await SkillManager.shared.fetchSkillInfo(name: name, source: source, repo: repo)
                state = .loaded(info)
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func confirmImport() {
        guard case let .loaded(info) = state else { return }
        state = .importing
        onImport?(info)
    }

    func cancel() {
        onCancel?()
    }

    private func updateImportedState() {
        let lockKey = if source == .external, let repo {
            "\(repo)/\(name)"
        } else {
            name
        }

        isAlreadyImported =
            SkillManager.shared.skills.contains { skill in
                skill.category == .imported && skill.lockKey == lockKey
            } ||
            SkillLockManager.shared.getEntry(lockKey: lockKey) != nil
    }
}

/// Skill import confirmation dialog
struct SkillImportView: View {
    @Bindable var viewModel: SkillImportViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Content
            switch viewModel.state {
            case .loading:
                loadingView
            case let .loaded(info):
                previewView(info: info)
            case let .error(message):
                errorView(message: message)
            case .importing:
                importingView
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Spacer()
                Button(String(localized: "Cancel")) {
                    viewModel.cancel()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Button(viewModel.isAlreadyImported
                    ? String(localized: "Update and Use Skill")
                    : String(localized: "Try Skill"))
                {
                    viewModel.confirmImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canImport)
            }
            .padding(20)
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: externalHasContent ? 420 : (viewModel.source == .external ? 280 : 480))
        .safeGlassEffect(in: RoundedRectangle(cornerRadius: 16))
    }

    private var externalHasContent: Bool {
        if case let .loaded(info) = viewModel.state {
            return viewModel.source == .external && info.contentHtml != nil
        }
        return false
    }

    private var canImport: Bool {
        if case .loaded = viewModel.state {
            return true
        }
        return false
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading skill...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func previewView(info: SkillInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(viewModel.isAlreadyImported
                ? String(localized: "Update skill")
                : String(localized: "Add skill to OpenBridge"))
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // Media carousel (only show if video or hero image exists)
            if info.videoURL != nil || info.heroURL != nil {
                SkillMediaCarousel(videoURL: info.videoURL, heroURL: info.heroURL)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Skill info
            VStack(alignment: .leading, spacing: 12) {
                // Skill name
                HStack(spacing: 6) {
                    if viewModel.source == .external {
                        Image("github")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    Text(info.displayName ?? info.name)
                        .font(.title3.weight(.semibold))
                }

                if let description = info.description {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)

            // Rendered SKILL.md content
            if let contentHtml = info.contentHtml {
                Divider()
                    .padding(.horizontal, 20)
                SkillContentWebView(html: contentHtml)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Failed to load skill")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Importing skill...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Skill Content WebView

private struct SkillContentWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context _: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadContent(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        loadContent(webView)
    }

    private func loadContent(_ webView: WKWebView) {
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                line-height: 1.5;
                color: -apple-system-label;
                padding: 16px;
                -webkit-font-smoothing: antialiased;
            }
            @media (prefers-color-scheme: dark) {
                body { color: rgba(255,255,255,0.85); }
                a { color: #6cb4ff; }
                code { background: rgba(255,255,255,0.1); }
                pre { background: rgba(255,255,255,0.06); }
            }
            @media (prefers-color-scheme: light) {
                body { color: rgba(0,0,0,0.85); }
                a { color: #0066cc; }
                code { background: rgba(0,0,0,0.06); }
                pre { background: rgba(0,0,0,0.04); }
            }
            h1 { font-size: 18px; margin-bottom: 8px; }
            h2 { font-size: 15px; margin-top: 16px; margin-bottom: 6px; }
            h3 { font-size: 13px; margin-top: 12px; margin-bottom: 4px; }
            p { margin-bottom: 8px; }
            ul, ol { padding-left: 20px; margin-bottom: 8px; }
            li { margin-bottom: 2px; }
            code {
                font-family: Menlo, monospace;
                font-size: 12px;
                padding: 1px 4px;
                border-radius: 3px;
            }
            pre {
                padding: 10px;
                border-radius: 6px;
                overflow-x: auto;
                margin-bottom: 8px;
            }
            pre code { padding: 0; background: none; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }
}

#Preview {
    let viewModel = SkillImportViewModel()
    return SkillImportView(viewModel: viewModel)
        .onAppear {
            viewModel.load(name: "test-skill", source: .official)
        }
}
