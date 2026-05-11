import AppKit
import Carbon.HIToolbox
import Combine
import ComposerEditor
import Foundation
import NotchKit
import OSLog

private let automationToolLogger = Logger(
    subsystem: Logger.loggingSubsystem,
    category: "BridgeAutomationToolService"
)

private final class AutomationClickIndicatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = frameRect.width / 2
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 3
        layer?.shadowOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

enum BridgeAutomationToolError: LocalizedError {
    case unknownWindow(String)
    case windowNotVisible(String)
    case windowCaptureFailed(String)
    case windowCaptureWriteFailed(String)
    case unsupportedAction(String)
    case unsupportedKey(String)
    case unsupportedModifier(String)
    case invalidCoordinates(window: String, x: Double, y: Double)
    case noFocusedInput(String)
    case invalidPath(String)
    case fileNotFound(String)
    case imagePathRequired(String)
    case emptySelection

    var errorDescription: String? {
        switch self {
        case let .unknownWindow(name):
            "unknown window: \(name)"
        case let .windowNotVisible(name):
            "window is not visible: \(name)"
        case let .windowCaptureFailed(name):
            "failed to capture window: \(name)"
        case let .windowCaptureWriteFailed(name):
            "failed to write window capture: \(name)"
        case let .unsupportedAction(action):
            "unsupported action: \(action)"
        case let .unsupportedKey(key):
            "unsupported key: \(key)"
        case let .unsupportedModifier(modifier):
            "unsupported modifier: \(modifier)"
        case let .invalidCoordinates(window, x, y):
            "invalid coordinates for \(window): (\(x), \(y))"
        case let .noFocusedInput(window):
            "no focused input in \(window)"
        case let .invalidPath(path):
            "invalid path: \(path)"
        case let .fileNotFound(path):
            "file not found: \(path)"
        case let .imagePathRequired(path):
            "path is not a supported image file: \(path)"
        case .emptySelection:
            "selection cannot be empty"
        }
    }
}

@MainActor
final class BridgeAutomationToolService {
    static let shared = BridgeAutomationToolService()

    private init() {}

    func listWindows() -> BridgeAutomationWindowListPayload {
        let managedWindows = Windows.Kind.allCases.map(summary(for:))
        let managedWindowNumbers = Set(managedWindows.map(\.windowNumber))
        let notch = notchWindowSummary(excluding: managedWindowNumbers)
        return BridgeAutomationWindowListPayload(
            windows: managedWindows,
            notch: notch,
            transient: transientWindowSummaries(excluding: managedWindowNumbers)
        )
    }

    func openWindow(named name: String) async throws -> BridgeAutomationWindowSummary {
        let kind = try resolveWindowKind(named: name)
        let window = await prepareWindow(for: kind)
        return summary(for: kind, window: window)
    }

    func closeWindow(named name: String) throws -> BridgeAutomationWindowSummary {
        if let kind = Windows.Kind(automationName: name) {
            let window = try visibleWindow(for: kind)
            activateWindowForAutomation(window)
            Windows.shared.close(kind, animated: false)
            return summary(for: kind, window: window)
        }

        let target = try visibleAutomationTarget(named: name)
        activateWindowForAutomation(target.window)
        target.window.close()
        return summary(
            named: target.automationName,
            window: target.window,
            kind: target.summaryKind
        )
    }

