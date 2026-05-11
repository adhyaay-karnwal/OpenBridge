import SwiftUI

// MARK: - Settings Tab

enum SettingsTab: Hashable {
    case general
    case sounds
    case aiProviders
    case systemSkills
    case mySkills
    case syncedSkills
    case shortcuts
    case access
    case notifications
    case about
}

// MARK: - Settings Navigation

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    private(set) var selectedTab: SettingsTab = .general
    var presentedDestination: SettingsDestination?

    private init() {}

    func navigate(to tab: SettingsTab) {
        selectedTab = tab
    }

    func present(_ destination: SettingsDestination, in tab: SettingsTab? = nil) {
        if let tab {
            selectedTab = tab
        }
        presentedDestination = destination
    }

    func clearPresentedDestination() {
        presentedDestination = nil
    }
}

// MARK: - Navigation Destination

enum SettingsDestination: Hashable {
    #if DEBUG || STAGING
        case notchDebug
    #endif

    // Skills sub-pages
    case skillDetail(Skill)
    case aiProviderDetail(BridgeAIProvider)
    case allSystemSkills
    case allSyncFolderSkills(URL)

    /// Log viewer page accessible from About settings
    case logViewer
}

struct SettingsWindowView: View {
    @State private var navigationPath = NavigationPath()

    private var selectedTab: Binding<SettingsTab> {
        Binding(
            get: { SettingsNavigation.shared.selectedTab },
            set: { SettingsNavigation.shared.navigate(to: $0) }
        )
    }

