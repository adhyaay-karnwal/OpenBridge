import SwiftUI

struct TintedToggle<Label: View>: View {
    @Environment(SettingsManager.self) private var settings

    private let isOn: Binding<Bool>
    private let label: () -> Label

    init(isOn: Binding<Bool>, @ViewBuilder label: @escaping () -> Label) {
        self.isOn = isOn
        self.label = label
    }

    init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) where Label == Text {
        self.init(isOn: isOn) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    init(_ titleKey: String, isOn: Binding<Bool>) where Label == Text {
        self.init(isOn: isOn) {
            Text(titleKey)
        }
    }

    var body: some View {
        Toggle(isOn: isOn, label: label)
            .toggleStyle(.switch)
            .tint(settings.accentColor)
    }
}
