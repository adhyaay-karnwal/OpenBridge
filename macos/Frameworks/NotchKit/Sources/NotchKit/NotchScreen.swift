import AppKit

extension NSScreen {
    var notchDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func notchScreen(withDisplayID displayID: UInt32) -> NSScreen? {
        screens.first { $0.notchDisplayID == displayID }
    }

    static var screenUnderPointer: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main
    }

    var notchKitSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        let notchWidth = fullWidth - leftPadding - rightPadding
        return .init(width: ceil(notchWidth), height: ceil(notchHeight))
    }

    var isBuiltInNotchDisplay: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(id.uint32Value) == 1
    }

    static var builtInNotchDisplay: NSScreen? {
        screens.first { $0.isBuiltInNotchDisplay }
    }
}
