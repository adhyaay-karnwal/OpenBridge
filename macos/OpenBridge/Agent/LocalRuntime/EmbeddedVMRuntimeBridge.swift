import CryptoKit
import Foundation
import OSLog

#if canImport(SandboxVM)
    @preconcurrency import SandboxVM

    extension SandboxvmSharedLocalConnectorRuntime: @unchecked Sendable {}
#endif

actor EmbeddedVMRuntimeBridge {
    struct StatResult: Decodable, Sendable {
        let path: String
        let kind: String
        let size: Int64
        let mode: Int
        let modifiedAt: Int

        private enum CodingKeys: String, CodingKey {
            case path
            case kind
            case size
            case mode
            case modifiedAt = "modified_at"
        }
    }

    struct DirectoryEntry: Decodable, Sendable {
        let name: String
        let kind: String
        let size: Int
        let modifiedAt: Int

        private enum CodingKeys: String, CodingKey {
            case name
            case kind
            case size
            case modifiedAt = "modified_at"
        }
    }

    struct GrepMatch: Decodable, Sendable {
        let file: String
        let line: Int
        let content: String
    }

    struct GlobResult: Decodable, Sendable {
        let matches: [String]
        let truncated: Bool
    }

    struct GrepResult: Decodable, Sendable {
        let matches: [GrepMatch]
        let truncated: Bool
    }

    struct ExecResult: Decodable, Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int

        private enum CodingKeys: String, CodingKey {
            case stdout
            case stderr
            case exitCode = "exit_code"
        }
    }

    struct ReadStreamHandle: Sendable {
        let streamID: String
        let totalSize: Int64
    }

    struct ReadStreamChunk: Sendable {
        let data: Data
        let eof: Bool
    }

    struct ReviewActionResult: Sendable {
        let summary: String
        let state: WorkspaceState?
        let reviewDiff: [FileDiff]
        let reviewDiffTotal: Int
    }

    enum RuntimeError: LocalizedError {
        case missingResource(String)
        case invalidResponse(String)
        case unavailable(String)
        case missingLocalBridgeConfig

        var errorDescription: String? {
            switch self {
            case let .missingResource(name): "Missing embedded VM resource: \(name)"
            case let .invalidResponse(detail): "Invalid embedded VM response: \(detail)"
            case let .unavailable(detail): "Embedded VM runtime unavailable: \(detail)"
            case .missingLocalBridgeConfig: "Embedded VM runtime missing local callback configuration"
            }
        }
    }

    private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "EmbeddedVMRuntimeBridge")
    #if canImport(SandboxVM)
        private struct SharedRuntimeScope: Equatable {
            let rootPath: String
            let mountsJSON: String
            let metadataDir: String
            let rootfsOverlayDir: String
        }

        private struct SharedRuntimeDescriptor {
            let scope: SharedRuntimeScope
            let config: SandboxvmLocalConnectorConfig
            let localCallbackBaseURL: String
            let localCallbackAPIKey: String

            func withScope(_ scope: SharedRuntimeScope) -> SharedRuntimeDescriptor {
                let copiedConfig = SandboxvmLocalConnectorConfig()
                copiedConfig.rootPath = scope.rootPath
                copiedConfig.mountsJSON = scope.mountsJSON
                copiedConfig.kernelPath = config.kernelPath
                copiedConfig.rootfsPath = config.rootfsPath
                copiedConfig.backendURL = config.backendURL
                copiedConfig.backendAPIKey = config.backendAPIKey
                copiedConfig.metadataDir = scope.metadataDir
                copiedConfig.rootfsOverlayDir = scope.rootfsOverlayDir
                copiedConfig.readMaxBytes = config.readMaxBytes
                copiedConfig.maxMatches = config.maxMatches
                copiedConfig.execOutputMaxBytes = config.execOutputMaxBytes
                return SharedRuntimeDescriptor(
                    scope: scope,
                    config: copiedConfig,
                    localCallbackBaseURL: localCallbackBaseURL,
                    localCallbackAPIKey: localCallbackAPIKey
                )
            }
        }

        private struct ReadStreamOwner {
            let sessionKey: String
            let runtimeStreamID: String
        }

        private actor SharedRuntimeStore {
            private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "EmbeddedVMRuntimeBridge.Store")
            private var sharedRuntime: SandboxvmSharedLocalConnectorRuntime?
            private var sharedRuntimeScope: SharedRuntimeScope?
            private var sharedRuntimeLoadingTask: Task<SandboxvmSharedLocalConnectorRuntime, Error>?
            private var sharedRuntimeLoadingScope: SharedRuntimeScope?
            private var sessionScopes: [String: SharedRuntimeScope] = [:]

            func ensureRuntime(using descriptor: SharedRuntimeDescriptor) async throws -> SandboxvmSharedLocalConnectorRuntime {
                if let runtime = runtimeIfLoaded(matching: descriptor.scope) {
                    try await EmbeddedVMRuntimeBridge.refreshBackendConfig(runtime, descriptor: descriptor)
                    return runtime
                }
                if let loadingTask = sharedRuntimeLoadingTask {
                    let loadingScope = sharedRuntimeLoadingScope
                    let runtime = try await loadingTask.value
                    if sharedRuntimeLoadingTask != nil, loadingScope == sharedRuntimeLoadingScope {
                        sharedRuntimeLoadingTask = nil
                        sharedRuntimeLoadingScope = nil
                    }
                    if loadingScope == descriptor.scope {
                        sharedRuntime = runtime
                        sharedRuntimeScope = descriptor.scope
                        try await EmbeddedVMRuntimeBridge.refreshBackendConfig(runtime, descriptor: descriptor)
                        return runtime
                    }
                    logger.info("Closing mismatched shared runtime load for root \(descriptor.scope.rootPath, privacy: .public)")
                }

                if let runtime = sharedRuntime {
                    logger.info("Closing stale shared runtime before reload for root \(descriptor.scope.rootPath, privacy: .public)")
                    try await EmbeddedVMRuntimeBridge.closeSharedRuntime(runtime)
                    sharedRuntime = nil
                    sharedRuntimeScope = nil
                }

                logger.info("Creating shared runtime for root \(descriptor.scope.rootPath, privacy: .public)")
                let task = Task<SandboxvmSharedLocalConnectorRuntime, Error> {
                    try await EmbeddedVMRuntimeBridge.createRuntime(config: descriptor.config)
                }
                sharedRuntimeLoadingTask = task
                sharedRuntimeLoadingScope = descriptor.scope

                do {
                    let runtime = try await task.value
                    sharedRuntime = runtime
                    sharedRuntimeScope = descriptor.scope
                    sharedRuntimeLoadingTask = nil
                    sharedRuntimeLoadingScope = nil
                    try await EmbeddedVMRuntimeBridge.refreshBackendConfig(runtime, descriptor: descriptor)
                    return runtime
                } catch {
                    sharedRuntimeLoadingTask = nil
                    sharedRuntimeLoadingScope = nil
                    throw error
                }
            }

            func runtimeForReviewIfAvailable(using descriptor: SharedRuntimeDescriptor, sessionID: String) async throws -> SandboxvmSharedLocalConnectorRuntime? {
                if let runtime = runtimeIfLoaded(matching: descriptor.scope), runtime.hasSessionState(sessionID) {
                    try await EmbeddedVMRuntimeBridge.refreshBackendConfig(runtime, descriptor: descriptor)
                    return runtime
                }
                let runtime = try await ensureRuntime(using: descriptor)
                guard runtime.hasSessionState(sessionID) else {
                    return nil
                }
                return runtime
            }

            func noteSession(_ sessionID: String, scope: SharedRuntimeScope) {
                sessionScopes[sessionID] = scope
            }

            func scopeForSession(_ sessionID: String) -> SharedRuntimeScope? {
                sessionScopes[sessionID]
            }

            func runtimeIfLoaded(matching scope: SharedRuntimeScope) -> SandboxvmSharedLocalConnectorRuntime? {
                guard sharedRuntimeScope == scope else {
                    return nil
                }
                return sharedRuntime
            }

            func closeRuntime() async throws {
                let runtime = sharedRuntime
                let loadingTask = sharedRuntimeLoadingTask
                sharedRuntime = nil
                sharedRuntimeScope = nil
                sharedRuntimeLoadingTask = nil
                sharedRuntimeLoadingScope = nil

                if let runtime {
                    try await EmbeddedVMRuntimeBridge.closeSharedRuntime(runtime)
                    return
                }

                guard let loadingTask else { return }
                loadingTask.cancel()
                do {
                    let runtime = try await loadingTask.value
                    try await EmbeddedVMRuntimeBridge.closeSharedRuntime(runtime)
                } catch is CancellationError {
                    return
                } catch {
                    logger.info("Ignoring shared runtime load failure during shutdown: \(error.localizedDescription, privacy: .public)")
                }
            }

            func invalidateRuntime() async {
                let runtime = sharedRuntime
                let loadingTask = sharedRuntimeLoadingTask
                sharedRuntime = nil
                sharedRuntimeScope = nil
                sharedRuntimeLoadingTask = nil
                sharedRuntimeLoadingScope = nil

                loadingTask?.cancel()
                if let runtime {
                    do {
                        try await EmbeddedVMRuntimeBridge.closeSharedRuntime(runtime)
                    } catch {
                        logger.info("Ignoring shared runtime close failure during invalidation: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            func loadedRuntimeIsHealthy() async -> Bool {
                guard let runtime = sharedRuntime else {
                    return false
                }
                do {
                    try await EmbeddedVMRuntimeBridge.healthCheck(runtime)
                    return true
                } catch {
                    return false
                }
            }
        }

        private static let sharedRuntimeStore = SharedRuntimeStore()
        private var readStreamOwners: [String: ReadStreamOwner] = [:]
    #endif

    func shutdown() async {
        #if canImport(SandboxVM)
            readStreamOwners.removeAll()
            do {
                try await Self.sharedRuntimeStore.closeRuntime()
            } catch {
                logger.error("Failed to close embedded VM shared runtime during shutdown: \(error.localizedDescription)")
            }
        #endif
    }

    func shutdown(sessionID: String) async {
        do {
            try await shutdown(sessionID: sessionID, deleteSessionState: false)
        } catch {
            logger.error("Failed to shutdown embedded VM connector runtime for \(normalizedSessionKey(sessionID)): \(error.localizedDescription)")
        }
    }

    func deleteSessionState(sessionID: String) async throws {
        try await shutdown(sessionID: sessionID, deleteSessionState: true)
    }

    private func shutdown(sessionID: String, deleteSessionState: Bool) async throws {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            readStreamOwners = readStreamOwners.reduce(into: [:]) { partialResult, entry in
                if entry.value.sessionKey != sessionKey {
                    partialResult[entry.key] = entry.value
                }
            }

            let descriptor = try await makeSharedRuntimeDescriptor()
            let runtime: SandboxvmSharedLocalConnectorRuntime
            if deleteSessionState {
                runtime = try await Self.sharedRuntimeStore.ensureRuntime(using: descriptor)
            } else {
                guard let loadedRuntime = await Self.sharedRuntimeStore.runtimeIfLoaded(matching: descriptor.scope) else { return }
                runtime = loadedRuntime
            }
            try await runBlocking {
                if deleteSessionState {
                    try runtime.deleteSessionState(sessionKey)
                } else {
                    try runtime.closeSessionPreservingState(sessionKey)
                }
            }
        #endif
    }

    func workspaceState(sessionID: String) async throws -> WorkspaceState? {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            var descriptor = try await makeSharedRuntimeDescriptor()
            if let sessionScope = await Self.sharedRuntimeStore.scopeForSession(sessionKey) {
                descriptor = descriptor.withScope(sessionScope)
                logger.info("Local VM workspace state for session \(sessionKey, privacy: .public) using recorded runtime metadata \(sessionScope.metadataDir, privacy: .public)")
            } else {
                logger.info("Local VM workspace state for session \(sessionKey, privacy: .public) has no recorded runtime scope")
            }
            guard let runtime = try await Self.sharedRuntimeStore.runtimeForReviewIfAvailable(using: descriptor, sessionID: sessionKey) else {
                logger.info("Local VM workspace state unavailable: no review runtime for session \(sessionKey, privacy: .public)")
                return nil
            }
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.getSandboxStateJSON(sessionKey, error: &error)
                if let error { throw error }
                return value
            }
            let state: BridgeWorkspaceState = try Self.decodeJSON(payload)
            logger.info("Local VM workspace state loaded for session \(sessionKey, privacy: .public): sandbox=\(state.sandboxId, privacy: .public) diffs=\(state.fileDiff?.count ?? 0, privacy: .public)")
            return await MainActor.run {
                Self.makeWorkspaceState(from: state)
            }
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func previewFile(sessionID: String, path: String, environmentID: String?) async throws -> String {
        #if canImport(SandboxVM)
            _ = try await requireReviewRuntime(for: sessionID)
        #endif
        let cacheURL = try previewCacheURL(sessionID: sessionID, environmentID: environmentID, path: path)
        let fileManager = FileManager.default
        do {
            let data = try await readFile(sessionID: sessionID, at: path)
            try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            return cacheURL.path
        } catch {
            if fileManager.fileExists(atPath: cacheURL.path) {
                return cacheURL.path
            }
            throw error
        }
    }

    func acceptChanges(sessionID: String, paths: [String]) async throws -> ReviewActionResult {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await requireReviewRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                let data = try JSONEncoder().encode(paths)
                let pathsJSON = String(data: data, encoding: .utf8) ?? "[]"
                var error: NSError?
                let value = runtime.acceptChangesJSON(sessionKey, pathsJSON: pathsJSON, error: &error)
                if let error { throw error }
                return value
            }
            let result: AcceptChangesPayload = try Self.decodeJSON(payload)
            return await MainActor.run {
                ReviewActionResult(
                    summary: result.summary ?? "",
                    state: result.state.map(Self.makeWorkspaceState(from:)),
                    reviewDiff: result.reviewDiff?.map(Self.makeFileDiff(from:)) ?? [],
                    reviewDiffTotal: result.reviewDiff?.count ?? 0
                )
            }
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func discardAllChanges(sessionID: String) async throws -> ReviewActionResult {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await requireReviewRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.discardAllChangesJSON(sessionKey, error: &error)
                if let error { throw error }
                return value
            }
            let result: DiscardAllChangesPayload = try Self.decodeJSON(payload)
            return await MainActor.run {
                ReviewActionResult(
                    summary: result.summary ?? "",
                    state: result.state.map(Self.makeWorkspaceState(from:)),
                    reviewDiff: [],
                    reviewDiffTotal: 0
                )
            }
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func readFile(sessionID: String?, at path: String) async throws -> Data {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.readJSON(sessionKey, path: path, offset: 0, limit: 0, error: &error)
                if let error { throw error }
                return value
            }
            let result: FileReadResult = try Self.decodeJSON(payload)
            if result.encoding == "base64" {
                guard let data = Data(base64Encoded: result.content) else {
                    throw RuntimeError.invalidResponse("invalid base64 payload")
                }
                return data
            }
            return Data(result.content.utf8)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func openReadStream(sessionID: String?, at path: String) async throws -> ReadStreamHandle {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.openReadStreamJSON(sessionKey, path: path, error: &error)
                if let error { throw error }
                return value
            }
            let result: OpenReadStreamResult = try Self.decodeJSON(payload)
            let bridgeStreamID = UUID().uuidString
            readStreamOwners[bridgeStreamID] = ReadStreamOwner(sessionKey: sessionKey, runtimeStreamID: result.streamID)
            return ReadStreamHandle(streamID: bridgeStreamID, totalSize: result.size)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func readStreamChunk(id streamID: String, maxBytes: Int) async throws -> ReadStreamChunk {
        #if canImport(SandboxVM)
            guard let owner = readStreamOwners[streamID] else {
                throw RuntimeError.invalidResponse("unknown read stream: \(streamID)")
            }
            let runtime = try await ensureRuntime(for: owner.sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.readStreamChunkJSON(owner.sessionKey, streamID: owner.runtimeStreamID, maxBytes: maxBytes, error: &error)
                if let error { throw error }
                return value
            }
            let result: ReadStreamChunkResult = try Self.decodeJSON(payload)
            guard let data = Data(base64Encoded: result.content) else {
                throw RuntimeError.invalidResponse("invalid read stream chunk payload")
            }
            if result.eof {
                readStreamOwners.removeValue(forKey: streamID)
            }
            return ReadStreamChunk(data: data, eof: result.eof)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func closeReadStream(id streamID: String) async {
        #if canImport(SandboxVM)
            guard let owner = readStreamOwners.removeValue(forKey: streamID) else { return }
            let descriptor: SharedRuntimeDescriptor
            do {
                descriptor = try await makeSharedRuntimeDescriptor()
            } catch {
                logger.error("Failed to resolve embedded VM descriptor while closing read stream: \(error.localizedDescription)")
                return
            }
            guard let runtime = await Self.sharedRuntimeStore.runtimeIfLoaded(matching: descriptor.scope) else { return }
            do {
                try await runBlocking {
                    try runtime.closeReadStream(owner.sessionKey, streamID: owner.runtimeStreamID)
                }
            } catch {
                logger.error("Failed to close embedded VM read stream: \(error.localizedDescription)")
            }
        #endif
    }

    func writeFile(sessionID: String?, at path: String, data: Data) async throws {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            _ = try await runBlockingString {
                var error: NSError?
                let value = runtime.writeJSON(sessionKey, path: path, content: data.base64EncodedString(), encoding: "base64", mode: 0o644, error: &error)
                if let error { throw error }
                return value
            }
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func deleteFile(sessionID: String?, at path: String, recursive: Bool = false) async throws {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            _ = try await runBlockingString {
                var error: NSError?
                let value = runtime.deleteJSON(sessionKey, path: path, recursive: recursive, error: &error)
                if let error { throw error }
                return value
            }
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func stat(sessionID: String?, path: String) async throws -> StatResult {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.statJSON(sessionKey, path: path, error: &error)
                if let error { throw error }
                return value
            }
            return try Self.decodeJSON(payload)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func list(sessionID: String?, path: String) async throws -> [DirectoryEntry] {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.listJSON(sessionKey, path: path, error: &error)
                if let error { throw error }
                return value
            }
            let result: ListResult = try Self.decodeJSON(payload)
            return result.entries
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func glob(sessionID: String?, pattern: String, basePath: String?, limit: Int) async throws -> (matches: [String], truncated: Bool) {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.globJSON(sessionKey, pattern: pattern, path: basePath ?? "", error: &error)
                if let error { throw error }
                return value
            }
            let result: GlobResult = try Self.decodeJSON(payload)
            guard limit > 0, result.matches.count > limit else {
                return (result.matches, result.truncated)
            }
            return (Array(result.matches.prefix(limit)), true)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func grep(sessionID: String?, pattern: String, basePath: String?, globPattern: String?, limit: Int) async throws -> (matches: [GrepMatch], truncated: Bool) {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.grepJSON(sessionKey, pattern: pattern, path: basePath ?? "", glob: globPattern ?? "", error: &error)
                if let error { throw error }
                return value
            }
            let result: GrepResult = try Self.decodeJSON(payload)
            guard limit > 0, result.matches.count > limit else {
                return (result.matches, result.truncated)
            }
            return (Array(result.matches.prefix(limit)), true)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    func executeShellCommand(
        _ command: String,
        workingDir: String?,
        timeoutSeconds: Int?,
        env: [String: String],
        sessionID: String?,
        callerAgentID: String?
    ) async throws -> ExecResult {
        #if canImport(SandboxVM)
            let sessionKey = normalizedSessionKey(sessionID)
            let runtime = try await ensureRuntime(for: sessionKey)
            var executionEnv = env
            executionEnv["HOME"] = executionEnv["HOME"] ?? NSHomeDirectory()
            executionEnv["USER"] = executionEnv["USER"] ?? NSUserName()
            executionEnv["LOGNAME"] = executionEnv["LOGNAME"] ?? NSUserName()
            let envJSON = try String(data: JSONEncoder().encode(executionEnv), encoding: .utf8) ?? "{}"
            let payload = try await runBlockingString {
                var error: NSError?
                let value = runtime.exec(
                    withRuntimeEnvJSON: sessionKey,
                    command: command,
                    workingDir: workingDir ?? "",
                    timeoutSeconds: timeoutSeconds ?? 10,
                    envJSON: envJSON,
                    capabilitySessionID: sessionID ?? "",
                    callerAgentID: callerAgentID ?? "",
                    error: &error
                )
                if let error { throw error }
                return value
            }
            return try Self.decodeJSON(payload)
        #else
            throw RuntimeError.unavailable("Local VM runtime framework not loaded")
        #endif
    }

    #if canImport(SandboxVM)
        private func ensureRuntime() async throws -> SandboxvmSharedLocalConnectorRuntime {
            let descriptor = try await makeSharedRuntimeDescriptor()
            return try await Self.sharedRuntimeStore.ensureRuntime(using: descriptor)
        }

        private func ensureRuntime(for sessionID: String) async throws -> SandboxvmSharedLocalConnectorRuntime {
            let descriptor = try await makeSharedRuntimeDescriptor()
            let runtime = try await Self.sharedRuntimeStore.ensureRuntime(using: descriptor)
            await Self.sharedRuntimeStore.noteSession(sessionID, scope: descriptor.scope)
            logger.info("Local VM session \(sessionID, privacy: .public) using runtime metadata \(descriptor.scope.metadataDir, privacy: .public)")
            return runtime
        }

        private func requireReviewRuntime(for sessionID: String) async throws -> SandboxvmSharedLocalConnectorRuntime {
            var descriptor = try await makeSharedRuntimeDescriptor()
            if let sessionScope = await Self.sharedRuntimeStore.scopeForSession(sessionID) {
                descriptor = descriptor.withScope(sessionScope)
                logger.info("Local VM review session \(sessionID, privacy: .public) using recorded runtime metadata \(sessionScope.metadataDir, privacy: .public)")
            } else {
                logger.info("Local VM review session \(sessionID, privacy: .public) has no recorded runtime scope")
            }
            if let runtime = try await Self.sharedRuntimeStore.runtimeForReviewIfAvailable(using: descriptor, sessionID: sessionID) {
                return runtime
            }
            throw RuntimeError.unavailable("embedded VM session runtime is not active")
        }

        private func makeSharedRuntimeDescriptor() async throws -> SharedRuntimeDescriptor {
            guard let kernelPath = Bundle.main.path(forResource: "kernel", ofType: "bin") else {
                throw RuntimeError.missingResource("kernel.bin")
            }
            guard let rootfsPath = Bundle.main.path(forResource: "rootfs", ofType: "img") else {
                throw RuntimeError.missingResource("rootfs.img")
            }

            let config = SandboxvmLocalConnectorConfig()
            let configuredMounts = await MainActor.run {
                SettingsManager.shared.localVMMounts
            }
            let effectiveMounts = Self.effectiveMounts(configuredMounts)
            let resolvedRootPath = effectiveMounts.first?.hostPath ?? Self.normalizedPath(NSHomeDirectory())
            let mountsJSON = try Self.mountsJSON(effectiveMounts)
            config.rootPath = resolvedRootPath
            config.mountsJSON = mountsJSON
            config.kernelPath = kernelPath
            config.rootfsPath = rootfsPath
            config.backendURL = "http://127.0.0.1"
            config.backendAPIKey = "local"
            // Keep the runtime read cap above the connector's 10MB read limit so read_stream can transfer larger files.
            config.readMaxBytes = 128 * 1024 * 1024
            config.maxMatches = await MainActor.run { localRuntimeConnectorMaxMatches }
            config.execOutputMaxBytes = 65536

            let runtimePaths = sharedRuntimePaths(rootPath: resolvedRootPath, mountsJSON: mountsJSON)
            config.metadataDir = runtimePaths.metadataDir
            config.rootfsOverlayDir = runtimePaths.rootfsOverlayDir
            return SharedRuntimeDescriptor(
                scope: SharedRuntimeScope(
                    rootPath: resolvedRootPath,
                    mountsJSON: mountsJSON,
                    metadataDir: runtimePaths.metadataDir,
                    rootfsOverlayDir: runtimePaths.rootfsOverlayDir
                ),
                config: config,
                localCallbackBaseURL: "http://127.0.0.1",
                localCallbackAPIKey: "local"
            )
        }

        private static func createRuntime(config: SandboxvmLocalConnectorConfig) async throws -> SandboxvmSharedLocalConnectorRuntime {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var error: NSError?
                    let runtime = SandboxvmNewSharedLocalConnectorRuntime(config, &error)
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let runtime else {
                        continuation.resume(throwing: RuntimeError.invalidResponse("shared local connector runtime was nil"))
                        return
                    }
                    continuation.resume(returning: runtime)
                }
            }
        }

        private static func refreshBackendConfig(_ runtime: SandboxvmSharedLocalConnectorRuntime, descriptor: SharedRuntimeDescriptor) async throws {
            try await runBlocking {
                try runtime.updateBackendConfig(descriptor.localCallbackBaseURL, backendAPIKey: descriptor.localCallbackAPIKey)
            }
        }

        private static func closeSharedRuntime(_ runtime: SandboxvmSharedLocalConnectorRuntime) async throws {
            try await runBlocking {
                try runtime.close()
            }
        }

        private static func healthCheck(_ runtime: SandboxvmSharedLocalConnectorRuntime) async throws {
            try await runBlocking {
                try runtime.healthCheck()
            }
        }
    #endif

    private nonisolated static func decodeJSON<T: Decodable>(_ payload: String) throws -> T {
        try makeDecoder().decode(T.self, from: Data(payload.utf8))
    }

    private func previewCacheURL(sessionID: String, environmentID: String?, path: String) throws -> URL {
        let fileManager = FileManager.default
        let cleanPath = try cleanedRelativeWorkspacePath(path)
        let resolvedEnvironmentID: String = {
            let trimmed = environmentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "local-vm" : trimmed
        }()
        let baseURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".openbridge", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(normalizedSessionKey(sessionID), isDirectory: true)
            .appendingPathComponent("preview-cache", isDirectory: true)
            .appendingPathComponent(resolvedEnvironmentID, isDirectory: true)
        let destination = baseURL.appendingPathComponent(cleanPath, isDirectory: false)

        let normalizedBase = baseURL.standardizedFileURL.path
        let normalizedDestination = destination.standardizedFileURL.path
        guard normalizedDestination == normalizedBase || normalizedDestination.hasPrefix(normalizedBase + "/") else {
            throw RuntimeError.invalidResponse("preview cache path escapes session directory")
        }
        return destination
    }

    private func cleanedRelativeWorkspacePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RuntimeError.invalidResponse("workspace preview path is empty")
        }

        var cleaned = (trimmed as NSString).standardizingPath
        while cleaned.hasPrefix("/") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else {
            throw RuntimeError.invalidResponse("workspace preview path is empty")
        }

        let components = cleaned.split(separator: "/")
        guard components.allSatisfy({ $0 != ".." }) else {
            throw RuntimeError.invalidResponse("workspace preview path escapes session directory")
        }
        return components.joined(separator: "/")
    }

    private func sharedRuntimePaths(rootPath: String, mountsJSON: String = "") -> (metadataDir: String, rootfsOverlayDir: String) {
        Self.sharedRuntimePaths(
            homeDirectory: NSHomeDirectory(),
            rootPath: rootPath,
            mountsJSON: mountsJSON,
            bundlePath: Bundle.main.bundleURL.standardizedFileURL.path
        )
    }

    static func sharedRuntimePaths(homeDirectory: String, rootPath: String = "/", mountsJSON: String = "", bundlePath: String = "OpenBridge.app") -> (metadataDir: String, rootfsOverlayDir: String) {
        let base = homeDirectory + "/.openbridge/shared-\(localVMStateDirectoryName())/" + sharedRuntimeNamespace(rootPath: rootPath, mountsJSON: mountsJSON, bundlePath: bundlePath)
        return (
            metadataDir: base + "/metadata",
            rootfsOverlayDir: base + "/rootfs-overlay"
        )
    }

    private func normalizedSessionKey(_ sessionID: String?) -> String {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "default" : trimmed
    }

    static func localVMStateDirectoryName() -> String {
        #if DEBUG
            return "local-vm-debug"
        #elseif STAGING
            return "local-vm-staging"
        #else
            return "local-vm"
        #endif
    }

    private static func sharedRuntimeNamespace(rootPath: String, mountsJSON: String = "", bundlePath: String) -> String {
        let seed = normalizedPath(rootPath) + "\n" + mountsJSON + "\n" + normalizedPath(bundlePath)
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "/"
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private static func effectiveMounts(_ mounts: [LocalVMMount]) -> [LocalVMMount] {
        let cleaned = mounts
            .map { LocalVMMount(hostPath: $0.hostPath, vmPath: $0.vmPath, readOnly: $0.readOnly, passthrough: $0.passthrough) }
            .filter { !$0.hostPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.hostPath != $1.hostPath { return $0.hostPath < $1.hostPath }
                if $0.vmPath != $1.vmPath { return $0.vmPath < $1.vmPath }
                if $0.readOnly != $1.readOnly { return !$0.readOnly && $1.readOnly }
                return !$0.passthrough && $1.passthrough
            }
        return cleaned.isEmpty ? LocalVMMount.defaultMounts() : cleaned
    }

    private static func mountsJSON(_ mounts: [LocalVMMount]) throws -> String {
        struct Payload: Encodable {
            let hostPath: String
            let vmPath: String
            let readOnly: Bool
            let passthrough: Bool

            private enum CodingKeys: String, CodingKey {
                case hostPath = "host_path"
                case vmPath = "vm_path"
                case readOnly = "read_only"
                case passthrough
            }
        }

        let payload = mounts.map {
            Payload(hostPath: $0.hostPath, vmPath: $0.vmPath, readOnly: $0.readOnly, passthrough: $0.passthrough)
        }
        let data = try JSONEncoder().encode(payload)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func runBlocking<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try body()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        do {
            return try await Self.runBlocking(body)
        } catch {
            #if canImport(SandboxVM)
                if await !Self.sharedRuntimeStore.loadedRuntimeIsHealthy() {
                    readStreamOwners.removeAll()
                    await Self.sharedRuntimeStore.invalidateRuntime()
                }
            #endif
            throw error
        }
    }

    private func runBlockingString(_ body: @escaping @Sendable () throws -> String) async throws -> String {
        try await runBlocking(body)
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: rawValue) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(rawValue)")
        }
        return decoder
    }
}

