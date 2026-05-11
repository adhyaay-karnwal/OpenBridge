import Foundation

struct LocalVMMount: Codable, Equatable, Identifiable, Sendable {
    var id: String {
        "\(hostPath)\u{0}\(vmPath)"
    }

    var hostPath: String
    var vmPath: String
    var readOnly: Bool
    var passthrough: Bool

    nonisolated init(hostPath: String, vmPath: String? = nil, readOnly: Bool = false, passthrough: Bool = false) {
        let normalizedHostPath = Self.normalizedPath(hostPath)
        self.hostPath = normalizedHostPath
        self.vmPath = Self.normalizedPath(vmPath?.isEmpty == false ? vmPath ?? normalizedHostPath : normalizedHostPath)
        self.readOnly = readOnly
        self.passthrough = passthrough
    }

    nonisolated static func defaultMounts(homeDirectory: String = NSHomeDirectory()) -> [LocalVMMount] {
        [LocalVMMount(hostPath: homeDirectory)]
    }

    nonisolated static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}