    func captureWindow(named name: String) async throws -> BridgeAutomationCaptureResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)
        let image = try captureImage(windowName: target.automationName, window: window)
        guard let pngData = image.pngData() else {
            throw BridgeAutomationToolError.windowCaptureFailed(target.automationName)
        }
        let outputURL = try writeCaptureImage(
            pngData: pngData,
            window: target.automationName
        )

        return BridgeAutomationCaptureResult(
            window: target.automationName,
            path: outputURL.path,
            width: image.width,
            height: image.height,
            scale: effectiveScale(for: window, capturedImage: image),
            frame: BridgeAutomationRect(window.frame)
        )
    }

    func pointClick(window name: String, x: Double, y: Double) async throws -> BridgeAutomationPointClickResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)
        let scale = try coordinateScale(
            windowName: target.automationName,
            window: window
        )
        let point = try resolvedPoint(
            windowName: target.automationName,
            window: window,
            x: x,
            y: y,
            scale: scale
        )
        showClickIndicator(at: point.pointInRoot, in: point.rootView)
        let route = try await dispatchAppKitClick(
            atWindowPoint: point.pointInWindow,
            rootPoint: point.pointInRoot,
            in: window,
            rootView: point.rootView
        )
        return BridgeAutomationPointClickResult(
            window: target.automationName,
            x: x,
            y: y,
            performed: true,
            route: route,
            elementId: nil
        )
    }

    func pointDoubleClick(window name: String, x: Double, y: Double) async throws -> BridgeAutomationPointClickResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)
        let scale = try coordinateScale(
            windowName: target.automationName,
            window: window
        )
        let point = try resolvedPoint(
            windowName: target.automationName,
            window: window,
            x: x,
            y: y,
            scale: scale
        )
        showClickIndicator(at: point.pointInRoot, in: point.rootView)
        let route = try dispatchAppKitDoubleClick(
            atWindowPoint: point.pointInWindow,
            in: window
        )
        return BridgeAutomationPointClickResult(
            window: target.automationName,
            x: x,
            y: y,
            performed: true,
            route: route,
            elementId: nil
        )
    }

    func scroll(
        window name: String,
        x: Double,
        y: Double,
        deltaX: Double,
        deltaY: Double
    ) async throws -> BridgeAutomationScrollResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)
        let scale = try coordinateScale(
            windowName: target.automationName,
            window: window
        )
        let point = try resolvedPoint(
            windowName: target.automationName,
            window: window,
            x: x,
            y: y,
            scale: scale
        )
        let route = try dispatchAppKitScroll(
            atWindowPoint: point.pointInWindow,
            rootPoint: point.pointInRoot,
            deltaX: deltaX,
            deltaY: deltaY,
            in: window,
            rootView: point.rootView,
            scale: point.scale
        )
        return BridgeAutomationScrollResult(
            window: target.automationName,
            x: x,
            y: y,
            deltaX: deltaX,
            deltaY: deltaY,
            performed: true,
            route: route
        )
    }

    func type(window name: String, text: String) async throws -> BridgeAutomationTypeResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)

        let route = try dispatchAppKitTextInput(
            text,
            in: window
        )

        return BridgeAutomationTypeResult(
            window: target.automationName,
            textLength: text.count,
            performed: true,
            route: route
        )
    }

    func pressKey(window name: String, key: String, modifiers: [String]) async throws -> BridgeAutomationPressKeyResult {
        let target = try visibleAutomationTarget(named: name)
        let window = target.window
        activateWindowForAutomation(window)

        let normalizedKey = normalizeKeyName(key)
        let modifierFlags = try modifierFlags(from: modifiers)
        let route = try dispatchAppKitKeyPress(
            key: normalizedKey,
            modifiers: modifierFlags,
            in: window
        )

        return BridgeAutomationPressKeyResult(
            window: target.automationName,
            key: normalizedKey,
            modifiers: modifiers.map { $0.lowercased() },
            performed: true,
            route: route
        )
    }

    func chatAddFile(path: String) throws -> BridgeAutomationChatAttachmentResult {
        try queueChatAttachment(path: path, requireImage: false)
    }

    func chatAddImage(path: String) throws -> BridgeAutomationChatAttachmentResult {
        try queueChatAttachment(path: path, requireImage: true)
    }

    func chatSend(text: String) throws -> BridgeAutomationChatSendResult {
        let target = try visibleAutomationTarget(named: "chat")
        activateWindowForAutomation(target.window)

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw BridgeAutomationToolError.unsupportedAction("chat.send requires non-empty text")
        }

        let submission = ChatEditorViewModel.Submission(
            text: trimmedText,
            attachments: [],
            quote: nil,
            reasoningEffort: nil
        )
        ContinueInChatManager.shared.submissionPublisher.send(submission)

        return BridgeAutomationChatSendResult(
            window: "chat",
            textLength: trimmedText.count,
            performed: true,
            route: "chat_submission_publisher"
        )
    }

    func filePickerSelect(paths: [String]) throws -> BridgeAutomationFilePickerSelectResult {
        guard !paths.isEmpty else {
            throw BridgeAutomationToolError.emptySelection
        }

        activateBridgeForAutomation()
        let urls = try paths.map { try automationFileURL(from: $0, requireImage: false) }
        let result = try FilePicker.fulfillAutomationSelection(with: urls)

        return BridgeAutomationFilePickerSelectResult(
            pathCount: urls.count,
            performed: true,
            route: result.route,
            requestMessage: result.requestMessage,
            paths: urls.map(\.path)
        )
    }

    func filePickerCancel() -> BridgeAutomationFilePickerCancelResult {
        activateBridgeForAutomation()
        let result = FilePicker.cancelAutomationSelection()
        return BridgeAutomationFilePickerCancelResult(
            performed: true,
            route: result.route,
            requestMessage: result.requestMessage
        )
    }
}