private extension EmbeddedVMRuntimeBridge {
    struct BridgeWorkspaceState: Decodable, Sendable {
        let sandboxId: String
        let environmentId: String?
        let environmentLabel: String?
        let fileDiff: [BridgeFileDiff]?
    }

    struct BridgeFileDiff: Decodable, Sendable {
        let path: String
        let mode: UInt32
        let isDir: Bool
        let isUpdated: Bool
        let isDeleted: Bool
        let movedFrom: String?
        let timestamp: Date
        let size: Int64
    }

    struct FileReadResult: Decodable {
        let content: String
        let encoding: String
    }

    struct OpenReadStreamResult: Decodable {
        let streamID: String
        let size: Int64

        private enum CodingKeys: String, CodingKey {
            case streamID = "stream_id"
            case size
        }
    }

    struct ReadStreamChunkResult: Decodable {
        let content: String
        let eof: Bool
    }

    struct ListResult: Decodable {
        let entries: [DirectoryEntry]
    }

    struct AcceptChangesPayload: Decodable {
        let acceptedCount: Int?
        let rejectedCount: Int?
        let state: BridgeWorkspaceState?
        let reviewDiff: [BridgeFileDiff]?
        let summary: String?
    }

    struct DiscardAllChangesPayload: Decodable {
        let totalFiles: Int?
        let state: BridgeWorkspaceState?
        let summary: String?
    }

    @MainActor
    static func makeWorkspaceState(from state: BridgeWorkspaceState) -> WorkspaceState {
        WorkspaceState(
            sessionId: state.sandboxId,
            environmentId: state.environmentId ?? "",
            environmentLabel: state.environmentLabel ?? "",
            fileDiff: state.fileDiff?.map(makeFileDiff(from:)) ?? []
        )
    }

    @MainActor
    static func makeFileDiff(from diff: BridgeFileDiff) -> FileDiff {
        FileDiff(
            path: diff.path,
            mode: diff.mode,
            isDir: diff.isDir,
            isUpdated: diff.isUpdated,
            isDeleted: diff.isDeleted,
            movedFrom: diff.movedFrom,
            timestamp: ISO8601DateFormatter().string(from: diff.timestamp),
            size: diff.size
        )
    }
}
