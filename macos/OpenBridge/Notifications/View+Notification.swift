import SwiftUI

extension View {
    func onReceiveNotification(
        name: Notification.Name,
        object: AnyObject? = nil,
        perform action: @escaping (Notification) -> Void
    ) -> some View {
        onReceive(NotificationCenter.publisher(for: name, object: object), perform: action)
    }
}
