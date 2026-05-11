//
//  LogViewerView.swift
//  OpenBridge
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct LogViewerView: View {
    @State private var viewModel = LogViewerViewModel()
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logContent
            Divider()
            bottomToolbar
        }
        .navigationTitle(String(localized: "Log Viewer"))
        .onAppear { viewModel.loadLogs() }
        .confirmationDialog(
            String(localized: "Clear all logs?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear Logs"), role: .destructive) {
                viewModel.clearLogs()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This will permanently delete all log files.")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search logs…"), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Picker(selection: $viewModel.selectedLevel) {
                Text("All Levels").tag(LogLevel?.none)
                Divider()
                Text("Debug").tag(LogLevel?.some(.debug))
                Text("Info").tag(LogLevel?.some(.info))
                Text("Error").tag(LogLevel?.some(.error))
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .fixedSize()

            Picker(selection: $viewModel.selectedCategory) {
                Text("All Categories").tag(String?.none)
                Divider()
                ForEach(LogCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(String?.some(cat.rawValue))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button {
                viewModel.loadLogs()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .padding(10)
    }

    // MARK: - Log Content

    private var logContent: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No log entries")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.filteredEntries) { entry in
                            LogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.filteredEntries.count) of \(viewModel.allEntries.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.copyToClipboard()
            } label: {
                Label(String(localized: "Copy All"), systemImage: "doc.on.doc")
            }
            .disabled(viewModel.filteredEntries.isEmpty)

            Button {
                exportLogs()
            } label: {
                Label(String(localized: "Export…"), systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.filteredEntries.isEmpty)

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(String(localized: "Clear"), systemImage: "trash")
            }
            .disabled(viewModel.allEntries.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(10)
    }

    // MARK: - Export

    private func exportLogs() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "OpenBridge-Logs-\(formatter.string(from: Date())).log"
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? viewModel.exportText().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Log Line View

private struct LogLineView: View {
    let entry: LogEntry

    var body: some View {
        Text(formattedLine)
            .foregroundStyle(colorForLevel)
            .lineLimit(nil)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 1)
    }

    private var formattedLine: String {
        let ts = formatTimestamp(entry.timestamp)
        return "\(ts) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
    }

    private var colorForLevel: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .primary
        case .error: .red
        }
    }

    private func formatTimestamp(_ ts: String) -> String {
        guard let tIndex = ts.firstIndex(of: "T") else { return ts }
        let timePart = ts[ts.index(after: tIndex)...]
        if let plusIndex = timePart.lastIndex(of: "+") {
            return String(timePart[timePart.startIndex ..< plusIndex])
        }
        if let minusIndex = timePart.lastIndex(of: "-") {
            return String(timePart[timePart.startIndex ..< minusIndex])
        }
        return String(timePart)
    }
}
