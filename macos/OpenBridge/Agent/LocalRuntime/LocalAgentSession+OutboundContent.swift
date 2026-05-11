import Foundation

extension LocalAgentSession {
    func prepareOutboundContent(_ content: [SessionHistoryMessage.Content]) async throws -> [SessionHistoryMessage.Content] {
        var prepared: [SessionHistoryMessage.Content] = []
        prepared.reserveCapacity(content.count)

        for item in content {
            if item.type == "text" || item.type == "quote" {
                prepared.append(item)
                continue
            }

            let stagedAttachment = try await stageAttachmentContent(item)
            prepared.append(stagedAttachment)
        }

        return prepared
    }

    func makeTransportContent(from content: [SessionHistoryMessage.Content]) -> [SessionHistoryMessage.Content] {
        injectMacOSUserReminder(into: injectPendingSystemReminders(into: serializedQuoteTransportContent(from: content)))
    }

    static func containsMeaningfulOutboundContent(_ content: [SessionHistoryMessage.Content]) -> Bool {
        content.contains { item in
            if item.type == "text" {
                guard let text = item.text else { return false }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    private func injectPendingSystemReminders(into content: [SessionHistoryMessage.Content]) -> [SessionHistoryMessage.Content] {
        var reminderBlocks: [String] = []

        if shouldInjectInitialSystemReminder,
           let reminder = AgentSessionManager.shared.initialSystemReminder?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reminder.isEmpty
        {
            reminderBlocks.append(reminder)
        }

        reminderBlocks.append(contentsOf: pendingLocalContextReminders.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        guard !reminderBlocks.isEmpty else {
            return content
        }

        let reminderPrefix = reminderBlocks.map { reminder in
            """
            <system-reminder>
            \(reminder)
            </system-reminder>
            """
        }.joined(separator: "\n")

        var nextContent = content
        nextContent.insert(
            SessionHistoryMessage.Content(
                type: "text",
                text: reminderPrefix,
                url: nil,
                fileRef: nil,
                fileRefs: nil,
                fileName: nil,
                mimeType: nil,
                sizeBytes: nil,
                entryKind: nil
            ),
            at: 0
        )
        return nextContent
    }

    private func injectMacOSUserReminder(into content: [SessionHistoryMessage.Content]) -> [SessionHistoryMessage.Content] {
        let reminder = Self.macOSUserReminderBlock()
        let insertIndex = if let firstText = content.first?.text,
                             firstText.contains("<system-reminder>")
        {
            1
        } else {
            0
        }

        var nextContent = content
        nextContent.insert(
            SessionHistoryMessage.Content(
                type: "text",
                text: reminder,
                url: nil,
                fileRef: nil,
                fileRefs: nil,
                fileName: nil,
                mimeType: nil,
                sizeBytes: nil,
                entryKind: nil
            ),
            at: min(insertIndex, nextContent.count)
        )
        return nextContent
    }

    private static func macOSUserReminderBlock() -> String {
        let localVMAlias = LocalRuntimeConnector.EnvironmentKind.localVM.connectAlias
        let localMacOSAlias = LocalRuntimeConnector.EnvironmentKind.localMacOS.connectAlias

        return "<user-reminder>This message is sent from the user's computer. When you need a user-visible local file path, place the file in environment \(localVMAlias) (or \(localMacOSAlias) when the VM is unusable). Use an absolute macOS home path from the environment's home=... value, such as <home>/Desktop/result.md or <home>/Downloads/result.md. Use that same absolute path in file tools and shell commands, and report the absolute macOS path back to the user. In \(localVMAlias), keep Desktop, Documents, and Downloads on the absolute macOS home path instead of ~/... or $HOME/....</user-reminder>"
    }

    private func serializedQuoteTransportContent(
        from content: [SessionHistoryMessage.Content]
    ) -> [SessionHistoryMessage.Content] {
        content.compactMap { item in
            guard item.type == "quote" else {
                return item
            }

            let serialized = Self.serializeOutboundContent([item])
            guard !serialized.isEmpty else {
                return nil
            }

            return SessionHistoryMessage.Content(
                type: "text",
                text: serialized,
                url: nil,
                fileRef: nil,
                fileRefs: nil,
                fileName: nil,
                mimeType: nil,
                sizeBytes: nil,
                entryKind: nil
            )
        }
    }

    private func stageAttachmentContent(_ content: SessionHistoryMessage.Content) async throws -> SessionHistoryMessage.Content {
        let mergedRefs = LocalAgentAttachmentFileRefs.mergedFileRefs(
            primary: content.fileRef,
            fileRefs: content.fileRefs
        )
        let sourceRef = mergedRefs.first {
            !$0.isVFSReference && FileManager.default.fileExists(atPath: $0.path)
        }
        let sourceURL = sourceRef.map { URL(fileURLWithPath: $0.path) }
        let resolvedEntryKind = normalizedEntryKind(for: content, localURL: sourceURL)

        if let vfsRef = mergedRefs.first(where: \.isVFSReference),
           !vfsRef.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           resolvedEntryKind != "dir"
        {
            return normalizedPreStagedAttachmentContent(
                from: content,
                mergedRefs: mergedRefs,
                vfsRef: vfsRef,
                entryKind: resolvedEntryKind
            )
        }

        guard let sourceRef else {
            return normalizedAttachmentContent(
                from: content,
                primaryFileRef: LocalAgentAttachmentFileRefs.primaryDisplayFileRef(
                    primary: content.fileRef,
                    mergedFileRefs: mergedRefs
                ),
                fileRefs: mergedRefs,
                sizeBytes: content.sizeBytes,
                entryKind: resolvedEntryKind
            )
        }

        let localURL = URL(fileURLWithPath: sourceRef.path)
        let entryKind = normalizedEntryKind(for: content, localURL: localURL)
        if entryKind == "dir" {
            return normalizedDirectoryAttachmentContent(
                from: content,
                sourceRef: sourceRef,
                mergedRefs: mergedRefs,
                entryKind: entryKind
            )
        }

        return try await uploadedAttachmentContent(
            from: content,
            sourceRef: sourceRef,
            localURL: localURL,
            mergedRefs: mergedRefs,
            entryKind: entryKind
        )
    }

    private func normalizedPreStagedAttachmentContent(
        from content: SessionHistoryMessage.Content,
        mergedRefs: [SessionHistoryMessage.FileRef],
        vfsRef: SessionHistoryMessage.FileRef,
        entryKind: String
    ) -> SessionHistoryMessage.Content {
        let primaryLocalRef = mergedRefs
            .first(where: { !$0.isVFSReference })
            .map { localRef in
                LocalAgentAttachmentFileRefs.normalizedLocalRef(
                    localRef,
                    environmentID: normalizedLocalEnvironmentID(from: localRef.environmentId)
                )
            }
        let normalizedRefs = primaryLocalRef.map { localRef in
            LocalAgentAttachmentFileRefs.mergedFileRefs(
                primary: nil,
                fileRefs:
                [localRef, vfsRef] + mergedRefs.filter { ref in
                    !ref.isVFSReference && !LocalAgentAttachmentFileRefs.isRedundantLocalRef(ref, canonical: localRef)
                }
            )
        } ?? mergedRefs

        return normalizedAttachmentContent(
            from: content,
            primaryFileRef: LocalAgentAttachmentFileRefs.primaryDisplayFileRef(
                primary: primaryLocalRef ?? content.fileRef,
                mergedFileRefs: normalizedRefs
            ),
            url: LocalAgentAttachmentFileRefs.browserAttachmentURL(
                existingURL: content.url,
                entryKind: entryKind,
                mergedFileRefs: normalizedRefs
            ),
            fileRefs: normalizedRefs,
            sizeBytes: content.sizeBytes,
            entryKind: entryKind
        )
    }

    private func normalizedDirectoryAttachmentContent(
        from content: SessionHistoryMessage.Content,
        sourceRef: SessionHistoryMessage.FileRef,
        mergedRefs: [SessionHistoryMessage.FileRef],
        entryKind: String
    ) -> SessionHistoryMessage.Content {
        let localRef = LocalAgentAttachmentFileRefs.normalizedLocalRef(
            sourceRef,
            environmentID: normalizedLocalEnvironmentID(from: sourceRef.environmentId)
        )
        let normalizedRefs = LocalAgentAttachmentFileRefs.mergedFileRefs(
            primary: nil,
            fileRefs:
            [localRef] + mergedRefs.filter {
                !$0.isVFSReference && !LocalAgentAttachmentFileRefs.isRedundantLocalRef($0, canonical: localRef)
            }
        )

        return normalizedAttachmentContent(
            from: content,
            primaryFileRef: localRef,
            fileRefs: normalizedRefs,
            sizeBytes: content.sizeBytes,
            entryKind: entryKind
        )
    }

    private func uploadedAttachmentContent(
        from content: SessionHistoryMessage.Content,
        sourceRef: SessionHistoryMessage.FileRef,
        localURL: URL,
        mergedRefs: [SessionHistoryMessage.FileRef],
        entryKind: String
    ) async throws -> SessionHistoryMessage.Content {
        let fileData = try await Self.readAttachmentData(from: localURL)
        let sizeBytes = content.sizeBytes ?? Int64(fileData.count)

        let localRef = LocalAgentAttachmentFileRefs.normalizedLocalRef(
            sourceRef,
            environmentID: normalizedLocalEnvironmentID(from: sourceRef.environmentId)
        )
        let normalizedRefs = LocalAgentAttachmentFileRefs.mergedFileRefs(
            primary: nil,
            fileRefs:
            [localRef] + mergedRefs.filter {
                !$0.isVFSReference && !LocalAgentAttachmentFileRefs.isRedundantLocalRef($0, canonical: localRef)
            }
        )

        return normalizedAttachmentContent(
            from: content,
            primaryFileRef: localRef,
            url: localURL.path,
            fileRefs: normalizedRefs,
            sizeBytes: sizeBytes,
            entryKind: entryKind
        )
    }

    private nonisolated static func readAttachmentData(from localURL: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: localURL)
        }.value
    }

    private func normalizedAttachmentContent(
        from content: SessionHistoryMessage.Content,
        primaryFileRef: SessionHistoryMessage.FileRef?,
        url: String? = nil,
        fileRefs: [SessionHistoryMessage.FileRef],
        sizeBytes: Int64?,
        entryKind: String
    ) -> SessionHistoryMessage.Content {
        SessionHistoryMessage.Content(
            type: content.type,
            text: content.text,
            url: url,
            fileRef: primaryFileRef,
            fileRefs: fileRefs.isEmpty ? nil : fileRefs,
            fileName: content.fileName,
            mimeType: content.mimeType,
            sizeBytes: sizeBytes,
            entryKind: entryKind,
            quoteRef: content.quoteRef
        )
    }

    private func normalizedLocalEnvironmentID(from environmentID: String?) -> String {
        let trimmed = environmentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Local") != .orderedSame {
            return trimmed
        }

        let workspaceEnvironmentID = workspaceState?.environmentId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return workspaceEnvironmentID.isEmpty ? "local-vm" : workspaceEnvironmentID
    }

    private func normalizedEntryKind(for content: SessionHistoryMessage.Content, localURL: URL?) -> String {
        let explicitKind = content.entryKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if explicitKind == "dir" || explicitKind == "file" {
            return explicitKind
        }
        if let localURL,
           (try? localURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        {
            return "dir"
        }
        return "file"
    }
}
