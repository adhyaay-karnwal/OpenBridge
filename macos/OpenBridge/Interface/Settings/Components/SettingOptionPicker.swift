//
//  SettingOptionPicker.swift
//  OpenBridge
//
//  Created by Claude Code on 12/12/25.
//

import SwiftUI

/// A reusable picker component that displays options horizontally
/// with visual selection indicators and labels
struct SettingOptionPicker<T: Hashable & Identifiable, Content: View>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let animateSelection: Bool
    let content: (T, Bool) -> Content
    let label: (T, Bool) -> String?

    init(
        title: String,
        options: [T],
        selection: Binding<T>,
        animateSelection: Bool = true,
        @ViewBuilder content: @escaping (T, Bool) -> Content,
        label: @escaping (T, Bool) -> String?
    ) {
        self.title = title
        self.options = options
        _selection = selection
        self.animateSelection = animateSelection
        self.content = content
        self.label = label
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            HStack(alignment: .top, spacing: 4) {
                ForEach(options) { option in
                    let isSelected = selection.id == option.id
                    let labelText = label(option, isSelected)
                    VStack(spacing: 0) {
                        content(option, isSelected)
                        Text("")
                            .font(.caption)
                            .frame(minWidth: 18)
                            .overlay {
                                if let labelText {
                                    Text(labelText)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                    }
                    .onTapGesture {
                        if animateSelection {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = option
                            }
                        } else {
                            selection = option
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedAppearance: Appearance = .system
        @State private var selectedColor: SystemAccentColor = .system

        var body: some View {
            VStack(spacing: 32) {
                SettingOptionPicker(
                    title: "Appearance",
                    options: Appearance.allCases,
                    selection: $selectedAppearance
                ) { appearance, isSelected in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: appearance == .dark ? [.black, .gray] : [.white, .gray],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .frame(width: 100, height: 100)
                } label: { appearance, _ in
                    appearance.displayName
                }

                SettingOptionPicker(
                    title: "Accent Color",
                    options: SystemAccentColor.allCases,
                    selection: $selectedColor
                ) { color, isSelected in
                    Circle()
                        .fill(color.color)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .frame(width: 40, height: 40)
                } label: { color, isSelected in
                    isSelected ? color.displayName : nil
                }
            }
            .padding()
            .frame(width: 600)
        }
    }

    return PreviewWrapper()
        .environment(SettingsManager())
}
