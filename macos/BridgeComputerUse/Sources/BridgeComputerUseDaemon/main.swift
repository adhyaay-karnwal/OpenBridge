import CUBackground
import CUForeground
import CUShared
import Foundation

MainActor.assumeIsolated {
    DaemonPermissionBridge.shared = PermissionFlowBridge()
    SessionRegistry.shared.registerBackground(
        factory: { BackgroundModeRuntime() },
        help: ComputerUseCLI.agentUsage
    )
    SessionRegistry.shared.registerForeground(
        factory: { ForegroundModeRuntime() },
        help: ForegroundParser.agentUsage
    )
}

DaemonMain.run(
    handler: { SessionRegistry.shared },
    cleanup: {
        // Tear down any active session before the daemon process exits.
        // Synchronous so the signal handler (which runs on the main
        // thread) never waits on a Task that itself needs the main actor.
        SessionRegistry.shared.deactivateIfActive()
        DaemonCursor.shared.tearDown()
    }
)