private extension BridgeAutomationToolService {
    struct MouseDispatchEvent {
        let type: NSEvent.EventType
        let timestamp: TimeInterval
        let clickCount: Int
        let pressure: Float
    }

    struct AutomationWindowTarget {
        let automationName: String
        let summaryKind: String
        let window: NSWindow
    }

    struct ResolvedWindowPoint {
        let rootView: NSView
        let scale: Double
        let pointInRoot: CGPoint
        let pointInWindow: CGPoint
    }

    func resolveWindowKind(named name: String) throws -> Windows.Kind {
        guard let kind = Windows.Kind(automationName: name) else {
            throw BridgeAutomationToolError.unknownWindow(name)
        }
        return kind
    }

    func summary(for kind: Windows.Kind) -> BridgeAutomationWindowSummary {
        let window = Windows.shared.windowInstance(for: kind)
        return summary(for: kind, window: window)
    }

    func summary(for kind: Windows.Kind, window: NSWindow) -> BridgeAutomationWindowSummary {
        summary(named: kind.automationName, window: window, kind: "managed")
    }

    func summary(named name: String, window: NSWindow, kind: String) -> BridgeAutomationWindowSummary {
        BridgeAutomationWindowSummary(
            window: name,
            title: windowTitle(for: window, kind: kind),
            isVisible: window.isVisible,
            frame: BridgeAutomationRect(window.frame),
            scale: effectiveScale(for: window),
            kind: kind,
            windowNumber: window.windowNumber
        )
    }

    func windowTitle(for window: NSWindow, kind: String) -> String {
        if kind == "managed" {
            return window.title
        }
        if kind == "notch" {
            return "Notch"
        }
        return transientWindowTitle(for: window)
    }

    func notchWindowSummary(excluding managedWindowNumbers: Set<Int>) -> BridgeAutomationWindowSummary? {
        guard let window = visibleNotchWindow(excluding: managedWindowNumbers) else {
            return nil
        }
        return summary(named: "notch", window: window, kind: "notch")
    }

    func transientWindowSummaries(excluding managedWindowNumbers: Set<Int>) -> [BridgeAutomationWindowSummary] {
        visibleTransientWindows(excluding: managedWindowNumbers)
            .sorted { lhs, rhs in
                lhs.windowNumber < rhs.windowNumber
            }
            .map(transientSummary(for:))
    }

    func transientSummary(for window: NSWindow) -> BridgeAutomationWindowSummary {
        summary(
            named: transientAutomationName(for: window),
            window: window,
            kind: "transient"
        )
    }

    func transientAutomationName(for window: NSWindow) -> String {
        if isCommandMenuWindow(window) {
            return "commandMenu"
        }
        if window is NSPanel {
            return "panel_\(window.windowNumber)"
        }
        return "window_\(window.windowNumber)"
    }

    func transientWindowTitle(for window: NSWindow) -> String {
        if isCommandMenuWindow(window) {
            return "Command Menu"
        }
        let trimmedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if window is NSPanel {
            return "Panel"
        }
        return "Window"
    }

    func isCommandMenuWindow(_ window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        return NSStringFromClass(Swift.type(of: contentView)).contains("CommandMenuView")
    }

    func isNotchWindow(_ window: NSWindow) -> Bool {
        NotchWindowMetadata.isAutomationWindow(window)
    }

    func shouldExposeTransientWindow(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0, window.windowNumber < Int(Int32.max) else {
            return false
        }

        if isNotchWindow(window) {
            return false
        }

        if isCommandMenuWindow(window) {
            return true
        }

        if window is NSPanel {
            return true
        }

        return window.level.rawValue > NSWindow.Level.normal.rawValue
    }

    func visibleNotchWindow(excluding managedWindowNumbers: Set<Int>) -> NSWindow? {
        NSApp.windows
            .filter { window in
                window.isVisible
                    && !managedWindowNumbers.contains(window.windowNumber)
                    && isNotchWindow(window)
            }
            .sorted { lhs, rhs in
                lhs.windowNumber < rhs.windowNumber
            }
            .first
    }

