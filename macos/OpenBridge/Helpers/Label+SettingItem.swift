//
//  Label+SettingItem.swift
//  OpenBridge
//
//  Created by Hwang on 11/12/25.
//

import SwiftUI

struct SettingItemLabelStyle: LabelStyle {
    enum Background {
        case color(Color)
        case style(AnyShapeStyle)
    }

    var background: Background?
    /// Outer container size (badge size). Keep this stable for consistent alignment.
    var containerSize: CGFloat
    /// Inner icon content size. This only affects the glyph/image inside the container.
    var iconSize: CGFloat
    var iconCornerRadius: CGFloat
    var iconForegroundStyle: AnyShapeStyle?
    var iconFont: Font?

    /// 便利初始化 - 使用 Color
    init(
        color: Color,
        containerSize: CGFloat = 20,
        iconSize: CGFloat = 14,
        iconCornerRadius: CGFloat = 6,
        iconForegroundStyle: AnyShapeStyle? = AnyShapeStyle(Color.white),
        iconFont: Font? = nil
    ) {
        background = .color(color)
        self.containerSize = containerSize
        self.iconSize = iconSize
        self.iconCornerRadius = iconCornerRadius
        self.iconForegroundStyle = iconForegroundStyle
        self.iconFont = iconFont
    }

    /// 便利初始化 - 使用自定义 ShapeStyle
    init(
        style: AnyShapeStyle,
        containerSize: CGFloat = 20,
        iconSize: CGFloat = 14,
        iconCornerRadius: CGFloat = 6,
        iconForegroundStyle: AnyShapeStyle? = AnyShapeStyle(Color.white),
        iconFont: Font? = nil
    ) {
        background = .style(style)
        self.containerSize = containerSize
        self.iconSize = iconSize
        self.iconCornerRadius = iconCornerRadius
        self.iconForegroundStyle = iconForegroundStyle
        self.iconFont = iconFont
    }

    /// 仅控制 icon 容器大小（不绘制背景，不强制 tint）。
    /// - Note: 适用于 icon 本体是自定义 Image（如 asset）并希望保留原始颜色的场景。
    init(
        iconSize: CGFloat,
        containerSize: CGFloat = 20,
        iconCornerRadius: CGFloat = 6,
        iconForegroundStyle: AnyShapeStyle? = nil,
        iconFont: Font? = nil
    ) {
        background = nil
        self.containerSize = containerSize
        self.iconSize = iconSize
        self.iconCornerRadius = iconCornerRadius
        self.iconForegroundStyle = iconForegroundStyle
        self.iconFont = iconFont
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
                .modifier(SettingItemIconStyleModifier(
                    background: background,
                    containerSize: containerSize,
                    size: iconSize,
                    cornerRadius: iconCornerRadius,
                    foregroundStyle: iconForegroundStyle,
                    font: iconFont
                ))
            configuration.title
        }
    }

    @ViewBuilder
    fileprivate static func backgroundView(for background: Background) -> some View {
        switch background {
        case let .color(color):
            Rectangle().fill(AnyShapeStyle(color.gradient))
        case let .style(style):
            Rectangle().fill(style)
        }
    }
}

private struct SettingItemIconStyleModifier: ViewModifier {
    let background: SettingItemLabelStyle.Background?
    let containerSize: CGFloat
    let size: CGFloat
    let cornerRadius: CGFloat
    let foregroundStyle: AnyShapeStyle?
    let font: Font?

    func body(content: Content) -> some View {
        let resolvedFont = font ?? .system(size: size)
        Group {
            if let background {
                content
                    .font(resolvedFont)
                    .frame(width: size, height: size, alignment: .center)
                    .frame(width: containerSize, height: containerSize, alignment: .center)
                    .background(SettingItemLabelStyle.backgroundView(for: background))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .modifier(OptionalForegroundStyleModifier(foregroundStyle: foregroundStyle))
            } else {
                content
                    .font(resolvedFont)
                    .frame(width: size, height: size, alignment: .center)
                    .frame(width: containerSize, height: containerSize, alignment: .center)
                    .modifier(OptionalForegroundStyleModifier(foregroundStyle: foregroundStyle))
            }
        }
    }
}

private struct OptionalForegroundStyleModifier: ViewModifier {
    let foregroundStyle: AnyShapeStyle?

    func body(content: Content) -> some View {
        Group {
            if let foregroundStyle {
                content.foregroundStyle(foregroundStyle)
            } else {
                content
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        // 简单 Color 示例
        Label("Account", systemImage: "person.fill")
            .labelStyle(SettingItemLabelStyle(color: .blue))

        // 复杂渐变示例 - Apple Intelligence 风格
        Label("Apple Intelligence", systemImage: "sparkles")
            .labelStyle(SettingItemLabelStyle(
                style: AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.6, blue: 1.0),
                            Color(red: 0.6, green: 0.4, blue: 1.0),
                            Color(red: 0.8, green: 0.4, blue: 0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            ))

        // 仅设置 icon 尺寸（不绘制背景 / 不强制 tint），适合自定义 icon 颜色
        Label {
            Text("Skills")
        } icon: {
            Image(systemName: "brain.filled.head.profile")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.pink, .purple)
        }
        .labelStyle(SettingItemLabelStyle(iconSize: 16))
    }
    .padding()
}
