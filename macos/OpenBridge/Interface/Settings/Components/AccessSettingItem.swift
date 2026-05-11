import AppKit
import SwiftUI

struct AccessSettingItem<Content: View, Actions: View>: View {
    private let iconName: String?
    let title: LocalizedStringKey
    let statusText: String
    let statusColor: Color
    private let customIcon: (() -> AnyView)?
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    init(
        iconName: String,
        title: LocalizedStringKey,
        statusText: String,
        statusColor: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.iconName = iconName
        customIcon = nil
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
        self.content = content()
        self.actions = actions()
    }

    init(
        icon: @escaping () -> some View,
        title: LocalizedStringKey,
        statusText: String,
        statusColor: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        iconName = nil
        customIcon = { AnyView(icon()) }
        self.title = title
        self.statusText = statusText
        self.statusColor = statusColor
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    icon

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).fontWeight(.semibold)

                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        actions
                    }
                }
                content
            }
        }
    }

    private var icon: some View {
        AnyView(
            iconBody
        )
    }

    private var iconBody: AnyView {
        if let customIcon {
            AnyView(customIcon())
        } else if let iconName {
            AnyView(
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(NSColor.quaternaryLabelColor))
                    .containerShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
        } else {
            AnyView(EmptyView())
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Form {
            AccessSettingItem(
                iconName: "record.circle",
                title: "Screen Recording",
                statusText: "Enabled",
                statusColor: .green
            ) {
                EmptyView()
            } actions: {
                Button("Refresh") {}
                    .buttonStyle(.bordered)
            }

            AccessSettingItem(
                iconName: "folder",
                title: "Files and Folders",
                statusText: "Disabled",
                statusColor: .orange
            ) {
                Text("Manage access to Desktop, Documents, Downloads and other folders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } actions: {
                Button("Refresh") {}
                    .buttonStyle(.pillOutlined)
                Button("Enable") {}
                    .buttonStyle(.bordered)
            }
        }.formStyle(.grouped)
    }
    .padding()
    .frame(width: 680)
}
