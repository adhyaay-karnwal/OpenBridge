import SwiftUI

public extension EnvironmentValues {
    @Entry var windowNotificationCenter: WindowNotificationCenter?
}

public extension View {
    func windowNotificationCenter(_ center: WindowNotificationCenter?) -> some View {
        environment(\.windowNotificationCenter, center)
    }
}
