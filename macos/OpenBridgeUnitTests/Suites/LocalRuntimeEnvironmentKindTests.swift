import KWWKAgent
import KWWKAI
@testable import OpenBridge
import Testing

struct LocalRuntimeEnvironmentKindTests {
    @Test
    func `local macOS environment uses stable local alias`() {
        #expect(LocalRuntimeConnector.EnvironmentKind.localMacOS.connectAlias == "local")
    }

    @Test
    func `local VM environment uses stable sandbox alias`() {
        #expect(LocalRuntimeConnector.EnvironmentKind.localVM.connectAlias == "sandbox")
    }

    @Test
    func `user visible names accept current and legacy sandbox aliases`() {
        let sandboxName = LocalRuntimeConnector.EnvironmentKind.localVM.userVisibleName

        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "sandbox") == sandboxName)
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "sandbox-primary") == sandboxName)
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "local-vm") == sandboxName)
    }

    @Test
    func `user visible names map local aliases to this mac`() {
        let localName = LocalRuntimeConnector.EnvironmentKind.localMacOS.userVisibleName

        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "local") == localName)
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "local-primary") == localName)
    }

    @Test
    func `openbridge coding tools expose environment selector`() {
        let tools = makeOpenBridgeCodingTools(sessionID: "test-session")
        let environmentTools = Set(["request_permission", "read", "write", "edit", "bash", "grep", "find", "ls", "current_changes"])

        #expect(Set(tools.map(\.name)) == environmentTools)
        for tool in tools {
            let properties = tool.parameters.objectValue?["properties"]?.objectValue ?? [:]
            let environment = properties["environment"]?.objectValue ?? [:]
            let expected: Set<KWWKAI.JSONValue> = tool.name == "current_changes" ? [.string("sandbox")] : [.string("sandbox"), .string("local")]
            if case let .array(values) = environment["enum"] {
                #expect(Set(values) == expected)
            } else {
                Issue.record("Missing environment enum for \(tool.name)")
            }
        }
    }
}