    init() {}

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTab) {
                // (accessibility IDs are applied to individual tab labels below)
                // MARK: Section 1 - 基础设置 / Basic Settings

                // 这个 section 用于展示基础的设置项目，他一般是本地的，并且是常规的，和一般 App 功能一致的。
                // 也就是说这是所有 app 都可能会有的设置，我们会放到这里
                // This section displays basic settings that are local, standard, and consistent with general app functionality.
                // In other words, these are settings that all apps might have, so we place them here.
                Section {
                    Label("General", systemImage: "gearshape").tag(SettingsTab.general)
                        .labelStyle(SettingItemLabelStyle(color: .blue))
                        .accessibilityIdentifier(AccessibilityID.Settings.generalTab)
                    Label("Sounds", systemImage: "speaker.wave.3.fill").tag(SettingsTab.sounds)
                        .labelStyle(SettingItemLabelStyle(color: .blue, iconSize: 10))
                        .accessibilityIdentifier(AccessibilityID.Settings.soundsTab)
                }

                // MARK: Section 2 - AI 和在线相关 / AI and Online Services

                // 这个 section 用于展示那些和 AI 相关的，或者其他和账户相关的，需要联网的设置项目
                // 如果 AI 相关的配置，你不知道放哪里，可以先放到 AI 的子页面中
                // 后续可能会把 AI 部分拆分出来
                // If you don't know where to place AI-related configurations, you can put them in AI sub-pages first.
                // This section displays AI-related settings and other account-related settings that require internet connectivity.
                // The AI section might be split out later.
                Section {
                    Label("AI Providers", systemImage: "key.fill").tag(SettingsTab.aiProviders)
                        .labelStyle(
                            SettingItemLabelStyle(
                                style: AnyShapeStyle(
                                    LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
                                ),
                                iconSize: 11
                            )
                        )
                    if #available(macOS 15.0, *) {
                        Label("My Skills", systemImage: "brain.head.profile.fill").tag(SettingsTab.mySkills)
                            .labelStyle(
                                SettingItemLabelStyle(
                                    style: AnyShapeStyle(
                                        MeshGradient(
                                            width: 3, height: 3,
                                            points: [
                                                .init(0, 0), .init(0.5, 0), .init(1, 0),
                                                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                                                .init(0, 1), .init(0.5, 1), .init(1, 1),
                                            ],
                                            colors: [
                                                .orange, .orange, .red,
                                                .orange, .pink, .pink,
                                                .yellow, .yellow, .pink,
                                            ]
                                        )
                                    ),
                                    iconSize: 10
                                )
                            )
                            .accessibilityIdentifier(AccessibilityID.Settings.mySkillsTab)
                        Label("System Skills", systemImage: "desktopcomputer").tag(SettingsTab.systemSkills)
                            .labelStyle(
                                SettingItemLabelStyle(
                                    style: AnyShapeStyle(
                                        MeshGradient(
                                            width: 3, height: 3,
                                            points: [
                                                .init(0, 0), .init(0.5, 0), .init(1, 0),
                                                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                                                .init(0, 1), .init(0.5, 1), .init(1, 1),
                                            ],
                                            colors: [
                                                .orange, .orange, .red,
                                                .orange, .pink, .pink,
                                                .yellow, .yellow, .pink,
                                            ]
                                        )
                                    ),
                                    iconSize: 10
                                )
                            )
                            .accessibilityIdentifier(AccessibilityID.Settings.systemSkillsTab)
                        Label("Synced Skills", systemImage: "folder.badge.gearshape").tag(
                            SettingsTab.syncedSkills
                        )
                        .labelStyle(
                            SettingItemLabelStyle(
                                style: AnyShapeStyle(
                                    MeshGradient(
                                        width: 3, height: 3,
                                        points: [
                                            .init(0, 0), .init(0.5, 0), .init(1, 0),
                                            .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                                            .init(0, 1), .init(0.5, 1), .init(1, 1),
                                        ],
                                        colors: [
                                            .orange, .orange, .red,
                                            .orange, .pink, .pink,
                                            .yellow, .yellow, .pink,
                                        ]
                                    )
                                ),
                                iconSize: 10
                            )
                        )
                        .accessibilityIdentifier(AccessibilityID.Settings.syncedSkillsTab)
                    } else {
                        Label("My Skills", systemImage: "brain.head.profile.fill").tag(SettingsTab.mySkills)
                            .labelStyle(
                                SettingItemLabelStyle(
                                    style:
                                    AnyShapeStyle(
                                        LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                                    )
                                )
                            )
                            .accessibilityIdentifier(AccessibilityID.Settings.mySkillsTab)
                        Label("System Skills", systemImage: "desktopcomputer").tag(SettingsTab.systemSkills)
                            .labelStyle(
                                SettingItemLabelStyle(
                                    style:
                                    AnyShapeStyle(
                                        LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                                    )
                                )
                            )
                            .accessibilityIdentifier(AccessibilityID.Settings.systemSkillsTab)
                        Label("Synced Skills", systemImage: "folder.badge.gearshape").tag(
                            SettingsTab.syncedSkills
                        )
                        .labelStyle(
                            SettingItemLabelStyle(
                                style:
                                AnyShapeStyle(
                                    LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom)
                                )
                            )
                        )
                        .accessibilityIdentifier(AccessibilityID.Settings.syncedSkillsTab)
                    }
                }

                // MARK: Section 3 - App 功能相关 / App Features

                // 这是一些和 App 的某个功能相关的配置
                // 一般是比较独立的相关设置，并且他们一般与 AI 无关
                // 主要是一些效率类型的设置
                // These are configurations related to specific app features.
                // Generally, these are independent settings that are typically unrelated to AI.
                // Mainly productivity-related settings.
                Section {
                    Label("Shortcuts", systemImage: "keyboard").tag(SettingsTab.shortcuts)
                        .labelStyle(SettingItemLabelStyle(color: .purple, iconSize: 12))
                        .accessibilityIdentifier(AccessibilityID.Settings.shortcutsTab)
                }

                Section {
                    Label("Access", systemImage: "checkerboard.shield").tag(SettingsTab.access)
                        .labelStyle(SettingItemLabelStyle(color: .green))
                        .accessibilityIdentifier(AccessibilityID.Settings.accessTab)
                }

                // MARK: Section 4 - 其他内容 / Other

                // 这是一些其他内容
                // These are miscellaneous items.
                Section {
                    Label("Notifications", systemImage: "app.badge").tag(SettingsTab.notifications)
                        .labelStyle(SettingItemLabelStyle(color: .orange, iconSize: 12))
                        .accessibilityIdentifier(AccessibilityID.Settings.notificationsTab)
                }

                Section {
                    Label("About", systemImage: "info.circle.fill").tag(SettingsTab.about)
                        .labelStyle(SettingItemLabelStyle(color: .gray))
                        .accessibilityIdentifier(AccessibilityID.Settings.aboutTab)
                }
            }
            .frame(minWidth: 180)
            .accessibilityIdentifier(AccessibilityID.Settings.sidebar)
        } detail: {
            NavigationStack(path: $navigationPath) {
                rootView(for: SettingsNavigation.shared.selectedTab)
                    .navigationDestination(for: SettingsDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 600)
        .accessibilityIdentifier(AccessibilityID.Settings.window)
        .onChange(of: SettingsNavigation.shared.selectedTab) { _, _ in
            navigationPath = NavigationPath()
        }
        .onChange(of: SettingsNavigation.shared.presentedDestination) { _, destination in
            guard let destination else { return }
            DispatchQueue.main.async {
                navigationPath = NavigationPath()
                navigationPath.append(destination)
                SettingsNavigation.shared.clearPresentedDestination()
            }
        }
    }

    @ViewBuilder
    private func rootView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .sounds:
            SoundsSettingsView()
        case .aiProviders:
            AIProvidersSettingsView(navigationPath: $navigationPath)
        case .systemSkills:
            SystemSkillsSettingsView()
        case .mySkills:
            MySkillsSettingsView(navigationPath: $navigationPath)
        case .syncedSkills:
            SyncedSkillsSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .access:
            AccessSettingsView()
        case .notifications:
            NotificationsSettingsView()
        case .about:
            AboutSettingsView(navigationPath: $navigationPath)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case let .skillDetail(skill):
            SkillDetailView(skill: skill)
        case let .aiProviderDetail(provider):
            AIProviderDetailView(provider: provider)
        case .allSystemSkills:
            AllSystemSkillsView()
        case let .allSyncFolderSkills(folder):
            AllSyncFolderSkillsView(folder: folder)
        case .logViewer:
            LogViewerView()
        #if DEBUG || STAGING
            case .notchDebug:
                NotchDebugSettingsView()
        #endif
        }
    }
}

#Preview {
    SettingsWindowView()
        .frame(width: 700, height: 800, alignment: .center)
        .environment(SettingsManager.shared)
}
