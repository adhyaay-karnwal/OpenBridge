import AppKit
import SwiftUI

struct TintedToggle<Label: View>: View {
    private let isOn: Binding<Bool>
    private let tintColor: Color
    private let label: () -> Label

    init(
        isOn: Binding<Bool>,
        tintColor: Color = Color(nsColor: .controlAccentColor),
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isOn = isOn
        self.tintColor = tintColor
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
            .tint(tintColor)
    }
}
