import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers
import WebKit

@MainActor
final class FilePreviewWindowController {
    static let shared = FilePreviewWindowController()

    private let viewController = FilePreviewViewController()
    private var window: NSWindow?

    private init() {}

    func show(
        fileURL: URL,
        title: String? = nil,
        quickLookSourceFrameOnScreen: CGRect? = nil,
        quickLookTransitionImage: NSImage? = nil
    ) {
        switch previewRoute(for: fileURL) {
        case .systemOpen:
            dismissCustomPreview()
            NSWorkspace.shared.open(fileURL)
            return
        case .quickLook:
            dismissCustomPreview()
            QuickLookController.shared.show(
                urls: [fileURL],
                sourceFrameOnScreen: quickLookSourceFrameOnScreen,
                transitionImage: quickLookTransitionImage
            )
            return
        case .embedded:
            break
        }

        let window = window ?? makeWindow()
        self.window = window

        viewController.load(fileURL: fileURL, title: title)
        window.title = title ?? fileURL.lastPathComponent
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: viewController)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 980, height: 720))
        window.center()
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 28
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }
        return window
    }

    private enum PreviewRoute {
        case embedded
        case quickLook
        case systemOpen
    }

    private func previewRoute(for fileURL: URL) -> PreviewRoute {
        if isMarkdownFile(fileURL) {
            return .embedded
        }

        guard let type = PreviewPayloadBuilder.contentType(for: fileURL) else {
            return .quickLook
        }

        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .systemOpen
        }

        return .quickLook
    }

    private func dismissCustomPreview() {
        window?.orderOut(nil)
    }

    private func isMarkdownFile(_ fileURL: URL) -> Bool {
        switch fileURL.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            true
        default:
            false
        }
    }
}

@MainActor
private final class FilePreviewViewController: NSViewController {
    fileprivate static let previewScheme = "openbridgepreview"
    private static let headerHeight: CGFloat = 52

