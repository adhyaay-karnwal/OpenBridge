import Foundation

enum WebKitBridgeError: Error, Equatable {
    case readinessTimedOut(TimeInterval)
}
