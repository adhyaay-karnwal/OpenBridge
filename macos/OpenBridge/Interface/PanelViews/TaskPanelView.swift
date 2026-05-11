import AppKit
import SwiftUI

struct TaskPanelView: View {
    @State private var taskViewModel = TaskViewModel.shared

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 8, y: 4)
        )
        .padding(8)
    }

    private var header: some View {
        HStack {
            Text(String(localized: "Background Tasks"))
                .font(.headline)
            Spacer()
            let totalCount = taskViewModel.surfaceItems.count
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button {
                Windows.shared.close(.backgroundTasks)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if taskViewModel.surfaceItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !taskViewModel.surfaceItems.isEmpty {
                        sectionHeader(String(localized: "Task Activity"))
                        ForEach(taskViewModel.surfaceItems) { item in
                            BackgroundTaskRow(
                                item: item,
                                onDismiss: {
                                    taskViewModel.dismissSurfaceItem(item.sessionID)
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No background tasks yet"))
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "Active or completed agent tasks will appear here."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct BackgroundTaskRow: View {
    let item: TaskViewModel.SurfaceItem
    let onDismiss: () -> Void

    private var statusText: String {
        switch item.status {
        case .running:
            String(localized: "Running")
        case .waiting:
            String(localized: "Waiting")
        case .completed:
            String(localized: "Completed")
        case .failed:
            String(localized: "Failed")
        case .cancelled:
            String(localized: "Cancelled")
        }
    }

    private var statusTint: Color {
        switch item.status {
        case .running:
            .blue
        case .waiting:
            .white.opacity(0.85)
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .yellow
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .running:
            "arrow.triangle.2.circlepath"
        case .waiting:
            "pause.circle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        case .cancelled:
            "xmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                    if item.isDismissible {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(String(localized: "Open in Chat")) {
                ContinueInChatManager.shared.openConversation(item.sessionID)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        )
    }
}