    private let schemeHandler = PreviewResourceSchemeHandler()
    private let bridgeController: WebKitBridgeController
    private var currentPayload: PreviewPayload?
    private var currentSurfaceURL: URL

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.previewScheme)
        #if DEBUG
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let initialURL = EmbeddedSurfaceURLResolver.url(for: .preview)

        bridgeController = WebKitBridgeController(
            url: initialURL,
            configuration: configuration
        )
        currentSurfaceURL = initialURL

        super.init(nibName: nil, bundle: nil)

        bridgeController.registerMessageHandler(named: "previewReady") { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pushCurrentPayload()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        view = rootView

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.state = .active
        backgroundView.blendingMode = .behindWindow
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor

        let webView = bridgeController.bridge.webView
        let headerView = PreviewWindowHeaderView()
        let closeButton = makeCloseButton()

        headerView.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        view.addSubview(backgroundView)
        view.addSubview(headerView)
        view.addSubview(webView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeCloseButton() -> NSButton {
        let button = NSButton()
        let configuration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Close Preview"))?
            .withSymbolConfiguration(configuration)
        button.isBordered = false
        button.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(closePreview)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc
    private func closePreview() {
        view.window?.performClose(nil)
    }

    func load(fileURL: URL, title: String?) {
        refreshSurfaceIfNeeded()
        let payload = PreviewPayloadBuilder.build(
            fileURL: fileURL,
            title: title,
            resourceURL: schemeHandler.register(fileURL: fileURL)
        )
        currentPayload = payload
        pushCurrentPayload()
    }

    private func pushCurrentPayload() {
        guard let payload = currentPayload else { return }

        Task { @MainActor [bridgeController] in
            do {
                try await bridgeController.bridge.waitUntilReady(timeout: 5)
                let data = try JSONEncoder().encode(payload)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    return
                }

                _ = try await bridgeController.bridge.webView.evaluateJavaScriptAsync(
                    """
                    if (window.updateFilePreview) {
                        window.updateFilePreview(\(jsonString));
                    }
                    """
                )
            } catch {
                Logger.ui.error("Failed to push preview payload: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func refreshSurfaceIfNeeded() {
        let resolvedURL = EmbeddedSurfaceURLResolver.url(for: .preview)
        guard resolvedURL != currentSurfaceURL else { return }
        currentSurfaceURL = resolvedURL
        bridgeController.load(url: resolvedURL)
    }
}

private final class PreviewWindowHeaderView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .behindWindow
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct PreviewPayload: Encodable {
    let title: String
    let fileName: String
    let kind: String
    let content: String?
    let resourceURL: String?
    let mimeType: String?
    let message: String?
}

private enum PreviewPayloadBuilder {
    static func build(fileURL: URL, title: String?, resourceURL: URL?) -> PreviewPayload {
        let previewTitle = title ?? fileURL.lastPathComponent
        let fileName = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        if isMarkdownFile(fileURL), let text = loadText(from: fileURL) {
            return PreviewPayload(
                title: previewTitle,
                fileName: fileName,
                kind: "markdown",
                content: text,
                resourceURL: nil,
                mimeType: mimeType,
                message: nil
            )
        }

        if isMarkdownFile(fileURL) {
            return PreviewPayload(
                title: previewTitle,
                fileName: fileName,
                kind: "markdown_error",
                content: nil,
                resourceURL: nil,
                mimeType: mimeType,
                message: "This Markdown file couldn't be rendered. The file may be missing, unreadable, or encoded in an unsupported format."
            )
        }

        if let type = contentType(for: fileURL) {
            if type.conforms(to: .image) {
                return mediaPayload(kind: "image", title: previewTitle, fileName: fileName, resourceURL: resourceURL, mimeType: mimeType)
            }

            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return mediaPayload(kind: "video", title: previewTitle, fileName: fileName, resourceURL: resourceURL, mimeType: mimeType)
            }

            if type.conforms(to: .audio) {
                return mediaPayload(kind: "audio", title: previewTitle, fileName: fileName, resourceURL: resourceURL, mimeType: mimeType)
            }

            if type.conforms(to: .pdf) {
                return mediaPayload(kind: "pdf", title: previewTitle, fileName: fileName, resourceURL: resourceURL, mimeType: mimeType)
            }

            if type.conforms(to: .text), let text = loadText(from: fileURL) {
                return PreviewPayload(
                    title: previewTitle,
                    fileName: fileName,
                    kind: "text",
                    content: text,
                    resourceURL: nil,
                    mimeType: mimeType,
                    message: nil
                )
            }
        }

        if let text = loadText(from: fileURL) {
            return PreviewPayload(
                title: previewTitle,
                fileName: fileName,
                kind: "text",
                content: text,
                resourceURL: nil,
                mimeType: mimeType,
                message: nil
            )
        }

        return PreviewPayload(
            title: previewTitle,
            fileName: fileName,
            kind: "unsupported",
            content: nil,
            resourceURL: resourceURL?.absoluteString,
            mimeType: mimeType,
            message: nil
        )
    }

    private static func mediaPayload(
        kind: String,
        title: String,
        fileName: String,
        resourceURL: URL?,
        mimeType: String?
    ) -> PreviewPayload {
        PreviewPayload(
            title: title,
            fileName: fileName,
            kind: kind,
            content: nil,
            resourceURL: resourceURL?.absoluteString,
            mimeType: mimeType,
            message: nil
        )
    }

    static func contentType(for fileURL: URL) -> UTType? {
        if let type = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: fileURL.pathExtension.lowercased())
    }

    private static func mimeType(for fileURL: URL) -> String? {
        contentType(for: fileURL)?.preferredMIMEType
    }

    private static func loadText(from fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? String(data: data, encoding: .utf16)
    }

    private static func isMarkdownFile(_ fileURL: URL) -> Bool {
        switch fileURL.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            true
        default:
            false
        }
    }
}

private final class PreviewResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct Resource {
        let fileURL: URL
        let mimeType: String
        let expectedLength: Int
    }

    private let lock = NSLock()
    private var resources: [String: Resource] = [:]

    func register(fileURL: URL) -> URL? {
        let mimeType = PreviewPayloadBuilder.contentType(for: fileURL)?.preferredMIMEType ?? "application/octet-stream"
        let expectedLength = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let token = UUID().uuidString
        let encodedName = fileURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.lastPathComponent

        lock.lock()
        resources = [token: Resource(fileURL: fileURL, mimeType: mimeType, expectedLength: expectedLength)]
        lock.unlock()

        return URL(string: "\(FilePreviewViewController.previewScheme)://preview/\(token)/\(encodedName)")
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard
            let url = urlSchemeTask.request.url,
            let token = url.pathComponents.dropFirst().first,
            let resource = resource(for: token)
        else {
            urlSchemeTask.didFailWithError(PreviewError.resourceNotFound)
            return
        }

        do {
            let response = URLResponse(
                url: url,
                mimeType: resource.mimeType,
                expectedContentLength: resource.expectedLength,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)

            let handle = try FileHandle(forReadingFrom: resource.fileURL)
            defer { try? handle.close() }

            while true {
                guard let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty else {
                    break
                }
                urlSchemeTask.didReceive(data)
            }

            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        _ = urlSchemeTask
    }

    private func resource(for token: String) -> Resource? {
        lock.lock()
        defer { lock.unlock() }
        return resources[token]
    }
}

private enum PreviewError: LocalizedError {
    case resourceNotFound

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "Preview resource not found"
        }
    }
}