    func visibleTransientWindows(excluding managedWindowNumbers: Set<Int>) -> [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible
                && !managedWindowNumbers.contains(window.windowNumber)
                && shouldExposeTransientWindow(window)
        }
    }

    func visibleAutomationTarget(named name: String) throws -> AutomationWindowTarget {
        if let kind = Windows.Kind(automationName: name) {
            let window = try visibleWindow(for: kind)
            return AutomationWindowTarget(
                automationName: kind.automationName,
                summaryKind: "managed",
                window: window
            )
        }

        let managedWindowNumbers = Set(Windows.Kind.allCases.map { kind in
            Windows.shared.windowInstance(for: kind).windowNumber
        })

        if name == "notch" {
            guard let window = visibleNotchWindow(excluding: managedWindowNumbers) else {
                throw BridgeAutomationToolError.windowNotVisible(name)
            }
            return AutomationWindowTarget(
                automationName: "notch",
                summaryKind: "notch",
                window: window
            )
        }

        if let window = visibleTransientWindows(excluding: managedWindowNumbers).first(where: {
            transientAutomationName(for: $0) == name
        }) {
            return AutomationWindowTarget(
                automationName: name,
                summaryKind: "transient",
                window: window
            )
        }

        if isDynamicAutomationWindowName(name) {
            throw BridgeAutomationToolError.windowNotVisible(name)
        }
        throw BridgeAutomationToolError.unknownWindow(name)
    }

    func isDynamicAutomationWindowName(_ name: String) -> Bool {
        name == "notch"
            || name == "commandMenu"
            || name.hasPrefix("panel_")
            || name.hasPrefix("window_")
    }

    func prepareWindow(for kind: Windows.Kind) async -> NSWindow {
        Windows.shared.open(kind, animated: false)
        let window = Windows.shared.windowInstance(for: kind)
        activateWindowForAutomation(window)

        try? await Task.sleep(for: .milliseconds(150))
        return window
    }

    func visibleWindow(for kind: Windows.Kind) throws -> NSWindow {
        let window = Windows.shared.windowInstance(for: kind)
        guard window.isVisible else {
            throw BridgeAutomationToolError.windowNotVisible(kind.automationName)
        }
        return window
    }

    func queueChatAttachment(path: String, requireImage: Bool) throws -> BridgeAutomationChatAttachmentResult {
        let window = try visibleWindow(for: .chat)
        activateWindowForAutomation(window)

        let fileURL = try automationFileURL(from: path, requireImage: requireImage)
        ContinueInChatManager.shared.addFileURLsToComposer([fileURL])

        return BridgeAutomationChatAttachmentResult(
            window: Windows.Kind.chat.automationName,
            path: fileURL.path,
            filename: fileURL.lastPathComponent,
            contentType: fileURL.detectedMimeType(),
            attachmentType: attachmentType(for: fileURL),
            performed: true,
            route: "chat_attachment_urls"
        )
    }

    func activateBridgeForAutomation() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func activateWindowForAutomation(_ window: NSWindow) {
        activateBridgeForAutomation()
        window.focus()
        window.displayIfNeeded()
        window.contentView?.displayIfNeeded()
    }

    func automationFileURL(from rawPath: String, requireImage: Bool) throws -> URL {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw BridgeAutomationToolError.invalidPath(rawPath)
        }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let absolutePath = if expandedPath.hasPrefix("/") {
            expandedPath
        } else {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expandedPath)
                .path
        }

        let fileURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            throw BridgeAutomationToolError.fileNotFound(fileURL.path)
        }

        if requireImage {
            guard !isDirectory.boolValue,
                  let contentType = fileURL.detectedMimeType(),
                  contentType.hasPrefix("image/")
            else {
                throw BridgeAutomationToolError.imagePathRequired(fileURL.path)
            }
        }

        return fileURL
    }

    func attachmentType(for fileURL: URL) -> String {
        if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return "directory"
        }
        if fileURL.detectedMimeType()?.hasPrefix("image/") == true {
            return "image"
        }
        return "file"
    }

    func captureImage(windowName: String, window: NSWindow) throws -> CGImage {
        let windowID = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            automationToolLogger.error("Failed to capture window \(windowName, privacy: .public)")
            throw BridgeAutomationToolError.windowCaptureFailed(windowName)
        }
        return image
    }

    func writeCaptureImage(pngData: Data, window: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-automation-captures", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = directoryURL
                .appendingPathComponent("\(window)-\(UUID().uuidString.lowercased())")
                .appendingPathExtension("png")
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            automationToolLogger.error(
                "Failed to write capture for \(window, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw BridgeAutomationToolError.windowCaptureWriteFailed(window)
        }
    }

    func effectiveScale(for window: NSWindow, capturedImage: CGImage? = nil) -> Double {
        if let capturedImage, window.frame.width > 0 {
            let derivedScale = Double(capturedImage.width) / Double(window.frame.width)
            if derivedScale.isFinite, derivedScale > 0 {
                return derivedScale
            }
        }

        let scale = window.screen?.backingScaleFactor ?? window.backingScaleFactor
        return max(1, Double(scale))
    }

    func coordinateScale(windowName: String, window: NSWindow) throws -> Double {
        if let image = try? captureImage(windowName: windowName, window: window) {
            return effectiveScale(for: window, capturedImage: image)
        }
        return effectiveScale(for: window)
    }

    func appKitRootView(for window: NSWindow) -> NSView? {
        window.contentView?.superview ?? window.contentView
    }

    func resolvedPoint(
        windowName: String,
        window: NSWindow,
        x: Double,
        y: Double,
        scale: Double
    ) throws -> ResolvedWindowPoint {
        guard let rootView = appKitRootView(for: window) else {
            throw BridgeAutomationToolError.unsupportedAction("point_resolution")
        }
        rootView.displayIfNeeded()
        let maxX = Double(rootView.bounds.width) * scale
        let maxY = Double(rootView.bounds.height) * scale
        guard x >= 0, y >= 0, x < maxX, y < maxY else {
            throw BridgeAutomationToolError.invalidCoordinates(
                window: windowName,
                x: x,
                y: y
            )
        }

        let pointInRoot = viewPoint(forPixelX: x, y: y, scale: scale, in: rootView)
        let pointInWindow = rootView.convert(pointInRoot, to: nil)
        return ResolvedWindowPoint(
            rootView: rootView,
            scale: scale,
            pointInRoot: pointInRoot,
            pointInWindow: pointInWindow
        )
    }

    func viewPoint(forPixelX x: Double, y: Double, scale: Double, in view: NSView) -> CGPoint {
        CGPoint(
            x: x / scale,
            y: view.isFlipped ? (y / scale) : view.bounds.height - (y / scale)
        )
    }

    func showClickIndicator(at point: CGPoint, in rootView: NSView) {
        let indicatorDiameter: CGFloat = 12
        let frame = CGRect(
            x: point.x - indicatorDiameter / 2,
            y: point.y - indicatorDiameter / 2,
            width: indicatorDiameter,
            height: indicatorDiameter
        )
        let indicator = AutomationClickIndicatorView(frame: frame)
        indicator.alphaValue = 0.95
        rootView.addSubview(indicator)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard indicator.superview != nil else {
                return
            }
            indicator.removeFromSuperview()
        }
    }

    func dispatchAppKitClick(
        atWindowPoint pointInWindow: CGPoint,
        rootPoint _: CGPoint,
        in window: NSWindow,
        rootView _: NSView
    ) async throws -> String {
        try dispatchWindowClickFallback(
            atWindowPoint: pointInWindow,
            in: window
        )
        return "appkit_window_event"
    }

    func dispatchWindowClickFallback(
        atWindowPoint pointInWindow: CGPoint,
        in window: NSWindow
    ) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ), let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            throw BridgeAutomationToolError.unsupportedAction("point_click")
        }

        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
    }

    func dispatchAppKitDoubleClick(
        atWindowPoint pointInWindow: CGPoint,
        in window: NSWindow
    ) throws -> String {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = [
            MouseDispatchEvent(type: .leftMouseDown, timestamp: timestamp, clickCount: 1, pressure: 1),
            MouseDispatchEvent(type: .leftMouseUp, timestamp: timestamp + 0.01, clickCount: 1, pressure: 0),
            MouseDispatchEvent(type: .leftMouseDown, timestamp: timestamp + 0.02, clickCount: 2, pressure: 1),
            MouseDispatchEvent(type: .leftMouseUp, timestamp: timestamp + 0.03, clickCount: 2, pressure: 0),
        ]

        for eventSpec in events {
            guard let event = NSEvent.mouseEvent(
                with: eventSpec.type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: eventSpec.timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: eventSpec.clickCount - 1,
                clickCount: eventSpec.clickCount,
                pressure: eventSpec.pressure
            ) else {
                throw BridgeAutomationToolError.unsupportedAction("point_double_click")
            }
            window.sendEvent(event)
        }

        return "appkit_window_double_click"
    }

    func dispatchAppKitScroll(
        atWindowPoint pointInWindow: CGPoint,
        rootPoint: CGPoint,
        deltaX: Double,
        deltaY: Double,
        in window: NSWindow,
        rootView: NSView,
        scale: Double
    ) throws -> String {
        guard let hitView = rootView.hitTest(rootPoint) else {
            throw BridgeAutomationToolError.unsupportedAction("scroll")
        }

        let pointDeltaX = CGFloat(deltaX / scale)
        let pointDeltaY = CGFloat(deltaY / scale)

        if let scrollView = viewAncestors(startingAt: hitView).first(where: { $0 is NSScrollView }) as? NSScrollView,
           let documentView = scrollView.documentView
        {
            let clipView = scrollView.contentView
            let documentBounds = documentView.bounds
            let visibleRect = clipView.documentVisibleRect
            let maxOriginX = max(0, documentBounds.width - visibleRect.width)
            let maxOriginY = max(0, documentBounds.height - visibleRect.height)
            let targetOriginX = min(max(0, visibleRect.origin.x + pointDeltaX), maxOriginX)
            let verticalDelta = documentView.isFlipped ? pointDeltaY : -pointDeltaY
            let targetOriginY = min(max(0, visibleRect.origin.y + verticalDelta), maxOriginY)
            let targetOrigin = CGPoint(x: targetOriginX, y: targetOriginY)
            clipView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            return "appkit_scroll_view"
        }

        if let scrollView = firstDescendantScrollView(in: window.contentView ?? rootView),
           let documentView = scrollView.documentView
        {
            let clipView = scrollView.contentView
            let documentBounds = documentView.bounds
            let visibleRect = clipView.documentVisibleRect
            let maxOriginX = max(0, documentBounds.width - visibleRect.width)
            let maxOriginY = max(0, documentBounds.height - visibleRect.height)
            let targetOriginX = min(max(0, visibleRect.origin.x + pointDeltaX), maxOriginX)
            let verticalDelta = documentView.isFlipped ? pointDeltaY : -pointDeltaY
            let targetOriginY = min(max(0, visibleRect.origin.y + verticalDelta), maxOriginY)
            let targetOrigin = CGPoint(x: targetOriginX, y: targetOriginY)
            clipView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            return "appkit_scroll_view_fallback"
        }

        _ = pointInWindow
        throw BridgeAutomationToolError.unsupportedAction("scroll")
    }

    func viewAncestors(startingAt view: NSView) -> [NSView] {
        var ancestors: [NSView] = []
        var current: NSView? = view
        while let unwrappedCurrent = current {
            ancestors.append(unwrappedCurrent)
            current = unwrappedCurrent.superview
        }
        return ancestors
    }

    func firstDescendantScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstDescendantScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    func dispatchAppKitTextInput(_ text: String, in window: NSWindow) throws -> String {
        guard !text.isEmpty else {
            return "appkit_noop"
        }

        if let responder = focusedTextResponder(in: window) {
            if responder.tryToPerform(#selector(NSResponder.insertText(_:)), with: text) {
                return "appkit_insert_text"
            }

            if let textView = responder as? NSTextView {
                textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                return "appkit_text_view_insert"
            }

            if let control = responder as? NSControl,
               let currentValue = control.stringValueIfAvailable
            {
                control.stringValue = currentValue + text
                _ = control.sendAction(control.action, to: control.target)
                return "appkit_control_string_value"
            }
        }

        throw BridgeAutomationToolError.noFocusedInput(window.title.isEmpty ? "window" : window.title)
    }

    func dispatchAppKitKeyPress(
        key: String,
        modifiers: NSEvent.ModifierFlags,
        in window: NSWindow
    ) throws -> String {
        if let route = try dispatchKeyEquivalentIfNeeded(
            for: key,
            modifiers: modifiers,
            in: window
        ) {
            return route
        }

        return try dispatchWindowKeyEvent(
            for: key,
            modifiers: modifiers,
            in: window
        )
    }

    func dispatchKeyEquivalentIfNeeded(
        for key: String,
        modifiers: NSEvent.ModifierFlags,
        in window: NSWindow
    ) throws -> String? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) == false else {
            return nil
        }

        let spec = try keyEventSpec(for: key)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let characters = characters(for: spec, modifiers: modifiers)

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: spec.charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: spec.keyCode
        ) else {
            throw BridgeAutomationToolError.unsupportedAction("press_key")
        }

        if window.performKeyEquivalent(with: event) {
            return "appkit_key_equivalent_window"
        }

        if let contentView = window.contentView,
           contentView.performKeyEquivalent(with: event)
        {
            return "appkit_key_equivalent_view"
        }

        if let mainMenu = NSApp.mainMenu,
           mainMenu.performKeyEquivalent(with: event)
        {
            return "appkit_key_equivalent_menu"
        }

        return nil
    }

    func focusedTextResponder(in window: NSWindow) -> NSResponder? {
        if let firstResponder = window.firstResponder,
           respondsToTextInput(firstResponder)
        {
            return firstResponder
        }

        if let editor = window.fieldEditor(false, for: nil),
           respondsToTextInput(editor)
        {
            return editor
        }

        return nil
    }

    func respondsToTextInput(_ responder: NSResponder) -> Bool {
        responder.responds(to: #selector(NSResponder.insertText(_:)))
    }

    func dispatchWindowKeyEvent(
        for key: String,
        modifiers: NSEvent.ModifierFlags,
        in window: NSWindow
    ) throws -> String {
        let spec = try keyEventSpec(for: key)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let characters = characters(for: spec, modifiers: modifiers)

        guard let keyDown = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: spec.charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: spec.keyCode
        ), let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: spec.charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: spec.keyCode
        ) else {
            throw BridgeAutomationToolError.unsupportedAction("press_key")
        }

        window.sendEvent(keyDown)
        window.sendEvent(keyUp)
        return "appkit_key_event"
    }

    func characters(for spec: AppKitKeyEventSpec, modifiers: NSEvent.ModifierFlags) -> String {
        if modifiers.contains(.shift), let shiftedCharacters = spec.shiftedCharacters {
            return shiftedCharacters
        }
        return spec.characters
    }

    func keyEventSpec(for key: String) throws -> AppKitKeyEventSpec {
        if let printableKeyCode = printableKeyCode(for: key) {
            let uppercased = key.uppercased()
            return AppKitKeyEventSpec(
                keyCode: printableKeyCode,
                characters: key,
                charactersIgnoringModifiers: key,
                shiftedCharacters: uppercased == key ? nil : uppercased
            )
        }

        guard let spec = Self.specialKeySpecs[key] else {
            throw BridgeAutomationToolError.unsupportedKey(key)
        }
        return spec
    }

    func printableKeyCode(for key: String) -> UInt16? {
        Self.printableKeyCodes[key]
    }

    func normalizeKeyName(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func modifierFlags(from modifiers: [String]) throws -> NSEvent.ModifierFlags {
        try modifiers.reduce(into: NSEvent.ModifierFlags()) { flags, modifier in
            switch modifier.lowercased() {
            case "command", "cmd":
                flags.insert(.command)
            case "shift":
                flags.insert(.shift)
            case "option", "alt":
                flags.insert(.option)
            case "control", "ctrl":
                flags.insert(.control)
            case "function", "fn":
                flags.insert(.function)
            case "":
                break
            default:
                throw BridgeAutomationToolError.unsupportedModifier(modifier)
            }
        }
    }

    static let printableKeyCodes: [String: UInt16] = [
        "a": UInt16(kVK_ANSI_A),
        "b": UInt16(kVK_ANSI_B),
        "c": UInt16(kVK_ANSI_C),
        "d": UInt16(kVK_ANSI_D),
        "e": UInt16(kVK_ANSI_E),
        "f": UInt16(kVK_ANSI_F),
        "g": UInt16(kVK_ANSI_G),
        "h": UInt16(kVK_ANSI_H),
        "i": UInt16(kVK_ANSI_I),
        "j": UInt16(kVK_ANSI_J),
        "k": UInt16(kVK_ANSI_K),
        "l": UInt16(kVK_ANSI_L),
        "m": UInt16(kVK_ANSI_M),
        "n": UInt16(kVK_ANSI_N),
        "o": UInt16(kVK_ANSI_O),
        "p": UInt16(kVK_ANSI_P),
        "q": UInt16(kVK_ANSI_Q),
        "r": UInt16(kVK_ANSI_R),
        "s": UInt16(kVK_ANSI_S),
        "t": UInt16(kVK_ANSI_T),
        "u": UInt16(kVK_ANSI_U),
        "v": UInt16(kVK_ANSI_V),
        "w": UInt16(kVK_ANSI_W),
        "x": UInt16(kVK_ANSI_X),
        "y": UInt16(kVK_ANSI_Y),
        "z": UInt16(kVK_ANSI_Z),
        "0": UInt16(kVK_ANSI_0),
        "1": UInt16(kVK_ANSI_1),
        "2": UInt16(kVK_ANSI_2),
        "3": UInt16(kVK_ANSI_3),
        "4": UInt16(kVK_ANSI_4),
        "5": UInt16(kVK_ANSI_5),
        "6": UInt16(kVK_ANSI_6),
        "7": UInt16(kVK_ANSI_7),
        "8": UInt16(kVK_ANSI_8),
        "9": UInt16(kVK_ANSI_9),
        "/": UInt16(kVK_ANSI_Slash),
        "slash": UInt16(kVK_ANSI_Slash),
    ]

    static let specialKeySpecs: [String: AppKitKeyEventSpec] = [
        "enter": .init(keyCode: UInt16(kVK_Return), characters: "\r", charactersIgnoringModifiers: "\r"),
        "return": .init(keyCode: UInt16(kVK_Return), characters: "\r", charactersIgnoringModifiers: "\r"),
        "escape": .init(keyCode: UInt16(kVK_Escape), characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}"),
        "esc": .init(keyCode: UInt16(kVK_Escape), characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}"),
        "tab": .init(keyCode: UInt16(kVK_Tab), characters: "\t", charactersIgnoringModifiers: "\t"),
        "backtab": .init(keyCode: UInt16(kVK_Tab), characters: "\u{19}", charactersIgnoringModifiers: "\t"),
        "space": .init(keyCode: UInt16(kVK_Space), characters: " ", charactersIgnoringModifiers: " "),
        "delete": .init(keyCode: UInt16(kVK_Delete), characters: "\u{8}", charactersIgnoringModifiers: "\u{8}"),
        "backspace": .init(keyCode: UInt16(kVK_Delete), characters: "\u{8}", charactersIgnoringModifiers: "\u{8}"),
        "forward_delete": .init(
            keyCode: UInt16(kVK_ForwardDelete),
            characters: String(UnicodeScalar(NSDeleteFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSDeleteFunctionKey)!)
        ),
        "up": .init(
            keyCode: UInt16(kVK_UpArrow),
            characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        ),
        "arrow_up": .init(
            keyCode: UInt16(kVK_UpArrow),
            characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        ),
        "down": .init(
            keyCode: UInt16(kVK_DownArrow),
            characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        ),
        "arrow_down": .init(
            keyCode: UInt16(kVK_DownArrow),
            characters: String(UnicodeScalar(NSDownArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        ),
        "left": .init(
            keyCode: UInt16(kVK_LeftArrow),
            characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        ),
        "arrow_left": .init(
            keyCode: UInt16(kVK_LeftArrow),
            characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        ),
        "right": .init(
            keyCode: UInt16(kVK_RightArrow),
            characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        ),
        "arrow_right": .init(
            keyCode: UInt16(kVK_RightArrow),
            characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        ),
        "home": .init(
            keyCode: UInt16(kVK_Home),
            characters: String(UnicodeScalar(NSHomeFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSHomeFunctionKey)!)
        ),
        "end": .init(
            keyCode: UInt16(kVK_End),
            characters: String(UnicodeScalar(NSEndFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSEndFunctionKey)!)
        ),
    ]
}

private extension NSControl {
    var stringValueIfAvailable: String? {
        if responds(to: #selector(getter: NSControl.stringValue)) {
            return stringValue
        }
        return nil
    }
}

private struct AppKitKeyEventSpec {
    let keyCode: UInt16
    let characters: String
    let charactersIgnoringModifiers: String
    let shiftedCharacters: String?

    init(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        shiftedCharacters: String? = nil
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.shiftedCharacters = shiftedCharacters
    }
}
