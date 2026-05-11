import SwiftUI

struct DraftQuoteBadgeView: View {
    let badge: DraftQuoteBadge

    private var displayText: String {
        badge.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: badge.onActivate) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .fontWeight(.medium)
                    Text(displayText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: badge.onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ifLet(badge.dismissAccessibilityID) { view, id in
                view.accessibilityIdentifier(id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .ifLet(badge.badgeAccessibilityID) { view, id in
            view.accessibilityIdentifier(id)
        }
    }
}

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

#Preview("Draft Quote Badge") {
    VStack(spacing: 8) {
        DraftQuoteBadgeView(
            badge: DraftQuoteBadge(
                text: "Refine the onboarding copy so it feels more natural, but keep the concise product positioning from the original draft.",
                onActivate: {},
                onDismiss: {}
            )
        )

        RoundedRectangle(cornerRadius: 12)
            .fill(Color.clear)
            .frame(height: 72)
            .overlay(alignment: .topLeading) {
                Text("Ask anything")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(0)
            }
    }
    .padding(12)
    .frame(width: 460)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.primary.opacity(0.1))
    )
    .padding(24)
    .background(Color(nsColor: .windowBackgroundColor))
}
