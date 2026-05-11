//
//  SoundTypePicker.swift
//  OpenBridge
//

import AppKit
import SwiftUI

/// A native popup button for selecting sound types with hover sound preview.
struct SoundTypePicker: NSViewRepresentable {
    @Binding var selection: SoundType

    private let hoverDelay: Duration = .milliseconds(300)

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)

        for soundType in SoundType.allCases {
            let item = NSMenuItem(title: soundType.displayName, action: nil, keyEquivalent: "")
            item.representedObject = soundType
            popup.menu?.addItem(item)
        }

        popup.menu?.delegate = context.coordinator
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))

        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)

        updateSelection(popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context _: Context) {
        updateSelection(popup)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateSelection(_ popup: NSPopUpButton) {
        guard let index = SoundType.allCases.firstIndex(of: selection) else { return }
        popup.selectItem(at: index)
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: SoundTypePicker
        private var hoverTask: Task<Void, Never>?

        init(_ parent: SoundTypePicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let soundType = sender.selectedItem?.representedObject as? SoundType else { return }
            parent.selection = soundType
            SoundsService.play(soundType)
        }

        func menu(_: NSMenu, willHighlight item: NSMenuItem?) {
            hoverTask?.cancel()
            guard let soundType = item?.representedObject as? SoundType else { return }
            hoverTask = Task {
                try? await Task.sleep(for: parent.hoverDelay)
                guard !Task.isCancelled else { return }
                SoundsService.play(soundType)
            }
        }

        func menuDidClose(_: NSMenu) {
            hoverTask?.cancel()
            hoverTask = nil
        }
    }
}
