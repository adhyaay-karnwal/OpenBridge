import NotchKit
import SwiftUI

struct NotchDebugSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    @State private var store = NotchDebugConfigurationStore.shared
    @State private var selectedTab: NotchDebugTab = .preview
    @State private var previewType: DebugPreviewType = .running
    @State private var previewCount = 3
    @State private var hasCopiedConfiguration = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            tabStrip

            Form {
                tabContent
            }
            .formStyle(.grouped)
        }
        .navigationTitle(String(localized: "Notch Debug"))
        .tint(settingsManager.systemAccentColor)
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotchDebugTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? Color.black : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedTab == tab ? settingsManager.systemAccentColor : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .preview:
            previewTab
        case .geometry:
            geometryTab
        case .spacing:
            spacingTab
        case .shadow:
            shadowTab
        case .motion:
            motionTab
        case .notification:
            notificationTab
        }
    }

    private var previewTab: some View {
        @Bindable var store = store

        return Group {
            Section(String(localized: "Debug Session")) {
                Text(String(localized: "Changes here apply to the live notch immediately. The config stays in memory only and resets after OpenBridge relaunches."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NotchDebugScreenSelectionRow(
                    title: String(localized: "Screen Selection"),
                    description: String(localized: "Choose which display the notch runtime attaches to while tuning. Keeping this editable keeps exported configs in sync with the live setup."),
                    selection: screenSelectionBinding
                )

                HStack(spacing: 12) {
                    Button(hasCopiedConfiguration ? String(localized: "Copied") : String(localized: "Copy Config")) {
                        handleCopyConfiguration()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "Reset Defaults")) {
                        store.reset()
                        NotchCenter.shared.applyDebugConfiguration()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section(String(localized: "Preview Actions")) {
                NotchDebugPreviewTypeRow(
                    title: String(localized: "Preview Style"),
                    description: String(localized: "Choose the state styling used by the active icon, notification bounce, and expanded preview card."),
                    selection: $previewType
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Preview Count"))
                        Spacer()
                        Stepper(value: $previewCount, in: 1 ... 9) {
                            Text("\(previewCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .labelsHidden()
                    }

                    Text(String(localized: "Controls the active badge count and the task count used in the expanded preview copy."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button(String(localized: "Show Active")) {
                            NotchCenter.shared.showDebugPreview(
                                type: previewType.liveInfoType,
                                count: previewCount,
                                expanded: false
                            )
                        }
                        .buttonStyle(.bordered)

                        Button(String(localized: "Show Expanded")) {
                            NotchCenter.shared.showDebugPreview(
                                type: previewType.liveInfoType,
                                count: previewCount,
                                expanded: true
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button(String(localized: "Trigger Notification")) {
                            NotchCenter.shared.triggerDebugNotification(
                                type: previewType.liveInfoType,
                                count: previewCount
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button(String(localized: "Restore Live Scene")) {
                            NotchCenter.shared.clearDebugPreview()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(String(localized: "These actions inject a temporary debug scene so you can tune active, expanded, and notifying visuals without waiting for real tasks."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Mock Panels")) {
                HStack(spacing: 12) {
                    Button(String(localized: "Add Task")) {
                        NotchCenter.shared.addDebugMockTask()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "Add Notify")) {
                        NotchCenter.shared.addDebugMockNotification()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Validation Cases"))
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        Button(String(localized: "Single Long Permission")) {
                            NotchCenter.shared.showDebugMock(.permissionSingleLong)
                        }
                        .buttonStyle(.bordered)

                        Button(String(localized: "Stacked Long Permissions")) {
                            NotchCenter.shared.showDebugMock(.permissionStackedLong)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button(String(localized: "Mixed Attention")) {
                            NotchCenter.shared.showDebugMock(.mixedAttention)
                        }
                        .buttonStyle(.bordered)

                        Button(String(localized: "Baseline Permissions")) {
                            NotchCenter.shared.showDebugMock(.permissions)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button(String(localized: "Computer Use Permissions")) {
                            NotchCenter.shared.showDebugMock(.computerUsePermissions)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 2)

                Button(String(localized: "Exit Mock Mode")) {
                    NotchCenter.shared.exitDebugMockMode()
                }
                .buttonStyle(.bordered)

                Text(String(localized: "Add Task uses the real notch runtime with randomly generated todos, timed step updates, and a final permission request so you can verify the actual UI and transition chain."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "The validation cases open deterministic mock expanded panels with baseline, computer-use, and long permission states so you can verify stacked icon alignment, chip treatments, card heights, and mixed attention layouts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var geometryTab: some View {
        @Bindable var store = store

        return Section(String(localized: "Geometry")) {
            NotchDebugSliderRow(
                title: String(localized: "Fallback Notch Width"),
                description: String(localized: "Default notch width to reserve on displays without physical hardware. This affects collapsed width and the gap in the expanded header."),
                value: applied($store.fallbackNotchWidth),
                range: 80 ... 260,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Fallback Notch Height"),
                description: String(localized: "Default notch height used when the selected display has no physical notch. This affects collapsed height and expanded header height."),
                value: applied($store.fallbackNotchHeight),
                range: 20 ... 60,
                step: 1
            )
            NotchDebugToggleRow(
                title: String(localized: "Show Fallback Notch Debug Overlay"),
                description: String(localized: "Highlights the reserved center area in translucent red when the current display is using the fallback notch size."),
                isOn: applied($store.showsFallbackNotchDebugOverlay)
            )
            NotchDebugSliderRow(
                title: String(localized: "Compact Side Width"),
                description: String(localized: "Width budget for each compact side slot. Slot content is clamped to this space so it does not collide with the physical notch."),
                value: applied($store.compactSideWidth),
                range: 20 ... 120,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Expanded Width"),
                description: String(localized: "Total width of the expanded outer container. This directly affects horizontal size and header composition."),
                value: applied($store.expandedSurfaceWidth),
                range: 320 ... 960,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Expanded Height"),
                description: String(localized: "Total height of the expanded outer container. This affects content height and the collapse transition."),
                value: applied($store.expandedSurfaceHeight),
                range: 100 ... 420,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Background Spacing"),
                description: String(localized: "Controls the spacing used where the shell shoulders transition into the main body."),
                value: applied($store.backgroundSpacing),
                range: 0 ... 32,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Top Corner Radius Ratio"),
                description: String(localized: "Ratio between the top shoulder corner radius and the bottom shell radius. The default 0.5 makes the top corners half as large."),
                value: applied($store.topCornerRadiusRatio),
                range: 0.1 ... 1.5,
                step: 0.01
            )
            NotchDebugSliderRow(
                title: String(localized: "Compact Corner Radius"),
                description: String(localized: "Corner radius used by the active shell."),
                value: applied($store.compactCornerRadius),
                range: 0 ... 32,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Notifying Corner Radius"),
                description: String(localized: "Corner radius used while the notification bounce is active."),
                value: applied($store.notifyingCornerRadius),
                range: 0 ... 32,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Expanded Corner Radius"),
                description: String(localized: "Corner radius used by the expanded shell."),
                value: applied($store.expandedCornerRadius),
                range: 0 ... 64,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Notification Height Boost"),
                description: String(localized: "Extra downward growth applied during the notifying state."),
                value: applied($store.notificationHeightBoost),
                range: 0 ... 16,
                step: 0.5
            )
            NotchDebugSliderRow(
                title: String(localized: "Interaction Outset"),
                description: String(localized: "Extra hit-test expansion used around the compact shell on displays with a real notch."),
                value: applied($store.interactionOutset),
                range: 0 ... 24,
                step: 0.5
            )
        }
    }

    private var spacingTab: some View {
        @Bindable var store = store

        return Group {
            Section(String(localized: "Compact Insets")) {
                NotchDebugSliderRow(
                    title: String(localized: "Top"),
                    description: String(localized: "Distance between compact content and the top edge."),
                    value: applied($store.compactInsetTop),
                    range: 0 ... 24,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Leading"),
                    description: String(localized: "Distance between the leading compact slot and the shell edge."),
                    value: applied($store.compactInsetLeading),
                    range: 0 ... 32,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Bottom"),
                    description: String(localized: "Distance between compact content and the bottom edge."),
                    value: applied($store.compactInsetBottom),
                    range: 0 ... 24,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Trailing"),
                    description: String(localized: "Distance between the trailing compact slot and the shell edge."),
                    value: applied($store.compactInsetTrailing),
                    range: 0 ... 32,
                    step: 0.5
                )
            }

            Section(String(localized: "Expanded Padding")) {
                NotchDebugSliderRow(
                    title: String(localized: "Top"),
                    description: String(localized: "Top padding applied below the expanded header."),
                    value: applied($store.expandedPaddingTop),
                    range: 0 ... 32,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Leading"),
                    description: String(localized: "Leading padding used by the expanded content area."),
                    value: applied($store.expandedPaddingLeading),
                    range: 0 ... 48,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Bottom"),
                    description: String(localized: "Bottom padding that keeps expanded content off the lower edge."),
                    value: applied($store.expandedPaddingBottom),
                    range: 0 ... 48,
                    step: 0.5
                )
                NotchDebugSliderRow(
                    title: String(localized: "Trailing"),
                    description: String(localized: "Trailing padding used by the expanded content area."),
                    value: applied($store.expandedPaddingTrailing),
                    range: 0 ... 48,
                    step: 0.5
                )
            }
        }
    }

    private var shadowTab: some View {
        @Bindable var store = store

        return Section(String(localized: "Shadow and Padding")) {
            NotchDebugSliderRow(
                title: String(localized: "Shadow Padding Width"),
                description: String(localized: "Horizontal padding reserved for the notch shadow so it does not get clipped."),
                value: applied($store.shadowPaddingWidth),
                range: 0 ... 160,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Shadow Padding Height"),
                description: String(localized: "Vertical padding reserved for the notch shadow so the lower edge does not get clipped."),
                value: applied($store.shadowPaddingHeight),
                range: 0 ... 140,
                step: 1
            )
            NotchDebugSliderRow(
                title: String(localized: "Expanded Entrance Blur"),
                description: String(localized: "Maximum blur radius used while expanded content enters and exits."),
                value: applied($store.expandedEntranceBlurRadius),
                range: 0 ... 140,
                step: 1
            )
        }
    }

    private var motionTab: some View {
        @Bindable var store = store

        return Group {
            Section(String(localized: "Main Animation")) {
                NotchDebugSliderRow(
                    title: String(localized: "Main Animation Duration"),
                    description: String(localized: "Primary shell animation duration for active, expanded, and collapsed state changes."),
                    value: applied($store.mainAnimationDuration),
                    range: 0.1 ... 1.2,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Main Animation Bounce"),
                    description: String(localized: "Extra bounce applied to the primary shell animation."),
                    value: applied($store.mainAnimationExtraBounce),
                    range: 0 ... 0.6,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Expanded Exit Duration"),
                    description: String(localized: "Duration of the expanded-content exit animation."),
                    value: applied($store.expandedExitAnimationDuration),
                    range: 0.05 ... 0.8,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Collapse Duration"),
                    description: String(localized: "Duration used when the outer shell collapses back to compact or hidden."),
                    value: applied($store.collapseAnimationDuration),
                    range: 0.1 ... 1.2,
                    step: 0.01
                )
            }

            Section(String(localized: "Hover")) {
                NotchDebugSliderRow(
                    title: String(localized: "Hover Outset"),
                    description: String(localized: "Extra left, right, and downward growth applied while hovering the compact shell."),
                    value: applied($store.compactHoverOutset),
                    range: 0 ... 12,
                    step: 0.25
                )
                NotchDebugSliderRow(
                    title: String(localized: "Hover Spring Response"),
                    description: String(localized: "Response speed of the hover spring animation."),
                    value: applied($store.compactHoverSpringResponse),
                    range: 0.05 ... 1.0,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Hover Spring Damping"),
                    description: String(localized: "Damping used by the hover spring animation."),
                    value: applied($store.compactHoverSpringDampingFraction),
                    range: 0.1 ... 1.2,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Hover Spring Blend"),
                    description: String(localized: "Blend duration used to smooth hover animation handoffs."),
                    value: applied($store.compactHoverSpringBlendDuration),
                    range: 0 ... 0.4,
                    step: 0.01
                )
            }
        }
    }

    private var notificationTab: some View {
        @Bindable var store = store

        return Group {
            Section(String(localized: "Notification Shape")) {
                NotchDebugSliderRow(
                    title: String(localized: "Notification Scale Width"),
                    description: String(localized: "Horizontal scale applied during the notifying state."),
                    value: applied($store.notificationScaleWidth),
                    range: 1 ... 1.2,
                    step: 0.005
                )
                NotchDebugSliderRow(
                    title: String(localized: "Notification Scale Height"),
                    description: String(localized: "Vertical scale applied during the notifying state."),
                    value: applied($store.notificationScaleHeight),
                    range: 1 ... 1.2,
                    step: 0.005
                )
                NotchDebugSliderRow(
                    title: String(localized: "Notification Hold"),
                    description: String(localized: "How long the enlarged notification state stays visible before returning to active."),
                    value: applied($store.notificationHoldDuration),
                    range: 0.05 ... 0.8,
                    step: 0.01
                )
            }

            Section(String(localized: "Notification Intro Spring")) {
                NotchDebugSliderRow(
                    title: String(localized: "Intro Spring Response"),
                    description: String(localized: "Response speed used while the notification grows."),
                    value: applied($store.notificationIntroSpringResponse),
                    range: 0.05 ... 1.0,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Intro Spring Damping"),
                    description: String(localized: "Damping used while the notification grows."),
                    value: applied($store.notificationIntroSpringDampingFraction),
                    range: 0.1 ... 1.2,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Intro Spring Blend"),
                    description: String(localized: "Blend duration used while the notification grows."),
                    value: applied($store.notificationIntroSpringBlendDuration),
                    range: 0 ... 0.4,
                    step: 0.01
                )
            }

            Section(String(localized: "Notification Reset Spring")) {
                NotchDebugSliderRow(
                    title: String(localized: "Reset Spring Response"),
                    description: String(localized: "Response speed used while the notification settles back to active."),
                    value: applied($store.notificationResetSpringResponse),
                    range: 0.05 ... 1.0,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Reset Spring Damping"),
                    description: String(localized: "Damping used while the notification settles back to active."),
                    value: applied($store.notificationResetSpringDampingFraction),
                    range: 0.1 ... 1.2,
                    step: 0.01
                )
                NotchDebugSliderRow(
                    title: String(localized: "Reset Spring Blend"),
                    description: String(localized: "Blend duration used while the notification settles back to active."),
                    value: applied($store.notificationResetSpringBlendDuration),
                    range: 0 ... 0.4,
                    step: 0.01
                )
            }
        }
    }

    private var screenSelectionBinding: Binding<NotchConfiguration.ScreenSelectionPolicy> {
        @Bindable var store = store
        return applied($store.screenSelectionPolicy)
    }

    private func applied<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                NotchCenter.shared.applyDebugConfiguration()
            }
        )
    }

    private func handleCopyConfiguration() {
        guard store.copyExportToPasteboard() else { return }

        hasCopiedConfiguration = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            hasCopiedConfiguration = false
        }
    }
}

private enum NotchDebugTab: String, CaseIterable, Identifiable {
    case preview
    case geometry
    case spacing
    case shadow
    case motion
    case notification

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .preview:
            String(localized: "Preview")
        case .geometry:
            String(localized: "Geometry")
        case .spacing:
            String(localized: "Spacing")
        case .shadow:
            String(localized: "Shadow")
        case .motion:
            String(localized: "Motion")
        case .notification:
            String(localized: "Notification")
        }
    }
}

private enum DebugPreviewType: String, CaseIterable, Identifiable {
    case running
    case completed
    case others
    case failed

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .running:
            String(localized: "Running")
        case .completed:
            String(localized: "Completed")
        case .others:
            String(localized: "Queued")
        case .failed:
            String(localized: "Failed")
        }
    }

    var liveInfoType: TaskViewModel.LiveInfoType {
        switch self {
        case .running:
            .running
        case .completed:
            .completed
        case .others:
            .others
        case .failed:
            .failed
        }
    }
}

private struct NotchDebugSliderRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}

private struct NotchDebugToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $isOn)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct NotchDebugPreviewTypeRow: View {
    let title: String
    let description: String
    @Binding var selection: DebugPreviewType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                ForEach(DebugPreviewType.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private struct NotchDebugScreenSelectionRow: View {
    let title: String
    let description: String
    @Binding var selection: NotchConfiguration.ScreenSelectionPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                ForEach(NotchConfiguration.ScreenSelectionPolicy.allCases, id: \.self) { option in
                    Text(option.debugTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private extension NotchConfiguration.ScreenSelectionPolicy {
    static var allCases: [Self] {
        [.builtInFirst, .screenUnderPointer, .mainScreen]
    }

    var debugTitle: String {
        switch self {
        case .builtInFirst:
            String(localized: "Built-in")
        case .screenUnderPointer:
            String(localized: "Pointer")
        case .mainScreen:
            String(localized: "Main")
        }
    }
}

#Preview {
    NavigationStack {
        NotchDebugSettingsView()
    }
    .environment(SettingsManager.shared)
}
