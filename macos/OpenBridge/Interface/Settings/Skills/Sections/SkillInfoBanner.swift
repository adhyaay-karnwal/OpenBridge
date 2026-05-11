import AppKit
import SwiftUI

// MARK: - Skills Banner Style

private var skillsBannerStyle: SettingInfoBanner.BackgroundStyle {
    if #available(macOS 15.0, *) {
        .init(
            iconBackground: .style(
                AnyShapeStyle(
                    MeshGradient(width: 3, height: 3, points: [
                        .init(0, 0), .init(0.5, 0), .init(1, 0),
                        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                        .init(0, 1), .init(0.5, 1), .init(1, 1),
                    ], colors: [
                        .orange, .orange, .red,
                        .orange, .pink, .pink,
                        .yellow, .yellow, .pink,
                    ])
                )
            )
        )
    } else {
        .init(
            iconBackground: .style(
                AnyShapeStyle(
                    LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                )
            )
        )
    }
}

// MARK: - System Skills Info Banner

struct SystemSkillsInfoBanner: View {
    var body: some View {
        Section {
            SettingInfoBanner(
                iconName: "desktopcomputer",
                title: "System Skills",
                info: "Built-in capabilities. Ready to use out of the box.",
                backgroundStyle: skillsBannerStyle
            )
        }
    }
}

// MARK: - My Skills Info Banner

struct MySkillsInfoBanner: View {
    var body: some View {
        Section {
            SettingInfoBanner(
                iconName: "brain.head.profile.fill",
                title: "My Skills",
                info: "Your personal skills. Create, import, and customize.",
                backgroundStyle: skillsBannerStyle
            )
        }
    }
}

// MARK: - Synced Skills Info Banner

struct SyncedSkillsInfoBanner: View {
    var body: some View {
        Section {
            SettingInfoBanner(
                iconName: "folder.badge.gearshape",
                title: "Synced Skills",
                info: "Skills synced from folders. Always up to date.",
                backgroundStyle: skillsBannerStyle
            )
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
