import Foundation
@testable import OpenBridge
import Testing

@MainActor
struct LocalAgentTaskListTests {
    @Test
    func `local agent adapter emits optimistic thinking state for new rounds`() throws {
        let adapter = LocalAgentEventAdapter()

        let thinkingOutput = adapter.beginRound()
        let thinkingState = try #require(thinkingOutput.assistantState)
        #expect(thinkingState.phase == "thinking")
        #expect(thinkingState.sequence == 2)
        #expect(thinkingState.tools.isEmpty)

        let cancelledOutput = adapter.cancelRound()
        let idleState = try #require(cancelledOutput.assistantState)
        #expect(idleState.phase == "idle")
        #expect(idleState.sequence == 3)
    }

    @Test
    func `local agent adapter clears streaming state when paused status arrives`() throws {
        let adapter = LocalAgentEventAdapter()

        _ = adapter.beginRound()

        let delta = try jsonString([
            "content": "Still working",
            "message_id": 1,
        ])
        let deltaOutput = adapter.process(eventType: "delta", data: delta)
        let streamingState = try #require(deltaOutput.assistantState)
        #expect(streamingState.phase == "messaging")
        #expect(streamingState.messaging?.isStreaming == true)
        #expect(streamingState.messaging?.text == "Still working")

        let paused = try jsonString([
            "status": "paused",
        ])
        let pausedOutput = adapter.process(eventType: "status", data: paused)
        let idleState = try #require(pausedOutput.assistantState)
        let finished = try #require(pausedOutput.sessionFinished)
        #expect(idleState.phase == "idle")
        #expect(idleState.messaging == nil)
        #expect(finished.state == "completed")
        #expect(finished.error == nil)
    }

