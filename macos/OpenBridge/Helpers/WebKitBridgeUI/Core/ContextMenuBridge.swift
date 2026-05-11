import AppKit
import JSBridge
import WebKit

@MainActor
protocol WebViewAwareJSBridge: AnyObject {
    func attachWebView(_ webView: WKWebView)
}

/// Custom WKWebView subclass with context menu suppression.
class BridgeWKWebView: WKWebView {
    override func menu(for _: NSEvent) -> NSMenu? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let fileDropRouter = window as? any ChatWindowFileDropRouting else {
            return super.draggingEntered(sender)
        }

        let operation = fileDropRouter.fileDragEntered(sender.draggingPasteboard)
        return operation == [] ? super.draggingEntered(sender) : operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let fileDropRouter = window as? any ChatWindowFileDropRouting else {
            return super.draggingUpdated(sender)
        }

        let operation = fileDropRouter.fileDragUpdated(sender.draggingPasteboard)
        return operation == [] ? super.draggingUpdated(sender) : operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let fileDropRouter = window as? any ChatWindowFileDropRouting {
            fileDropRouter.fileDragExited()
            return
        }
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileDropRouter = window as? any ChatWindowFileDropRouting else {
            return super.prepareForDragOperation(sender)
        }
        return fileDropRouter.dragOperation(for: sender.draggingPasteboard) != []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileDropRouter = window as? any ChatWindowFileDropRouting else {
            return super.performDragOperation(sender)
        }

        guard fileDropRouter.dragOperation(for: sender.draggingPasteboard) != [] else {
            return super.performDragOperation(sender)
        }
        return fileDropRouter.performFileDrop(sender.draggingPasteboard)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let fileDropRouter = window as? any ChatWindowFileDropRouting {
            fileDropRouter.concludeFileDrop()
            return
        }
        super.concludeDragOperation(sender)
    }
}

@JSBridgeType
struct WebViewContextMenuIcon: Codable {
    let kind: String
    let value: String
}

@JSBridgeType
struct WebViewContextMenuItem: Codable {
    let kind: String
    let id: String?
    let title: String?
    let icon: WebViewContextMenuIcon?
    let enabled: Bool?
    let items: [WebViewContextMenuItem]?
}

@JSBridgeType
struct WebViewContextMenuRequest: Codable {
    let menuId: String
    let x: Double
    let y: Double
    let items: [WebViewContextMenuItem]
    let hasSelection: Bool
    let isEditable: Bool
}

@JSBridgeType
struct WebViewContextMenuActionEvent: Codable {
    let menuId: String
    let itemId: String
}

@JSBridgeType
struct WebViewContextMenuClosedEvent: Codable {
    let menuId: String
}

private final class ContextMenuActionPayload: NSObject {
    let menuId: String
    let itemId: String

    init(menuId: String, itemId: String) {
        self.menuId = menuId
        self.itemId = itemId
    }
}

@MainActor
@JSBridge
final class ContextMenuBridge: NSObject {
    private weak var webView: WKWebView?
    private let logger = Logger.bridge
    private var activeMenu: NSMenu?
    private var activeMenuId: String?

    func popupMenu(_ request: WebViewContextMenuRequest) throws {
        guard let webView else {
            throw RuntimeError("Context menu web view is unavailable")
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = true
        menu.appearance = webView.effectiveAppearance

        activeMenu?.cancelTracking()
        activeMenu = menu
        activeMenuId = request.menuId

        appendSection(buildCustomItems(from: request.items), to: menu)
        appendSection(
            buildSelectionItems(hasSelection: request.hasSelection, isEditable: request.isEditable),
            to: menu,
            separated: true
        )
        appendSection(buildDefaultItems(), to: menu, separated: true)

        guard menu.items.isEmpty == false else {
            activeMenu = nil
            activeMenuId = nil
            return
        }

        webView.window?.makeFirstResponder(webView)
        let popupPoint = resolvePopupPoint(for: request, menu: menu, in: webView)
        menu.popUp(positioning: nil, at: popupPoint, in: nil)
    }

    @EmitEvent
    func menuAction(_ event: WebViewContextMenuActionEvent)

    @EmitEvent
    func menuClosed(_ event: WebViewContextMenuClosedEvent)

    @objc
    private func handleCustomMenuItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextMenuActionPayload else {
            return
        }
        menuAction(.init(menuId: payload.menuId, itemId: payload.itemId))
    }

    @objc
    private func reloadPage(_: NSMenuItem) {
        webView?.reload()
    }

    @objc
    private func openInspector(_: NSMenuItem) {
        guard let webView else { return }
        guard LocalFeatureFlagManager.shared.isEnabled(.webviewDevTool) else { return }

        let inspectorSelector = NSSelectorFromString("_inspector")
        guard webView.responds(to: inspectorSelector),
              let inspector = webView.perform(inspectorSelector)?.takeUnretainedValue() as AnyObject?
        else {
            logger.error("Web inspector is unavailable")
            return
        }

        let showSelector = NSSelectorFromString("show")
        guard inspector.responds(to: showSelector) else {
            logger.error("Web inspector show selector is unavailable")
            return
        }

        _ = inspector.perform(showSelector)
    }
}

extension ContextMenuBridge: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        guard menu === activeMenu, let menuId = activeMenuId else { return }
        activeMenu = nil
        activeMenuId = nil
        menuClosed(.init(menuId: menuId))
    }
}

extension ContextMenuBridge: WebViewAwareJSBridge {
    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
    }
}

