import AppKit
import CUForeground

// Standalone visual test harness for the foreground-mode cursor:
//
//   1. Brings up `AgentCursorOverlay` (follower sprite on top of the
//      system cursor), running the same CVDisplayLink + system-cursor
//      hide pipeline the real daemon uses.
//   2. Shows a small calibration window with target regions. Click
//      any region and the demo fires `ForegroundMouseAnimator.animatedMove`
//      at that region's Quartz-space centre, so you can watch the
//      follower sprite ease there.
//
// Usage:
//   .build/debug/CoordDemo

@MainActor
final class DemoController {
    let window: NSWindow
    let overlay: AnyObject

    init() {
        let size = NSSize(width: 640, height: 360)
        let frame = NSRect(origin: NSPoint(x: 300, y: 300), size: size)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CoordDemo — click a target, follower sprite should ease there"
        window.isReleasedWhenClosed = false
        let view = TargetView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        overlay = DemoBridge.makeAgentCursorOverlay()
        DemoBridge.activate(overlay: overlay)
    }
}

final class TargetView: NSView {
    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirty: NSRect) {
        NSColor.black.setFill()
        dirty.fill()

        let corners: [(String, NSRect)] = [
            ("TL", NSRect(x: 8, y: 8, width: 80, height: 50)),
            ("TR", NSRect(x: bounds.width - 88, y: 8, width: 80, height: 50)),
            ("BL", NSRect(x: 8, y: bounds.height - 58, width: 80, height: 50)),
            ("BR", NSRect(x: bounds.width - 88, y: bounds.height - 58, width: 80, height: 50)),
        ]
        for (label, rect) in corners {
            NSColor.systemTeal.setFill()
            rect.fill()
            drawLabel(label, in: rect)
        }

        let center = NSRect(
            x: bounds.midX - 40,
            y: bounds.midY - 25,
            width: 80,
            height: 50
        )
        NSColor.systemPink.setFill()
        center.fill()
        drawLabel("MID", in: center)
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.black,
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let unflipped = NSPoint(x: viewPoint.x, y: bounds.height - viewPoint.y)
        guard let window, let screen = window.screen else { return }
        let windowPoint = convert(unflipped, to: nil)
        let appKit = window.convertPoint(toScreen: windowPoint)
        let quartz = CGPoint(x: appKit.x, y: screen.frame.maxY - appKit.y)
        let start = CGEvent(source: nil)?.location ?? .zero
        FileHandle.standardError.write(
            Data("[CoordDemo] animatedMove from (\(Int(start.x)),\(Int(start.y))) to (\(Int(quartz.x)),\(Int(quartz.y)))\n".utf8)
        )
        let t0 = Date()
        Task { @MainActor in
            do {
                try await DemoBridge.animatedMove(to: quartz)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                FileHandle.standardError.write(Data("[CoordDemo] done in \(ms)ms\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("[CoordDemo] error: \(error)\n".utf8))
            }
        }
    }
}

/// AppKit entry point: set up the app, build the controller, run.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

/// Build the controller inside a main-actor-isolated block. Top-level
/// script code is nominally on the main thread but not automatically
/// @MainActor-isolated, so guard with `assumeIsolated` before touching
/// @MainActor types (DemoController, AgentCursorOverlay, etc.).
let controller = MainActor.assumeIsolated { DemoController() }
app.activate(ignoringOtherApps: true)
app.run()
_ = controller
