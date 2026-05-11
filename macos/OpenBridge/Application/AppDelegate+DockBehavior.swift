//
//  AppDelegate+DockBehavior.swift
//  OpenBridge
//
//  Created by qaq on 15/1/2026.
//

import AppKit

/**
 这里列出的 Window.Kind 是 Dock 栏关心的窗口
 当这里的 Window 出现的时候 Dock 栏无论如何都会显示软件图标 点击就会激活
 */
private let dockControllableWindow: [Windows.Kind] = [
    .chat, .settings,
]

extension AppDelegate {
    func startDockIconControlTimer() {
        dockIconControlTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.isolated { self?.updateDockIconActivationPolicy() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dockIconControlTimer = timer
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        let visibleKind = dockControllableWindow.first {
            Windows.shared.windowInstance(for: $0).isVisible
        }
        if let visibleKind {
            Windows.shared.open(visibleKind)
        } else if !SkillImportWindowController.shared.isVisible {
            // Don't open chat window if skill import dialog is visible
            Windows.shared.open(.chat)
        }
        return false
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let title = String(localized: "Settings…")
        let item = NSMenuItem(title: title, action: #selector(openSettingsFromDockMenu), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func updateDockIconActivationPolicy() {
        var shouldShowDockIcon = SettingsManager.shared.showDockIcon
        // 如果主窗口在则显示 否则很尴尬
        var visibleWindows: [Windows.Kind] = dockControllableWindow
        while !shouldShowDockIcon, !visibleWindows.isEmpty {
            let kind = visibleWindows.removeFirst()
            if Windows.shared.windowInstance(for: kind).isVisible {
                shouldShowDockIcon = true
            }
        }
        let currentPolicy = NSApp.activationPolicy()
        let targetPolicy: NSApplication.ActivationPolicy = shouldShowDockIcon ? .regular : .accessory
        guard currentPolicy != targetPolicy else { return }
        NSApp.setActivationPolicy(targetPolicy)
    }

    @objc private func openSettingsFromDockMenu() {
        Windows.shared.open(.settings)
    }
}
