import Foundation
@testable import OpenBridge
import Testing

struct LocalAgentSessionTests {
    private func timestamp(_ seconds: Int) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    @Test
    func `sandbox review artifacts record message and next turn context`() {
        let diffs = [
            FileDiff(
                path: "Sources/App.swift",
                mode: 0o100644,
                isDir: false,
                isUpdated: true,
                isDeleted: false,
                timestamp: timestamp(1),
                size: 128
            ),
            FileDiff(
                path: "Sources/NewView.swift",
                mode: 0o100644,
                isDir: false,
                isUpdated: false,
                isDeleted: false,
                timestamp: timestamp(2),
                size: 64
            ),
            FileDiff(
                path: "Sources/Renamed.swift",
                mode: 0o100644,
                isDir: false,
                isUpdated: true,
                isDeleted: false,
                movedFrom: "Sources/Old.swift",
                timestamp: timestamp(3),
                size: 96
            ),
            FileDiff(
                path: "Sources/Deleted.swift",
                mode: 0o100644,
                isDir: false,
                isUpdated: false,
                isDeleted: true,
                timestamp: timestamp(4),
                size: 0
            ),
        ]

        let artifacts = LocalAgentSession.makeSandboxReviewArtifacts(
            sandboxID: "local-vm",
            summary: "Accepted 2 files and rejected 2 files.",
            reviewDiff: diffs,
            reviewDiffTotal: 6
        )

        #expect(artifacts.message.type == "sandbox_review")
        #expect(artifacts.message.sandboxId == "local-vm")
        #expect(artifacts.message.acceptedSummary == "Accepted 2 files and rejected 2 files.")
        #expect(artifacts.message.reviewDiff == diffs)
        #expect(artifacts.message.reviewDiffTotal == 6)
        #expect(artifacts.contextReminder.contains("[system] Accepted 2 files and rejected 2 files."))
        #expect(artifacts.contextReminder.contains("UPDATED Sources/App.swift"))
        #expect(artifacts.contextReminder.contains("NEW Sources/NewView.swift"))
        #expect(artifacts.contextReminder.contains("MOVED Sources/Old.swift -> Sources/Renamed.swift"))
        #expect(artifacts.contextReminder.contains("DELETED Sources/Deleted.swift"))
        #expect(artifacts.contextReminder.contains("... 2 more changes omitted."))
    }

    @Test
    func `sandbox review artifacts clip large diff lists`() {
        var diffs: [FileDiff] = []
        for index in 0 ..< 120 {
            let diff = FileDiff(
                path: "file-\(index).txt",
                mode: UInt32(0o100644),
                isDir: false,
                isUpdated: index.isMultiple(of: 2),
                isDeleted: false,
                timestamp: timestamp(index),
                size: Int64(index)
            )
            diffs.append(diff)
        }

        let artifacts = LocalAgentSession.makeSandboxReviewArtifacts(
            sandboxID: "local-vm",
            summary: "Accepted 120 files.",
            reviewDiff: diffs,
            reviewDiffTotal: 120
        )

        #expect(artifacts.message.reviewDiff?.count == 100)
        #expect(artifacts.message.reviewDiffTotal == 120)
        #expect(artifacts.contextReminder.contains("file-99.txt"))
        #expect(!artifacts.contextReminder.contains("file-100.txt"))
        #expect(artifacts.contextReminder.contains("... 20 more changes omitted."))
    }

    @Test
    func `serialize outbound content renders image file references`() {
        let outbound = LocalAgentSession.serializeOutboundContent([
            SessionHistoryMessage.Content(
                type: "image",
                text: nil,
                url: "https://example.com/image.png",
                fileRef: .init(environmentId: "Local", path: "/tmp/image.png"),
                fileName: "image.png",
                mimeType: "image/png"
            ),
            SessionHistoryMessage.Content(
                type: "text",
                text: "Describe this image",
                url: nil,
                fileRef: nil,
                fileName: nil,
                mimeType: nil
            ),
        ])

        #expect(outbound == "[type:\"image\" env:\"Local\" path:\"/tmp/image.png\"]\nDescribe this image")
    }

