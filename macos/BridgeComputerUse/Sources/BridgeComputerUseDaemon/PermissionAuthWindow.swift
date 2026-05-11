import AppKit
import Combine
import CUShared
import PermissionFlow
import SwiftUI

/// Single-window unified authorization UX. Lists every required pane with
/// its current TCC status and a Grant button that hands off to PermissionFlow
/// only when the user clicks. Polls TCC on a timer while visible so the row
/// flips to "Granted" automatically after macOS finishes registering the
/// drop in System Settings.
@MainActor
final class PermissionAuthWindowController {
    private var windowController: NSWindowController?
    private let viewModel = PermissionAuthViewModel()
    private let flow: PermissionFlowController

    /// Snapshot of whatever application was frontmost when the user invoked
    /// `ComputerUse permissions` — typically the terminal they typed into.
    /// Captured before the daemon flips to `.regular` and steals focus so we
    /// can hand focus back on close, matching PermissionFlow's own
    /// `closePanel(returnToPreviousApp:)` behaviour for its floating panel.
    private var previousFrontmostPID: pid_t?
    private var previousFrontmostBundleID: String?

    init() {
        flow = PermissionFlow.makeController(
            configuration: .init(
                requiredAppURLs: [Bundle.main.bundleURL],
                promptForAccessibilityTrust: false
            )
        )
    }

    func show() {
        if let wc = windowController, let window = wc.window {
            viewModel.startPolling()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        rememberPreviousFrontmost()

        let rootView = PermissionAuthView(
            viewModel: viewModel,
            onGrant: { [weak self] pane in self?.grant(pane: pane) },
            onClose: { [weak self] in self?.requestClose() }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "OpenBridge Computer Use — Authorize"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        windowDelegate.controller = self
        window.delegate = windowDelegate

        let wc = NSWindowController(window: window)
        windowController = wc

        // Accessory apps can't become .regular for a floating panel without
        // temporarily stealing focus; we switch back to .accessory when the
        // window closes so the daemon stays headless.
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        viewModel.startPolling()
    }

    /// User-facing close trigger (the in-window Close button). Routes through
    /// AppKit so the window's `windowWillClose` delegate callback ends up
    /// being the single cleanup point for every close path (red traffic
    /// light, Close button, programmatic close) — avoiding re-entrance.
    private func requestClose() {
        windowController?.window?.performClose(nil)
    }

    /// Cleanup performed exactly once after the window has committed to
    /// closing. Called by the delegate's `windowWillClose`.
    fileprivate func didClose() {
        viewModel.stopPolling()
        windowController = nil

        // If PermissionFlow's floating drop panel is still attached to
        // System Settings from a Grant click, tear it down too. We handle
        // the focus restoration ourselves below, so pass false.
        flow.closePanel(returnToPreviousApp: false)

        restorePreviousFrontmost()

        // Defer the policy flip to the next runloop tick so AppKit finishes
        // tearing down the window on the current tick first.
        DispatchQueue.main.async {
            _ = NSApp.setActivationPolicy(.accessory)
        }
    }

    private func rememberPreviousFrontmost() {
        let selfBundleID = Bundle.main.bundleIdentifier
        guard
            let front = NSWorkspace.shared.frontmostApplication,
            front.bundleIdentifier != selfBundleID
        else {
            previousFrontmostPID = nil
            previousFrontmostBundleID = nil
            return
        }
        previousFrontmostPID = front.processIdentifier
        previousFrontmostBundleID = front.bundleIdentifier
    }

    private func restorePreviousFrontmost() {
        defer {
            previousFrontmostPID = nil
            previousFrontmostBundleID = nil
        }
        if
            let pid = previousFrontmostPID,
            let app = NSRunningApplication(processIdentifier: pid)
        {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        guard let bundleID = previousFrontmostBundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private func grant(pane: PermissionPane) {
        flow.authorize(
            pane: Self.translate(pane),
            suggestedAppURLs: [Bundle.main.bundleURL]
        )
    }

    private lazy var windowDelegate = AuthWindowDelegate()

    private static func translate(_ pane: PermissionPane) -> PermissionFlowPane {
        switch pane {
        case .accessibility: .accessibility
        case .screenRecording: .screenRecording
        }
    }
}

private final class AuthWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: PermissionAuthWindowController?

    func windowWillClose(_: Notification) {
        controller?.didClose()
    }
}

@MainActor
final class PermissionAuthViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let pane: PermissionPane
        let granted: Bool
        var id: PermissionPane {
            pane
        }
    }

    @Published var rows: [Row] = PermissionPane.allCases.map {
        Row(pane: $0, granted: PermissionStatusProbe.check($0))
    }

    private var timer: Timer?

    func startPolling() {
        refresh()
        timer?.invalidate()
        // 0.8s is fast enough that the row flips within one visual beat of
        // the System Settings toggle landing, without burning CPU on AX calls.
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let next = PermissionPane.allCases.map {
            Row(pane: $0, granted: PermissionStatusProbe.check($0))
        }
        if next != rows {
            rows = next
        }
    }
}

struct PermissionAuthView: View {
    @ObservedObject var viewModel: PermissionAuthViewModel
    let onGrant: (PermissionPane) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Authorize OpenBridge Computer Use")
                    .font(.title2)
                    .bold()
                Text("OpenBridge Computer Use needs the following permissions to drive your Mac on behalf of automation tools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.rows) { row in
                    PermissionRowView(row: row) {
                        onGrant(row.pane)
                    }
                }
            }

            if viewModel.rows.allSatisfy(\.granted) {
                Label("All required permissions are granted.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("Click Grant to open System Settings; a floating helper will prompt you to drag OpenBridge Computer Use into the list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct PermissionRowView: View {
    let row: PermissionAuthViewModel.Row
    let onGrant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.pane.displayName)
                    .font(.body)
                    .bold()
                Text(row.pane.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if row.granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Grant", action: onGrant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
