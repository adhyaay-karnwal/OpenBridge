//
//  Extension+NSScreen.swift
//  OpenBridge
//
//  Created by qaq on 5/11/2025.
//

import AppKit

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(withDisplayID displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    static var screenForCurrentInteraction: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main
    }

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        let notchWidth = fullWidth - leftPadding - rightPadding
        return CGSize(width: ceil(notchWidth), height: ceil(notchHeight))
    }

    var headerHeight: CGFloat {
        notchSize.height > 0 ? notchSize.height : 32
    }

    var isBuiltInDisplay: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(id.uint32Value) == 1
    }

    static var buildin: NSScreen? {
        screens.first { $0.isBuiltInDisplay }
    }
}