    @Test
    func `serialize outbound content escapes image reference components`() {
        let outbound = LocalAgentSession.serializeOutboundContent([
            SessionHistoryMessage.Content(
                type: "image",
                text: nil,
                url: nil,
                fileRef: .init(environmentId: "Desk \"A\"", path: #"/tmp/with"quote\image.png"#),
                fileName: "image.png",
                mimeType: "image/png"
            ),
        ])

        #expect(outbound == #"[type:"image" env:"Desk \"A\"" path:"/tmp/with\"quote\\image.png"]"#)
    }

    @Test
    func `parse raw image references into structured content`() throws {
        let content = LocalAgentContentParser.parse("""
        [type:"image" env:"Local" path:"/tmp/example.jpg"]
        Describe this image
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 2)
        #expect(blocks[0].type == "image")
        #expect(blocks[0].fileRef?.environmentId == "Local")
        #expect(blocks[0].fileRef?.path == "/tmp/example.jpg")
        #expect(blocks[1].type == "text")
        #expect(blocks[1].text == "Describe this image")
    }

    @Test
    func `parse raw image references drops empty placeholder text`() throws {
        let content = LocalAgentContentParser.parse("""
        [type:"image" env:"Local" path:"/tmp/example.jpg"]
        <empty/>
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].type == "image")
        #expect(blocks[0].fileRef?.environmentId == "Local")
        #expect(blocks[0].fileRef?.path == "/tmp/example.jpg")
    }