    @Test
    func `local agent adapter preserves optimistic thinking until stored assistant message arrives`() throws {
        let adapter = LocalAgentEventAdapter()

        let thinkingOutput = adapter.beginRound()
        let thinkingState = try #require(thinkingOutput.assistantState)
        #expect(thinkingState.phase == "thinking")

        let paused = try jsonString([
            "status": "paused",
        ])
        let pausedOutput = adapter.process(eventType: "status", data: paused)
        let finished = try #require(pausedOutput.sessionFinished)
        #expect(finished.state == "completed")
        #expect(pausedOutput.assistantState == nil)

        let storedOutput = adapter.process(
            storedMessage: LocalAgentStoredMessage(
                messageId: 42,
                role: "assistant",
                content: "Final answer",
                toolUseId: nil,
                sessionId: nil,
                model: nil,
                inputTokens: nil,
                outputTokens: nil,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
        )
        let reconciledState = try #require(storedOutput.assistantState)
        #expect(reconciledState.phase == "idle")
        #expect(storedOutput.historyMessages.count == 1)
        #expect(storedOutput.historyMessages[0].role == "assistant")
    }

    @Test
    func `local agent adapter settles to idle after a direct assistant message is already visible`() throws {
        let adapter = LocalAgentEventAdapter()

        _ = adapter.beginRound()

        let assistantMessage = adapter.process(
            storedMessage: LocalAgentStoredMessage(
                messageId: 7,
                role: "assistant",
                content: "Ready",
                toolUseId: nil,
                sessionId: nil,
                model: nil,
                inputTokens: nil,
                outputTokens: nil,
                createdAt: Int64(Date().timeIntervalSince1970)
            )
        )
        let visibleState = try #require(assistantMessage.assistantState)
        #expect(visibleState.phase == "thinking")

        let paused = try jsonString([
            "status": "paused",
        ])
        let pausedOutput = adapter.process(eventType: "status", data: paused)
        let idleState = try #require(pausedOutput.assistantState)
        let finished = try #require(pausedOutput.sessionFinished)
        #expect(idleState.phase == "idle")
        #expect(finished.state == "completed")
    }

    @Test
    func `local agent adapter keeps waiting rounds active when no assistant message is visible`() throws {
        let adapter = LocalAgentEventAdapter()

        _ = adapter.beginRound()

        let waiting = try jsonString([
            "status": "waiting",
        ])
        let waitingOutput = adapter.process(eventType: "status", data: waiting)
        let waitingState = try #require(waitingOutput.assistantState)
        #expect(waitingState.phase == "execution")
        #expect(waitingOutput.sessionStarted)
        #expect(waitingOutput.sessionFinished == nil)
    }

    @Test
    func `connector skill inventory description lists active local skills`() {
        let description = LocalRuntimeConnector.localSkillInventoryDescription(
            skills: [
                makeSkill(
                    name: "my-helper",
                    description: "Reusable local workflow for project maintenance.",
                    type: .sync
                ),
            ],
            homeDirectory: "/Users/tester"
        )

        #expect(description.contains("local skills available via this machine"))
        #expect(description.contains("root /Users/tester/.openbridge/skills"))
        #expect(description.contains("my-helper [sync] - Reusable local workflow for project maintenance. @ /Users/tester/.openbridge/skills/sync/my-helper/SKILL.md"))
    }

    @Test
    func `connector skill inventory description omits disabled skills and truncates cleanly`() {
        let visible = makeSkill(
            name: "visible",
            description: String(repeating: "visible workflow ", count: 20),
            type: .sync
        )
        let disabled = makeSkill(
            name: "disabled-skill",
            description: "Should not appear.",
            type: .imported,
            disabled: true
        )
        let truncated = LocalRuntimeConnector.localSkillInventoryDescription(
            skills: [visible, disabled],
            homeDirectory: "/Users/tester",
            maxLength: 520
        )

        #expect(!truncated.contains("disabled-skill"))
        #expect(truncated.contains("visible [sync]"))
        #expect(truncated.contains("more skill(s) not shown") == false)

        let multiSkillTruncated = LocalRuntimeConnector.localSkillInventoryDescription(
            skills: [
                visible,
                makeSkill(
                    name: "zzz-second",
                    description: String(repeating: "second workflow ", count: 20),
                    type: .sync
                ),
            ],
            homeDirectory: "/Users/tester",
            maxLength: 520
        )

        #expect(multiSkillTruncated.contains("visible [sync]"))
        #expect(multiSkillTruncated.contains("... (1 more skill(s) not shown)"))
    }

    @Test
    func `local vm bypasses all path permission prompts`() {
        let connector = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localVM,
            target: .localMacOS
        )

        #expect(connector.requiresPathPermission(elevated: false) == false)
        #expect(connector.requiresPathPermission(elevated: true) == false)
    }

    @Test
    func `local macos still requires permission for elevated path access`() {
        SettingsManager.shared.localEnvironmentPermissionMode = .default

        let connector = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localMacOS,
            target: .localMacOS
        )

