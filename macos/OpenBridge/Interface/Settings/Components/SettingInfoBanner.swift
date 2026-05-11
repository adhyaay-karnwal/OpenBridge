//
//  SettingInfoBanner.swift
//  OpenBridge
//
//  Created by Hwang on 11/9/25.
//

import SwiftUI

struct SettingInfoBanner: View {
    struct BackgroundStyle {
        enum Background {
            case solid(Color)
            case gradient(Color)
            case style(AnyShapeStyle)
            case none

            var shapeStyle: AnyShapeStyle? {
                switch self {
                case let .solid(color):
                    AnyShapeStyle(color)
                case let .gradient(color):
                    AnyShapeStyle(color.gradient)
                case let .style(style):
                    style
                case .none:
                    nil
                }
            }
        }

        var iconBackground: Background
        var iconCornerRadius: CGFloat = 16
    }

    var iconName: String = "gear"
    var title: LocalizedStringKey = "General"
    var info: LocalizedStringKey = "Configure the app’s fundamental features and local agent behavior"

    var backgroundStyle: BackgroundStyle = .init(iconBackground: .gradient(.blue))
    private let customIcon: AnyView?

    init(
        iconName: String = "gear",
        title: LocalizedStringKey = "General",
        info: LocalizedStringKey = "Configure the app’s fundamental features and local agent behavior",
        backgroundStyle: BackgroundStyle = .init(iconBackground: .gradient(.blue))
    ) {
        self.iconName = iconName
        self.title = title
        self.info = info
        self.backgroundStyle = backgroundStyle
        customIcon = nil
    }

    init(
        title: LocalizedStringKey,
        info: LocalizedStringKey,
        backgroundStyle: BackgroundStyle = .init(iconBackground: .gradient(.blue)),
        @ViewBuilder icon: () -> some View
    ) {
        iconName = ""
        self.title = title
        self.info = info
        self.backgroundStyle = backgroundStyle
        customIcon = AnyView(icon())
    }

    var body: some View {
        VStack(spacing: 8) {
            if let customIcon {
                customIcon
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58, alignment: .center)
                    .background {
                        if let bg = backgroundStyle.iconBackground.shapeStyle {
                            RoundedRectangle(cornerRadius: backgroundStyle.iconCornerRadius, style: .continuous)
                                .fill(bg)
                        }
                    }
            }

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(info)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Gradient 样式
        SettingInfoBanner(backgroundStyle: .init(iconBackground: .gradient(.blue)))

        // Solid 样式
        SettingInfoBanner(backgroundStyle: .init(iconBackground: .solid(.blue)))

        // 自定义 Style - 线性渐变
        SettingInfoBanner(
            iconName: "sparkles",
            title: "AI",
            info: "Configure AI settings with custom gradient",
            backgroundStyle: .init(
                iconBackground: .style(
                    AnyShapeStyle(
                        LinearGradient(
                            colors: [.blue, .cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
            )
        )

        // 自定义 Style - MeshGradient (macOS 15.0+)
        if #available(macOS 15.0, *) {
            SettingInfoBanner(
                iconName: "sparkles",
                title: "AI Advanced",
                info: "Configure AI with MeshGradient style",
                backgroundStyle: .init(
                    iconBackground: .style(
                        AnyShapeStyle(
                            MeshGradient(width: 3, height: 3, points: [
                                .init(0, 0), .init(0.5, 0), .init(1, 0),
                                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                                .init(0, 1), .init(0.5, 1), .init(1, 1),
                            ], colors: [
                                .red, .purple, .indigo,
                                .orange, .cyan, .blue,
                                .yellow, .green, .mint,
                            ])
                        )
                    )
                )
            )
        }

        // None 样式
        SettingInfoBanner(backgroundStyle: .init(iconBackground: .none))
    }
    .padding()
}
