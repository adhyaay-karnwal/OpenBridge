import SwiftUI

// swiftformat:disable opaqueGenericParameters
public extension View {
    func windowNotifications(
        configuration: WindowNotificationStackConfiguration = .sonner
    ) -> some View {
        modifier(WindowNotificationContainerModifier(configuration: configuration))
    }

    func windowNotificationOverlay<Item: Identifiable, Card: View>(
        items: [Item],
        configuration: WindowNotificationStackConfiguration = .sonner,
        onDismiss: ((Item.ID) -> Void)? = nil,
        @ViewBuilder card: @escaping (Item, WindowNotificationCardContext) -> Card
    ) -> some View where Item.ID: Hashable {
        overlay(alignment: .top) {
            if !items.isEmpty {
                WindowNotificationOverlayHost(
                    items: items,
                    configuration: configuration,
                    onDismiss: onDismiss,
                    card: card
                )
                .transition(
                    .offset(y: -24)
                        .combined(with: .scale(scale: 0.94, anchor: .top))
                        .combined(with: .opacity)
                )
            }
        }
        .animation(configuration.animation, value: items.isEmpty)
    }

    func windowNotificationHost(
        center: WindowNotificationCenter,
        configuration: WindowNotificationStackConfiguration = .sonner
    ) -> some View {
        windowNotificationOverlay(items: center.items, configuration: configuration, onDismiss: center.dismiss) { item, context in
            item.render(context)
        }
        .windowNotificationCenter(center)
    }
}

// swiftformat:enable opaqueGenericParameters

private struct WindowNotificationContainerModifier: ViewModifier {
    let configuration: WindowNotificationStackConfiguration

    @State private var center = WindowNotificationCenter()

    func body(content: Content) -> some View {
        content
            .environment(center)
            .windowNotificationHost(center: center, configuration: configuration)
    }
}

private struct WindowNotificationOverlayHost<Item: Identifiable, Card: View>: View where Item.ID: Hashable {
    let items: [Item]
    let configuration: WindowNotificationStackConfiguration
    let onDismiss: ((Item.ID) -> Void)?
    let card: (Item, WindowNotificationCardContext) -> Card

    var body: some View {
        GeometryReader { proxy in
            let effectiveConfiguration = clampedConfiguration(for: proxy.size)
            WindowNotificationStack(
                items: items,
                configuration: effectiveConfiguration,
                onDismiss: onDismiss,
                maximumExpandedHeight: maximumExpandedHeight(
                    for: proxy.size.height,
                    configuration: effectiveConfiguration
                ),
                card: card
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, effectiveConfiguration.overlayInsets.top)
            .padding(.bottom, effectiveConfiguration.overlayInsets.bottom)
            .padding(
                .horizontal,
                max(effectiveConfiguration.overlayInsets.leading, effectiveConfiguration.overlayInsets.trailing)
            )
            .offset(x: effectiveConfiguration.offset.width, y: effectiveConfiguration.offset.height)
        }
    }

    private func clampedConfiguration(for containerSize: CGSize) -> WindowNotificationStackConfiguration {
        let horizontalInset = max(configuration.overlayInsets.leading, configuration.overlayInsets.trailing)
        let availableWidth = max(containerSize.width - (horizontalInset * 2), 1)

        var effectiveConfiguration = configuration
        effectiveConfiguration.maximumWidth = min(configuration.maximumWidth, availableWidth)
        return effectiveConfiguration
    }

    private func maximumExpandedHeight(
        for containerHeight: CGFloat,
        configuration: WindowNotificationStackConfiguration
    ) -> CGFloat? {
        guard configuration.allowsExpandedScrolling else {
            return nil
        }

        let availableHeight = containerHeight
            - configuration.overlayInsets.top
            - configuration.overlayInsets.bottom
            - max(configuration.offset.height, 0)

        return max(availableHeight, 1)
    }
}