        #expect(connector.requiresPathPermission(elevated: false) == false)
        #expect(connector.requiresPathPermission(elevated: true) == true)
    }

    @Test
    func `local macos exec requires explicit permission while local vm does not`() {
        SettingsManager.shared.localEnvironmentPermissionMode = .default

        let localMac = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localMacOS,
            target: .localMacOS
        )
        let localVM = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localVM,
            target: .localMacOS
        )

        #expect(localMac.requiresExecPermission(sessionId: "session-1") == true)
        #expect(localVM.requiresExecPermission(sessionId: "session-1") == false)
    }

    @Test
    func `full access mode bypasses local macos host permission checks`() {
        SettingsManager.shared.localEnvironmentPermissionMode = .fullAccess
        defer { SettingsManager.shared.localEnvironmentPermissionMode = .default }

        let connector = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localMacOS,
            target: .localMacOS
        )

        #expect(connector.requiresPathPermission(elevated: true) == false)
        #expect(connector.requiresExecPermission(sessionId: "session-1") == false)
        #expect(connector.hasGrantedHostAccessPermissionForTesting(sessionId: nil) == true)
    }

    @Test
    func `local macos description no longer advertises elevate or sandboxed exec`() {
        let connector = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localMacOS,
            target: .localMacOS
        )

        let description = connector.localDescription()
        #expect(description.contains("This Mac environment; use environment=\"local\" to target it."))
        #expect(description.contains("Commands and file operations affect the host directly with no connector sandbox."))
        #expect(description.contains("Never operate on both This Mac and the safe local workspace filesystems in the same task; choose one environment for filesystem work."))
        #expect(description.contains("Do not use this by default and do not switch here on your own initiative."))
        #expect(description.contains("First use environment=\"sandbox\" whenever it can accomplish the goal."))
        #expect(description.contains("Only after concluding sandbox cannot do the job should you request or trigger local permission"))
        #expect(description.contains("elevate ") == false)
    }

    @Test
    func `local vm description explains absolute macOS home paths for user-visible folders`() {
        let connector = LocalRuntimeConnector(
            agentGroupId: "test-agent-group",
            environmentKind: .localVM,
            target: .localMacOS
        )

        let description = connector.localDescription()
        let home = NSHomeDirectory()
        #expect(description.contains("Safe Workspace on This Mac"))
        #expect(description.contains("Mounted folders: \(home) (reviewed writes)."))
        #expect(description.contains("Use absolute macOS paths under the mounted folders"))
        #expect(description.contains("Do not assume Desktop, Documents, or Downloads are available unless their parent folder is mounted."))
    }

    @Test
    func `environment aliases map to human readable labels`() {
        #expect(LocalRuntimeConnector.EnvironmentKind.localMacOS.connectName == "This Mac")
        #expect(LocalRuntimeConnector.EnvironmentKind.localVM.connectName == "Safe Workspace on This Mac")
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "local-09a0fdaf15d0") == "This Mac")
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "local-vm-43b43e03b6ac") == "Safe Workspace on This Mac")
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "cloud-vm") == "Safe Workspace on This Mac")
        #expect(LocalRuntimeConnector.EnvironmentKind.userVisibleName(forAlias: "vfs") == "Agent Files")
    }

    @Test
    func `embedded vm runtime namespaces shared vm state by root and build`() {
        let first = EmbeddedVMRuntimeBridge.sharedRuntimePaths(
            homeDirectory: "/Users/tester",
            rootPath: "/Users/tester/worktree-a",
            bundlePath: "/Applications/OpenBridge-A.app"
        )
        let second = EmbeddedVMRuntimeBridge.sharedRuntimePaths(
            homeDirectory: "/Users/tester",
            rootPath: "/Users/tester/worktree-b",
            bundlePath: "/Applications/OpenBridge-A.app"
        )
        let third = EmbeddedVMRuntimeBridge.sharedRuntimePaths(
            homeDirectory: "/Users/tester",
            rootPath: "/Users/tester/worktree-a",
            bundlePath: "/Applications/OpenBridge-B.app"
        )

        #expect(first.metadataDir.hasPrefix("/Users/tester/.openbridge/shared-local-vm-debug/"))
        #expect(first.metadataDir.hasSuffix("/metadata"))
        #expect(first.rootfsOverlayDir.hasPrefix("/Users/tester/.openbridge/shared-local-vm-debug/"))
        #expect(first.rootfsOverlayDir.hasSuffix("/rootfs-overlay"))
        #expect(first.metadataDir != second.metadataDir)
        #expect(first.metadataDir != third.metadataDir)
    }

    @Test
    func `local agent adapter turns manage task tool calls into task history messages`() throws {
        let adapter = LocalAgentEventAdapter()

        let startAssistant = try makeMessageEvent(
            messageId: 1,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-start",
                "function": [
                    "name": "manage_task",
                    "arguments": jsonString([
                        "action": "start",
                        "title": "Wire task list",
                        "todos": [[
                            "content": "Render current todo",
                            "status": "in_progress",
                        ]],
                    ]),
                ],
            ]])
        )
        _ = adapter.process(eventType: "message", data: startAssistant)

        let startTool = try makeMessageEvent(
            messageId: 2,
            role: "tool",
            content: jsonString([
                "task_id": "task-1",
                "message": "Task started: Wire task list",
            ])
        )
        let startOutput = adapter.process(eventType: "message", data: startTool)
        let startedTask = try #require(startOutput.historyMessages.first)
        #expect(startedTask.type == "task")
        #expect(startedTask.action == "start")
        #expect(startedTask.taskId == "task-1")
        #expect(startedTask.taskTitle == "Wire task list")
        #expect(startedTask.todos?.count == 1)

        let updateAssistant = try makeMessageEvent(
            messageId: 3,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-update",
                "function": [
                    "name": "manage_task",
                    "arguments": jsonString([
                        "action": "update",
                        "task_id": "task-1",
                        "todos": [
                            [
                                "content": "Render current todo",
                                "status": "completed",
                            ],
                            [
                                "content": "Show task banner",
                                "status": "in_progress",
                            ],
                        ],
                    ]),
                ],
            ]])
        )
        _ = adapter.process(eventType: "message", data: updateAssistant)

        let updateTool = try makeMessageEvent(
            messageId: 4,
            role: "tool",
            content: jsonString(["message": "updated"])
        )
        let updateOutput = adapter.process(eventType: "message", data: updateTool)
        let updatedTask = try #require(updateOutput.historyMessages.first)
        #expect(updatedTask.type == "task")
        #expect(updatedTask.action == "update")
        #expect(updatedTask.taskId == "task-1")
        #expect(updatedTask.todos?.count == 2)
        #expect(updatedTask.todos?.last?.content == "Show task banner")

        let completeAssistant = try makeMessageEvent(
            messageId: 5,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-complete",
                "function": [
                    "name": "manage_task",
                    "arguments": jsonString([
                        "action": "complete",
                        "task_id": "task-1",
                    ]),
                ],
            ]])
        )
        _ = adapter.process(eventType: "message", data: completeAssistant)

        let completeTool = try makeMessageEvent(
            messageId: 6,
            role: "tool",
            content: jsonString(["message": "Task task-1 completed."])
        )
        let completeOutput = adapter.process(eventType: "message", data: completeTool)
        let completedTask = try #require(completeOutput.historyMessages.first)
        #expect(completedTask.type == "task")
        #expect(completedTask.action == "end")
        #expect(completedTask.taskId == "task-1")
    }

    @MainActor
    @Test
    func `local agent session only reports open tasks while runtime is active or waiting`() {
        let session = LocalAgentSession(sessionID: "session-1")

        #expect(session.hasOpenTask == false)

        session.injectMessage(makeTaskHistoryMessage(id: "task-start", action: "start", taskId: "task-1"))
        #expect(session.hasOpenTask == false)

        session.reconcileStoredSessionInfo(
            LocalAgentSessionInfo(
                sessionId: "session-1",
                agentId: "agent-1",
                name: "Untitled",
                purpose: nil,
                status: "active",
                activityStatus: "running",
                lastRoundError: nil,
                createdAt: 0,
                lastActivityAt: nil
            ),
            reason: "test"
        )
        #expect(session.hasOpenTask)

        session.injectMessage(makeTaskHistoryMessage(id: "task-update", action: "update", taskId: "task-1"))
        #expect(session.hasOpenTask)

        session.reconcileStoredSessionInfo(
            LocalAgentSessionInfo(
                sessionId: "session-1",
                agentId: "agent-1",
                name: "Untitled",
                purpose: nil,
                status: "idle",
                activityStatus: "paused",
                lastRoundError: nil,
                createdAt: 0,
                lastActivityAt: nil
            ),
            reason: "test"
        )
        #expect(session.hasOpenTask == false)

        session.reconcileStoredSessionInfo(
            LocalAgentSessionInfo(
                sessionId: "session-1",
                agentId: "agent-1",
                name: "Untitled",
                purpose: nil,
                status: "idle",
                activityStatus: "waiting",
                lastRoundError: nil,
                createdAt: 0,
                lastActivityAt: nil
            ),
            reason: "test"
        )
        #expect(session.hasOpenTask)

        session.injectMessage(makeTaskHistoryMessage(id: "task-end", action: "end", taskId: "task-1"))
        #expect(session.hasOpenTask == false)
    }

    @Test
    func `local agent session task title falls back to session title`() {
        let session = LocalAgentSession(sessionID: "session-1")

        session.loadLocalFixture(
            title: "Chat session title",
            messages: [
                makeTaskHistoryMessage(id: "task-end", action: "end", taskId: "task-1"),
            ]
        )

        #expect(session.taskDisplayTitle == "Chat session title")
    }

    @Test
    func `local agent session task title prefers explicit task title`() {
        let session = LocalAgentSession(sessionID: "session-1")

        session.loadLocalFixture(
            title: "Chat session title",
            messages: [
                makeTaskHistoryMessage(id: "task-start", action: "start", taskId: "task-1"),
                makeTaskHistoryMessage(id: "task-end", action: "end", taskId: "task-1"),
            ]
        )

        #expect(session.taskDisplayTitle == "Wire task list")
    }

    @Test
    func `local agent adapter ignores unsupported tool calls when matching FIFO tool results`() throws {
        let adapter = LocalAgentEventAdapter()

        let assistant = try makeMessageEvent(
            messageId: 10,
            role: "assistant",
            content: assistantContent(toolCalls: [
                [
                    "id": "call-shell",
                    "function": [
                        "name": "shell",
                        "arguments": jsonString([
                            "command": "pwd",
                        ]),
                    ],
                ],
                [
                    "id": "call-start",
                    "function": [
                        "name": "manage_task",
                        "arguments": jsonString([
                            "action": "start",
                            "title": "Wire task list",
                        ]),
                    ],
                ],
            ])
        )
        _ = adapter.process(eventType: "message", data: assistant)

        let tool = try makeMessageEvent(
            messageId: 11,
            role: "tool",
            content: jsonString([
                "task_id": "task-1",
                "message": "Task started: Wire task list",
            ])
        )
        let output = adapter.process(eventType: "message", data: tool)
        let taskMessage = try #require(output.historyMessages.first)
        #expect(taskMessage.type == "task")
        #expect(taskMessage.action == "start")
        #expect(taskMessage.taskId == "task-1")
    }

    @Test
    func `local agent adapter does not fall back to FIFO when explicit tool id is untracked`() throws {
        let adapter = LocalAgentEventAdapter()

        let assistant = try makeMessageEvent(
            messageId: 20,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-start",
                "function": [
                    "name": "manage_task",
                    "arguments": jsonString([
                        "action": "start",
                        "title": "Wire task list",
                    ]),
                ],
            ]])
        )
        _ = adapter.process(eventType: "message", data: assistant)

        let unknownToolResult = try jsonString([
            "message_id": 21,
            "role": "tool",
            "content": jsonString([
                "task_id": "wrong-task",
                "message": "unexpected",
            ]),
            "tool_use_id": "call-unknown",
            "created_at": 1233,
        ])
        let unknownOutput = adapter.process(eventType: "tool_result", data: unknownToolResult)
        #expect(unknownOutput.historyMessages.isEmpty)

        let trackedToolResult = try jsonString([
            "message_id": 22,
            "role": "tool",
            "content": jsonString([
                "task_id": "task-1",
                "message": "Task started: Wire task list",
            ]),
            "tool_use_id": "call-start",
            "created_at": 1234,
        ])
        let trackedOutput = adapter.process(eventType: "tool_result", data: trackedToolResult)
        let taskMessage = try #require(trackedOutput.historyMessages.first)
        #expect(taskMessage.type == "task")
        #expect(taskMessage.action == "start")
        #expect(taskMessage.taskId == "task-1")
    }

    @Test
    func `local agent adapter preserves stored timestamp for webbrowse tool results`() throws {
        let adapter = LocalAgentEventAdapter()

        let assistant = try makeMessageEvent(
            messageId: 30,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-web",
                "function": [
                    "name": "WebBrowse",
                    "arguments": jsonString([
                        "query": "openbridge",
                    ]),
                ],
            ]])
        )
        _ = adapter.process(eventType: "message", data: assistant)

        let storedToolResult = try jsonString([
            "message_id": 31,
            "role": "tool",
            "content": "browse result",
            "tool_use_id": "call-web",
            "created_at": 9876,
        ])
        let output = adapter.process(eventType: "tool_result", data: storedToolResult)
        let historyMessage = try #require(output.historyMessages.first)
        #expect(historyMessage.role == "tool")
        #expect(historyMessage.toolUseId == "call-web")
        #expect(historyMessage.timestamp == 9876.0)
    }

    @Test
    func `local agent adapter emits generic tool status updates with stable message ids`() throws {
        let adapter = LocalAgentEventAdapter()

        let assistant = try makeMessageEvent(
            messageId: 40,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-exec",
                "function": [
                    "name": "Exec",
                    "arguments": jsonString([
                        "description": "List workspace",
                        "command": "ls",
                        "environment": "local",
                    ]),
                ],
            ]])
        )
        let assistantOutput = adapter.process(eventType: "message", data: assistant)
        let runningMessage = try #require(assistantOutput.historyMessages.last)
        #expect(runningMessage.id == "agent-tool-call-exec")
        #expect(runningMessage.toolUseId == "call-exec")
        let runningPayload = try #require(runningMessage.content?.first?.text)
        #expect(runningPayload.contains("\"status\":\"running\""))
        #expect(runningPayload.contains("\"command\":\"ls\""))
        #expect(runningPayload.contains("\\\"environment\\\":\\\"local\\\""))

        let toolEnd = try jsonString([
            "call_id": "call-exec",
            "error": NSNull(),
        ])
        let toolEndOutput = adapter.process(eventType: "tool_end", data: toolEnd)
        let completedMessage = try #require(toolEndOutput.historyMessages.first)
        #expect(completedMessage.id == "agent-tool-call-exec")
        let completedPayload = try #require(completedMessage.content?.first?.text)
        #expect(completedPayload.contains("\"status\":\"completed\""))
        #expect(completedPayload.contains("\"tool_name\":\"Exec\""))
    }

    @Test
    func `local agent adapter does not regress completed generic tool status when assistant message arrives later`() throws {
        let adapter = LocalAgentEventAdapter()

        let toolStart = try jsonString([
            "call_id": "call-exec",
            "tool_name": "Exec",
            "arguments": jsonString([
                "description": "List workspace",
                "command": "ls",
                "environment": "local",
            ]),
        ])
        let startOutput = adapter.process(eventType: "tool_start", data: toolStart)
        let startMessage = try #require(startOutput.historyMessages.first)
        let startPayload = try #require(startMessage.content?.first?.text)
        #expect(startPayload.contains("\"status\":\"running\""))

        let toolEnd = try jsonString([
            "call_id": "call-exec",
        ])
        let toolEndOutput = adapter.process(eventType: "tool_end", data: toolEnd)
        let completedMessage = try #require(toolEndOutput.historyMessages.first)
        let completedPayload = try #require(completedMessage.content?.first?.text)
        #expect(completedMessage.id == "agent-tool-call-exec")
        #expect(completedPayload.contains("\"status\":\"completed\""))

        let assistant = try makeMessageEvent(
            messageId: 41,
            role: "assistant",
            content: assistantContent(toolCalls: [[
                "id": "call-exec",
                "function": [
                    "name": "Exec",
                    "arguments": jsonString([
                        "description": "List workspace",
                        "command": "ls",
                        "environment": "local",
                    ]),
                ],
            ]])
        )
        let assistantOutput = adapter.process(eventType: "message", data: assistant)
        #expect(assistantOutput.historyMessages.count == 1)
        let assistantMessage = try #require(assistantOutput.historyMessages.first)
        #expect(assistantMessage.id == "agent-41")
    }

    @Test
    func `local agent heartbeat decodes explicit last title`() throws {
        let heartbeat = try JSONDecoder().decode(
            LocalAgentHeartbeat.self,
            from: Data(#"""
            {
              "agent_id": "agent-1",
              "schedule_id": "schedule-1",
              "prompt": "heartbeat prompt",
              "cron_expr": "*/15 * * * *",
              "timezone": "UTC",
              "status": "active",
              "next_run_at": 100,
              "last_result": "notified",
              "last_title": "修复 copy-editor 空白页",
              "last_summary": "已修复空白页",
              "last_surface_session_id": "surface-1",
              "created_at": 1,
              "updated_at": 2
            }
            """#.utf8)
        )

        #expect(heartbeat.lastTitle == "修复 copy-editor 空白页")
        #expect(heartbeat.lastSummary == "已修复空白页")
        #expect(heartbeat.lastSurfaceSessionId == "surface-1")
    }

    private func makeMessageEvent(
        messageId: Int64,
        role: String,
        content: String
    ) throws -> String {
        try jsonString([
            "message_id": messageId,
            "role": role,
            "content": content,
        ])
    }

    private func assistantContent(toolCalls: [[String: Any]]) throws -> String {
        try jsonString([
            "text": "",
            "tool_calls": toolCalls,
        ])
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    private func makeTaskHistoryMessage(id: String, action: String, taskId: String) -> SessionHistoryMessage {
        SessionHistoryMessage(
            id: id,
            type: "task",
            role: nil,
            timestamp: Date().timeIntervalSince1970,
            content: nil,
            messageId: nil,
            taskId: taskId,
            action: action,
            taskTitle: action == "start" ? "Wire task list" : nil,
            todos: nil,
            sandboxId: nil,
            acceptedSummary: nil,
            reviewDiff: nil,
            reviewDiffTotal: nil,
            confirmationId: nil,
            traceparent: nil,
            tracestate: nil,
            question: nil,
            questionReply: nil,
            saveFileRequest: nil,
            saveFileReply: nil,
            permissionRequest: nil,
            permissionReply: nil,
            secretInput: nil,
            secretInputReply: nil,
            schedule: nil,
            toolUseId: nil,
            errorType: nil,
            error: nil
        )
    }
}

private enum TestSkillType {
    case custom
    case sync
    case imported
}

private func makeSkill(
    name: String,
    description: String,
    type: TestSkillType,
    disabled: Bool = false
) -> Skill {
    let basePath = switch type {
    case .custom:
        "/Users/tester/.openbridge/skills/custom"
    case .sync:
        "/Users/tester/.openbridge/skills/sync"
    case .imported:
        "/Users/tester/.openbridge/skills/imported"
    }
    let fileURL = URL(fileURLWithPath: "\(basePath)/\(name)/SKILL.md")
    let category = switch type {
    case .custom:
        Skill.Category.custom
    case .sync:
        Skill.Category.synced
    case .imported:
        Skill.Category.imported
    }
    let source = switch type {
    case .sync:
        Skill.Source.synced(fileURL: fileURL)
    case .custom, .imported:
        Skill.Source.legacy(fileURL: fileURL)
    }

    return Skill(
        id: fileURL.path,
        data: SkillData(
            frontmatter: .init(
                name: name,
                description: description,
                metadata: SkillData.Metadata(
                    displayName: nil,
                    icon: nil,
                    color: nil,
                    visibility: nil,
                    pinned: nil,
                    disabled: disabled ? true : nil,
                    sendDirectly: nil,
                    outputDir: nil,
                    placeholder: nil
                )
            ),
            content: ""
        ),
        category: category,
        source: source
    )
}
