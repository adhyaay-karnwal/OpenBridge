import AppKit
import CoreGraphics
import CUShared
import Foundation

/// Minimal NSWindow with a solid red ring — no Metal, no shader, no
/// CoreGraphics layering. If THIS shows up but `BorderOverlay` doesn't,
/// we know the issue is Metal-pipeline- or coordinate-specific. If even
/// this doesn't show up, the issue is window ordering / z-order at the
/// WindowServer level.
@MainActor
final class SolidRingWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenNone]
        level = .normal

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemRed.cgColor
        view.layer?.borderWidth = 8
        view.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = view
    }

    func pin(to appKitFrame: CGRect, anchor: CGWindowID) {
        let frame = appKitFrame.insetBy(dx: -20, dy: -20)
        setFrame(frame, display: true)
        order(.below, relativeTo: Int(anchor))
        orderFrontRegardless()
    }
}

// Smoke test: attach a BorderOverlay to a chosen window using the same
// CUShared APIs the background daemon uses — but in a standalone process
// with no daemon / socket / session machinery. If this shows a visible
// halo around the target window, the rendering stack works and any
// daemon-side invisibility is a process-context issue (activation policy,
// window level, hide flag, etc.).
//
// usage:
//   swift run --package-path macos/BridgeComputerUse \
//       BorderSmokeTest <cgWindowID-or-name-substring>
//
//   border-smoke 16465       # attach by exact CGWindowID
//   border-smoke Figma       # attach to the frontmost window whose owner
//                             or title contains "Figma" (case-insensitive)

@MainActor
final class SmokeTest {
    private let overlay = BorderOverlay()
    private let solidRing = SolidRingWindow()
    private var solidMode = false

    func run(arg: String, solid: Bool) {
        guard let target = resolveWindow(arg: arg) else {
            fputs("[!] no window matched \(arg)\n", stderr)
            exit(1)
        }
        solidMode = solid
        print("[*] mode=\(solid ? "solid-ring" : "colorful") cgWindow=\(target.id) owner=\(target.owner) title=\(target.title)")
        attach(target: target)

        // Schedule an alpha-forcing tick after the fadeIn window. If
        // `animator().alphaValue = 1` silently failed, this lets us see
        // whether the border is actually invisible due to alpha=0.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                self?.forceFullAlpha()
            }
        }

        // Re-attach every 500ms so the border follows the window if the user
        // drags it around while we're watching. This mimics what
        // BackgroundModeRuntime does between actions.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.attach(target: target)
            }
        }
    }

    private func attach(target: WindowInfo) {
        if solidMode {
            guard let axBounds = lookupBoundsAX(id: target.id) else { return }
            let appKit = axRectToAppKit(axBounds)
            solidRing.pin(to: appKit, anchor: target.id)
        } else {
            overlay.attach(toCGWindow: target.id)
        }
    }

    private func forceFullAlpha() {
        // Introspect NSApp.windows to find our ColorfulBorderWindow and
        // report its isVisible / alphaValue / frame. If alphaValue is 0,
        // force it to 1 so we can distinguish "fadeIn broken" from
        // "rendering broken."
        for window in NSApp.windows {
            guard window !== solidRing else { continue }
            fputs("[*] inspect window class=\(type(of: window)) visible=\(window.isVisible) alpha=\(window.alphaValue) frame=\(window.frame)\n", stderr)
            if window.alphaValue < 1.0 {
                window.alphaValue = 1.0
                fputs("[*] forced alphaValue=1 on \(type(of: window))\n", stderr)
            }
        }
    }

    private func lookupBoundsAX(id: CGWindowID) -> CGRect? {
        guard
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
            let entry = list.first,
            let dict = entry[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: dict)
        else { return nil }
        return rect
    }

    private func axRectToAppKit(_ ax: CGRect) -> CGRect {
        let bridgeHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: ax.minX,
            y: bridgeHeight - ax.maxY,
            width: ax.width,
            height: ax.height
        )
    }

    struct WindowInfo {
        var id: CGWindowID
        var owner: String
        var title: String
    }

    private func resolveWindow(arg: String) -> WindowInfo? {
        if let number = UInt32(arg) {
            return lookupByID(CGWindowID(number))
        }
        return findByName(substring: arg)
    }

    private func lookupByID(_ id: CGWindowID) -> WindowInfo? {
        guard
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
            let entry = list.first
        else { return nil }
        let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
        let title = entry[kCGWindowName as String] as? String ?? ""
        return WindowInfo(id: id, owner: owner, title: title)
    }

    private func findByName(substring: String) -> WindowInfo? {
        let needle = substring.lowercased()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in list {
            let owner = (entry[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let title = (entry[kCGWindowName as String] as? String ?? "").lowercased()
            guard owner.contains(needle) || title.contains(needle) else { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            // Skip menubar / notch / system overlay layers.
            guard layer == 0 else { continue }
            guard let idNumber = entry[kCGWindowNumber as String] as? Int else { continue }
            return WindowInfo(
                id: CGWindowID(idNumber),
                owner: entry[kCGWindowOwnerName as String] as? String ?? "?",
                title: entry[kCGWindowName as String] as? String ?? ""
            )
        }
        return nil
    }
}

let argv = CommandLine.arguments
guard argv.count >= 2 else {
    fputs("usage: BorderSmokeTest [--solid] <cgWindowID-or-name-substring>\n", stderr)
    exit(1)
}

let solid = argv.contains("--solid")
let arg = argv.last!

let app = NSApplication.shared
_ = app.setActivationPolicy(.accessory)

let smoke = MainActor.assumeIsolated { SmokeTest() }
DispatchQueue.main.async {
    MainActor.assumeIsolated { smoke.run(arg: arg, solid: solid) }
}

app.run()
