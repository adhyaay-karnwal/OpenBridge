import Foundation

extension NotificationCenter {
    static func publisher(
        for name: Notification.Name,
        object: AnyObject? = nil
    ) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name, object: object)
    }
}
