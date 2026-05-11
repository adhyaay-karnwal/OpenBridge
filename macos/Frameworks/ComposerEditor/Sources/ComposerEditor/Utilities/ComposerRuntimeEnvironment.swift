import Foundation

enum ComposerRuntimeEnvironment {
    static let isE2EMode = ProcessInfo.processInfo.arguments.contains("-e2eMode")
}
