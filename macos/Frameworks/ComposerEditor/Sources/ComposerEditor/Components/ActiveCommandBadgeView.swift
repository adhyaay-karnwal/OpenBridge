//
//  ActiveCommandBadgeView.swift
//  ComposerEditor
//

import SwiftUI

/// Displays an active command badge inside the composer, styled like CommandTokenAttachment.
struct ActiveCommandBadgeView: View {
    let badge: ActiveCommandBadge

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon = badge.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(badge.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let subtitle = badge.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                badge.onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.6)
            .ifLet(badge.dismissAccessibilityID) { view, id in
                view.accessibilityIdentifier(id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary)
        .clipShape(Capsule())
        .onHover { isHovering = $0 }
        .ifLet(badge.badgeAccessibilityID) { view, id in
            view.accessibilityIdentifier(id)
        }
    }
}

// MARK: - View Extension

private extension View {
    @ViewBuilder
    func ifLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
