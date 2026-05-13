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
        [
            primaryWorkspaceMount(homeDirectory: homeDirectory),
            LocalVMMount(hostPath: "/Applications", readOnly: true),
            LocalVMMount(hostPath: "/Library", readOnly: true),
            LocalVMMount(hostPath: "/Volumes"),
            openBridgeDataMount(homeDirectory: homeDirectory),
        ]
    }

    nonisolated static func primaryWorkspaceMount(homeDirectory: String = NSHomeDirectory()) -> LocalVMMount {
        LocalVMMount(hostPath: homeDirectory)
    }

    nonisolated static func openBridgeDataMount(homeDirectory: String = NSHomeDirectory()) -> LocalVMMount {
        let homePath = normalizedPath(homeDirectory)
        let dataPath = normalizedPath(homePath + "/.openbridge")
        return LocalVMMount(hostPath: dataPath, vmPath: dataPath, readOnly: false, passthrough: true)
    }

    nonisolated static func sandboxMounts(from mounts: [LocalVMMount], homeDirectory: String = NSHomeDirectory()) -> [LocalVMMount] {
        let sourceMounts = mounts.isEmpty ? [LocalVMMount(hostPath: homeDirectory)] : mounts
        let requiredDataMount = openBridgeDataMount(homeDirectory: homeDirectory)
        var includesDataMount = false

        var cleaned = sourceMounts
            .map { mount in
                var normalized = LocalVMMount(
                    hostPath: mount.hostPath,
                    vmPath: mount.vmPath,
                    readOnly: mount.readOnly,
                    passthrough: mount.passthrough
                )
                if normalized.hostPath == requiredDataMount.hostPath, normalized.vmPath == requiredDataMount.vmPath {
                    normalized = requiredDataMount
                    includesDataMount = true
                }
                return normalized
            }
            .filter { !$0.hostPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !includesDataMount {
            cleaned.append(requiredDataMount)
        }

        return cleaned
    }

    nonisolated func isOpenBridgeDataMount(homeDirectory: String = NSHomeDirectory()) -> Bool {
        let dataMount = Self.openBridgeDataMount(homeDirectory: homeDirectory)
        return hostPath == dataMount.hostPath && vmPath == dataMount.vmPath
    }

    nonisolated static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}
