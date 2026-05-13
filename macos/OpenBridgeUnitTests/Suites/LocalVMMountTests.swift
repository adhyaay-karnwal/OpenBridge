@testable import OpenBridge
import Testing

struct LocalVMMountTests {
    @Test
    func `default mounts include openbridge data as passthrough`() {
        let mounts = LocalVMMount.defaultMounts(homeDirectory: "/Users/tester")

        #expect(mounts == [
            LocalVMMount(hostPath: "/Users/tester"),
            LocalVMMount(hostPath: "/Applications", readOnly: true),
            LocalVMMount(hostPath: "/Library", readOnly: true),
            LocalVMMount(hostPath: "/Volumes"),
            LocalVMMount(hostPath: "/Users/tester/.openbridge", readOnly: false, passthrough: true),
        ])
    }

    @Test
    func `sandbox mounts add openbridge data mount for existing settings`() {
        let mounts = LocalVMMount.sandboxMounts(
            from: [LocalVMMount(hostPath: "/Users/tester")],
            homeDirectory: "/Users/tester"
        )

        #expect(mounts.contains(LocalVMMount(hostPath: "/Users/tester/.openbridge", passthrough: true)))
    }

    @Test
    func `sandbox mounts force openbridge data to direct writes`() throws {
        let mounts = LocalVMMount.sandboxMounts(
            from: [
                LocalVMMount(hostPath: "/Users/tester"),
                LocalVMMount(hostPath: "/Users/tester/.openbridge", readOnly: true, passthrough: false),
            ],
            homeDirectory: "/Users/tester"
        )

        let dataMount = try #require(mounts.first { $0.hostPath == "/Users/tester/.openbridge" })
        #expect(dataMount.vmPath == "/Users/tester/.openbridge")
        #expect(dataMount.readOnly == false)
        #expect(dataMount.passthrough == true)
    }
}