    @Test
    func `parse JSON image content keeps vfs file refs local without backend urls`() throws {
        let content = LocalAgentContentParser.parse("""
        [{
          "type":"image",
          "file_ref":{"environment_id":"local-vm","path":"/tmp/cat.png"},
          "file_refs":[
            {"environment_id":"local-vm","path":"/tmp/cat.png"},
            {"environment_id":"vfs","path":"/.agent/deliveries/session/call/cat.png"}
          ],
          "file_name":"cat.png",
          "mime_type":"image/png"
        }]
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].type == "image")
        #expect(blocks[0].fileRef?.environmentId == "local-vm")
        #expect(blocks[0].fileRef?.path == "/tmp/cat.png")
        #expect(blocks[0].fileRefs?.map(\.environmentId) == ["local-vm", "vfs"])
        #expect(blocks[0].url == nil)
    }

    @Test
    func `parse JSON image content keeps legacy path only vfs refs local`() throws {
        let content = LocalAgentContentParser.parse("""
        [{
          "type":"image",
          "file_ref":{"path":"/.agent/deliveries/session/call/cat.png"},
          "file_name":"cat.png",
          "mime_type":"image/png"
        }]
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].type == "image")
        #expect(blocks[0].fileRef?.path == "/.agent/deliveries/session/call/cat.png")
        #expect(blocks[0].url == nil)
    }

    @Test
    func `parse JSON image content preserves service-provided URLs`() throws {
        let content = LocalAgentContentParser.parse("""
        [{"type":"image","url":"/v1/user/agent/files/.agent/deliveries/session/call/cat.png","file_ref":{"path":"/.agent/deliveries/session/call/cat.png"},"file_name":"cat.png","mime_type":"image/png"}]
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].type == "image")
        #expect(blocks[0].url == "/v1/user/agent/files/.agent/deliveries/session/call/cat.png")
    }

    @Test
    func `parse JSON directory content keeps local refs even when vfs refs are present`() throws {
        let content = LocalAgentContentParser.parse("""
        [{
          "type":"file",
          "file_ref":{"environment_id":"local-vm","path":"/tmp/folder"},
          "file_refs":[
            {"environment_id":"local-vm","path":"/tmp/folder"},
            {"environment_id":"vfs","path":"/.agent/user/sessions/session-1/attachments/folder"}
          ],
          "file_name":"folder",
          "entry_kind":"dir"
        }]
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 1)
        #expect(blocks[0].type == "file")
        #expect(blocks[0].fileRef?.path == "/tmp/folder")
        #expect(blocks[0].url == nil)
    }

    @Test
    func `parse placeholder only text returns no visible content`() throws {
        let content = try #require(LocalAgentContentParser.parse("<empty/>"))
        #expect(content.isEmpty)
    }

    @Test
    func `serialize outbound content renders quote references`() {
        let outbound = LocalAgentSession.serializeOutboundContent([
            SessionHistoryMessage.Content(
                type: "quote",
                text: """
                Jason tomorrow at 4 PM
                Please confirm
                """,
                quoteRef: .init(
                    sourceMessageId: "msg-123",
                    startOffset: 12,
                    endOffset: 41
                )
            ),
            SessionHistoryMessage.Content(
                type: "text",
                text: "Draft a follow-up",
                url: nil,
                fileRef: nil,
                fileName: nil,
                mimeType: nil
            ),
        ])

        #expect(
            outbound ==
                """
                <quote source-message-id="msg-123" start="12" end="41">Jason tomorrow at 4 PM&#10;Please confirm</quote>
                Draft a follow-up
                """
        )
    }

    @Test
    func `parse raw quote references into structured content`() throws {
        let content = LocalAgentContentParser.parse("""
        <quote source-message-id="msg-123" start="12" end="41">Jason tomorrow at 4 PM&#10;Please confirm</quote>
        Draft a follow-up
        """)

        let blocks = try #require(content)
        #expect(blocks.count == 2)
        #expect(blocks[0].type == "quote")
        #expect(blocks[0].text == "Jason tomorrow at 4 PM\nPlease confirm")
        #expect(blocks[0].quoteRef?.sourceMessageId == "msg-123")
        #expect(blocks[0].quoteRef?.startOffset == 12)
        #expect(blocks[0].quoteRef?.endOffset == 41)
        #expect(blocks[1].type == "text")
        #expect(blocks[1].text == "Draft a follow-up")
    }

    @MainActor
    @Test
    func `prepare outbound content preserves quote references`() async throws {
        let session = LocalAgentSession(sessionID: "session-1")
        let quoteRef = SessionHistoryMessage.QuoteReference(
            sourceMessageId: "msg-123",
            startOffset: 12,
            endOffset: 41
        )

        let prepared = try await session.prepareOutboundContent([
            SessionHistoryMessage.Content(
                type: "quote",
                text: "Jason tomorrow at 4 PM\nPlease confirm",
                quoteRef: quoteRef
            ),
            SessionHistoryMessage.Content(
                type: "text",
                text: "Draft a follow-up"
            ),
        ])

        #expect(prepared.count == 2)
        #expect(prepared[0].type == "quote")
        #expect(prepared[0].text == "Jason tomorrow at 4 PM\nPlease confirm")
        #expect(prepared[0].quoteRef == quoteRef)
        #expect(
            LocalAgentSession.serializeOutboundContent(prepared) ==
                """
                <quote source-message-id="msg-123" start="12" end="41">Jason tomorrow at 4 PM&#10;Please confirm</quote>
                Draft a follow-up
                """
        )
    }

    @MainActor
    @Test
    func `prepare outbound content keeps vfs attachment refs local`() async throws {
        let session = LocalAgentSession(sessionID: "session-1")

        let prepared = try await session.prepareOutboundContent([
            SessionHistoryMessage.Content(
                type: "image",
                fileRef: .init(environmentId: "Local", path: "/tmp/image.png"),
                fileRefs: [
                    .init(
                        environmentId: "vfs",
                        path: "/.agent/user/sessions/session-1/attachments/image.png"
                    ),
                ],
                fileName: "image.png",
                mimeType: "image/png",
                entryKind: "file"
            ),
        ])

        #expect(prepared.count == 1)
        #expect(prepared[0].url == nil)
        #expect(prepared[0].fileRef?.environmentId == "local-vm")
        #expect(prepared[0].fileRef?.path == "/tmp/image.png")
        #expect(prepared[0].fileRefs?.count == 2)
        #expect(prepared[0].fileRefs?.map(\.environmentId) == ["local-vm", "vfs"])
    }

    @MainActor
    @Test
    func `prepare outbound content keeps directories local only`() async throws {
        let session = LocalAgentSession(sessionID: "session-1")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let prepared = try await session.prepareOutboundContent([
            SessionHistoryMessage.Content(
                type: "file",
                fileRef: .init(environmentId: "Local", path: directoryURL.path),
                fileRefs: [
                    .init(
                        environmentId: "vfs",
                        path: "/.agent/user/sessions/session-1/attachments/folder"
                    ),
                ],
                fileName: directoryURL.lastPathComponent,
                entryKind: "dir"
            ),
        ])

        #expect(prepared.count == 1)
        #expect(prepared[0].url == nil)
        #expect(prepared[0].fileRef?.path == directoryURL.path)
        #expect(prepared[0].fileRefs?.count == 1)
        #expect(prepared[0].fileRefs?.first?.environmentId == "local-vm")
        #expect(prepared[0].fileRefs?.first?.path == directoryURL.path)
    }

    @MainActor
    @Test
    func `make transport content serializes quote blocks into text`() {
        let session = LocalAgentSession(sessionID: "session-1")

        let transport = session.makeTransportContent(from: [
            SessionHistoryMessage.Content(
                type: "quote",
                text: "Jason tomorrow at 4 PM\nPlease confirm",
                quoteRef: .init(
                    sourceMessageId: "msg-123",
                    startOffset: 12,
                    endOffset: 41
                )
            ),
            SessionHistoryMessage.Content(
                type: "text",
                text: "Draft a follow-up"
            ),
        ])

        #expect(transport.count == 3)
        #expect(transport[0].type == "text")
        #expect(transport[0].text?.contains("<user-reminder>") == true)
        #expect(transport[1].type == "text")
        #expect(
            transport[1].text ==
                """
                <quote source-message-id="msg-123" start="12" end="41">Jason tomorrow at 4 PM&#10;Please confirm</quote>
                """
        )
        #expect(transport[1].quoteRef == nil)
        #expect(transport[2].type == "text")
        #expect(transport[2].text == "Draft a follow-up")
    }

    @MainActor
    @Test
    func `make transport content prepends macOS user reminder with connector aliases`() throws {
        let session = LocalAgentSession(sessionID: "session-1")

        let transport = session.makeTransportContent(from: [
            SessionHistoryMessage.Content(
                type: "text",
                text: "Please save the result for me."
            ),
        ])

        #expect(transport.count == 2)
        #expect(transport[0].type == "text")
        let reminder = try #require(transport[0].text)
        #expect(reminder.contains("<user-reminder>"))
        #expect(reminder.contains("place the file in environment \(LocalRuntimeConnector.EnvironmentKind.localVM.connectAlias)"))
        #expect(reminder.contains("(or \(LocalRuntimeConnector.EnvironmentKind.localMacOS.connectAlias) when the VM is unusable)."))
        #expect(reminder.contains("Use an absolute macOS home path"))
        #expect(reminder.contains("<home>/Desktop/result.md"))
        #expect(reminder.contains("instead of ~/... or $HOME/..."))
        #expect(transport[1].type == "text")
        #expect(transport[1].text == "Please save the result for me.")
    }

    @MainActor
    @Test
    func `make transport content keeps system reminder ahead of macOS user reminder`() {
        let session = LocalAgentSession(sessionID: "session-1")
        session.pendingLocalContextReminders = ["Please keep responses short."]

        let transport = session.makeTransportContent(from: [
            SessionHistoryMessage.Content(
                type: "text",
                text: "Do the thing."
            ),
        ])

        #expect(transport.count == 3)
        #expect(transport[0].text?.contains("<system-reminder>") == true)
        #expect(transport[1].text?.contains("<user-reminder>") == true)
        #expect(transport[2].text == "Do the thing.")
    }

    @MainActor
    @Test
    func `reconcile stored session info finishes missed paused round`() {
        let session = LocalAgentSession(sessionID: "session-1")
        var finished: [(String, String?)] = []

        session.onSessionFinished = { state, error in
            finished.append((state, error))
        }

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

        #expect(session.isProcessing == false)
        #expect(session.lastFinishState == "completed")
        #expect(finished.count == 1)
        #expect(finished[0].0 == "completed")
        #expect(finished[0].1 == nil)
    }

    @MainActor
    @Test
    func `settle local stop immediately completes the local session state`() {
        let session = LocalAgentSession(sessionID: "session-1")
        var finished: [(String, String?)] = []

        session.onSessionFinished = { state, error in
            finished.append((state, error))
        }

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

        session.settleLocalStop()

        #expect(session.isProcessing == false)
        #expect(session.lastFinishState == "completed")
        #expect(session.assistantState?.phase == "idle")
        #expect(finished.count == 1)
        #expect(finished[0].0 == "completed")
        #expect(finished[0].1 == nil)
    }

    @MainActor
    @Test
    func `reconcile waiting session keeps execution state active without task history`() {
        let session = LocalAgentSession(sessionID: "session-1")

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

        #expect(session.isProcessing)
        #expect(session.lastFinishState == nil)
        #expect(session.assistantState?.phase == "execution")
        #expect(session.hasOpenTask == false)

        session.settleLocalStop()

        #expect(session.hasOpenTask == false)
        #expect(session.isProcessing == false)
        #expect(session.lastFinishState == "completed")
    }

    @MainActor
    @Test
    func `runtime state can reopen a task after optimistic local stop`() {
        let session = LocalAgentSession(sessionID: "session-1")

        session.injectMessage(makeTaskHistoryMessage(id: "task-start", action: "start", taskId: "task-1"))
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

        session.settleLocalStop()
        #expect(session.hasOpenTask == false)
        #expect(session.lastFinishState == "completed")

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
            reason: "cancel_failed"
        )

        #expect(session.isProcessing)
        #expect(session.lastFinishState == nil)
        #expect(session.hasOpenTask)
    }

    @MainActor
    @Test
    func `reconcile stored session info surfaces failed state`() {
        let session = LocalAgentSession(sessionID: "session-1")
        var finished: [(String, String?)] = []

        session.onSessionFinished = { state, error in
            finished.append((state, error))
        }

        session.reconcileStoredSessionInfo(
            LocalAgentSessionInfo(
                sessionId: "session-1",
                agentId: "agent-1",
                name: "Untitled",
                purpose: nil,
                status: "idle",
                activityStatus: "failed",
                lastRoundError: "boom",
                createdAt: 0,
                lastActivityAt: nil
            ),
            reason: "test"
        )

        #expect(session.isProcessing == false)
        #expect(session.lastFinishState == "failed")
        #expect(finished.count == 1)
        #expect(finished[0].0 == "failed")
        #expect(finished[0].1 == "boom")
    }

    @MainActor
    @Test
    func `reconcile stored session info restores in flight session`() {
        let session = LocalAgentSession(sessionID: "session-1")
        var startedCount = 0

        session.onSessionStarted = {
            startedCount += 1
        }

        session.reconcileStoredSessionInfo(
            LocalAgentSessionInfo(
                sessionId: "session-1",
                agentId: "agent-1",
                name: "Untitled",
                purpose: nil,
                status: "running",
                activityStatus: "running",
                lastRoundError: nil,
                createdAt: 0,
                lastActivityAt: nil
            ),
            reason: "test"
        )

        #expect(session.isProcessing == true)
        #expect(session.lastFinishState == nil)
        #expect(startedCount == 1)
    }

    @MainActor
    @Test
    func `reconcile stored session info ignores duplicate terminal snapshot`() {
        let session = LocalAgentSession(sessionID: "session-1")
        var finished: [(String, String?)] = []

        session.onSessionFinished = { state, error in
            finished.append((state, error))
        }

        let snapshot = LocalAgentSessionInfo(
            sessionId: "session-1",
            agentId: "agent-1",
            name: "Untitled",
            purpose: nil,
            status: "idle",
            activityStatus: "paused",
            lastRoundError: nil,
            createdAt: 0,
            lastActivityAt: nil
        )

        session.reconcileStoredSessionInfo(snapshot, reason: "test")
        session.reconcileStoredSessionInfo(snapshot, reason: "test")

        #expect(session.lastFinishState == "completed")
        #expect(finished.count == 1)
    }
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
