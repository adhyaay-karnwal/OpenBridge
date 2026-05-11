//
//  LogViewerViewModel.swift
//  OpenBridge
//

import AppKit
import Foundation
import OSLog

@MainActor
@Observable
final class LogViewerViewModel {
    private(set) var allEntries: [LogEntry] = []
    private(set) var isLoading = false

    var searchText = ""
    var selectedLevel: LogLevel?
    var selectedCategory: String?

    var filteredEntries: [LogEntry] {
        allEntries.filter { entry in
            if let level = selectedLevel, entry.level != level {
                return false
            }
            if let category = selectedCategory, entry.category != category {
                return false
            }
            if !searchText.isEmpty {
                return entry.rawLine.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    func loadLogs() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            let text = await LogStore.shared.readAll()
            self.allEntries = LogEntry.parseAll(from: text)
            self.isLoading = false
        }
    }

    func clearLogs() {
        Task {
            await LogStore.shared.clear()
            allEntries = []
        }
    }

    func exportText() -> String {
        filteredEntries.map(\.rawLine).joined(separator: "\n")
    }

    func copyToClipboard() {
        let text = exportText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