private extension ContextMenuBridge {
    func appendSection(_ items: [NSMenuItem], to menu: NSMenu, separated: Bool = false) {
        guard items.isEmpty == false else { return }

        if separated, menu.items.isEmpty == false, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        items.forEach(menu.addItem(_:))
    }

    func buildCustomItems(from items: [WebViewContextMenuItem]) -> [NSMenuItem] {
        var menuItems: [NSMenuItem] = []

        for item in items {
            switch item.kind {
            case "separator":
                guard menuItems.isEmpty == false, menuItems.last?.isSeparatorItem == false else { continue }
                menuItems.append(.separator())
            case "item":
                guard let id = item.id, let title = item.title else { continue }
                let menuItem = NSMenuItem(title: title, action: #selector(handleCustomMenuItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = ContextMenuActionPayload(
                    menuId: activeMenuId ?? "",
                    itemId: id
                )
                menuItem.isEnabled = item.enabled ?? true
                menuItem.image = image(for: item.icon)
                menuItems.append(menuItem)
            case "submenu":
                guard let title = item.title else { continue }
                let childItems = buildCustomItems(from: item.items ?? [])
                guard childItems.isEmpty == false else { continue }

                let submenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                submenuItem.isEnabled = item.enabled ?? true
                submenuItem.image = image(for: item.icon)

                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = true
                submenu.appearance = webView?.effectiveAppearance
                childItems.forEach(submenu.addItem(_:))
                submenuItem.submenu = submenu
                menuItems.append(submenuItem)
            default:
                continue
            }
        }

        while menuItems.last?.isSeparatorItem == true {
            menuItems.removeLast()
        }

        return menuItems
    }

    func buildSelectionItems(hasSelection: Bool, isEditable: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if isEditable {
            if hasSelection {
                items.append(makeFirstResponderItem(
                    title: String(localized: "Cut"),
                    action: #selector(NSText.cut(_:)),
                    keyEquivalent: "x"
                ))
                items.append(makeFirstResponderItem(
                    title: String(localized: "Copy"),
                    action: #selector(NSText.copy(_:)),
                    keyEquivalent: "c"
                ))
            }

            items.append(makeFirstResponderItem(
                title: String(localized: "Paste"),
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            ))
            items.append(makeFirstResponderItem(
                title: String(localized: "Select All"),
                action: #selector(NSStandardKeyBindingResponding.selectAll(_:)),
                keyEquivalent: "a"
            ))

            return items
        }

        if hasSelection {
            items.append(makeFirstResponderItem(
                title: String(localized: "Copy"),
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            ))
        }

        return items
    }

    func buildDefaultItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let reloadItem = NSMenuItem(
            title: String(localized: "Reload"),
            action: #selector(reloadPage(_:)),
            keyEquivalent: "r"
        )
        reloadItem.keyEquivalentModifierMask = [.command]
        reloadItem.target = self
        reloadItem.image = makeSymbolImage(named: "arrow.clockwise")
        items.append(reloadItem)

        let inspectItem = NSMenuItem(
            title: String(localized: "Inspect"),
            action: #selector(openInspector(_:)),
            keyEquivalent: "i"
        )
        inspectItem.keyEquivalentModifierMask = [.command, .option]
        inspectItem.target = self
        inspectItem.isEnabled = LocalFeatureFlagManager.shared.isEnabled(.webviewDevTool)
        inspectItem.image = makeSymbolImage(named: "chevron.left.forwardslash.chevron.right")
        if LocalFeatureFlagManager.shared.isEnabled(.webviewDevTool) {
            items.append(inspectItem)
        }

        return items
    }

    func makeFirstResponderItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }

    func resolvePopupPoint(
        for request: WebViewContextMenuRequest,
        menu: NSMenu,
        in webView: WKWebView
    ) -> CGPoint {
        let defaultPoint = CGPoint(x: request.x, y: request.y)

        guard let window = webView.window else {
            return defaultPoint
        }

        let viewPoint = CGPoint(x: request.x, y: request.y)
        let windowPoint = webView.convert(viewPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        let menuSize = menu.size
        let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.screen?.frame ?? .zero
        let inset: CGFloat = 8

        var adjustedPoint = screenPoint
        adjustedPoint.x = min(
            max(adjustedPoint.x, visibleFrame.minX + inset),
            max(visibleFrame.minX + inset, visibleFrame.maxX - menuSize.width - inset)
        )
        adjustedPoint.y = min(
            max(adjustedPoint.y, visibleFrame.minY + menuSize.height + inset),
            visibleFrame.maxY - inset
        )

        return adjustedPoint
    }

    func image(for icon: WebViewContextMenuIcon?) -> NSImage? {
        guard let icon else { return nil }

        switch icon.kind {
        case "symbol":
            return makeSymbolImage(named: icon.value)
        case "dataUrl":
            guard let data = data(fromDataURL: icon.value) else { return nil }
            let image = NSImage(data: data)
            image?.size = NSSize(width: 16, height: 16)
            return image
        default:
            return nil
        }
    }

    func makeSymbolImage(named name: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    func data(fromDataURL dataURL: String) -> Data? {
        guard let separatorIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let metadata = dataURL[..<separatorIndex]
        let payload = dataURL[dataURL.index(after: separatorIndex)...]

        if metadata.contains(";base64") {
            return Data(base64Encoded: String(payload))
        }

        return String(payload).data(using: .utf8)
    }
}
