import Foundation

enum LocalAgentAttachmentFileRefs {
    static func mergedFileRefs(
        primary: SessionHistoryMessage.FileRef?,
        fileRefs: [SessionHistoryMessage.FileRef]?
    ) -> [SessionHistoryMessage.FileRef] {
        deduplicated((fileRefs ?? []) + (primary.map { [$0] } ?? []))
    }

    static func primaryDisplayFileRef(
        primary: SessionHistoryMessage.FileRef?,
        mergedFileRefs: [SessionHistoryMessage.FileRef]
    ) -> SessionHistoryMessage.FileRef? {
        if let primary, !primary.isVFSReference {
            return normalized(primary)
        }

        if let localRef = mergedFileRefs.first(where: { !$0.isVFSReference }) {
            return localRef
        }

        if let primary {
            return normalized(primary)
        }

        return mergedFileRefs.first
    }

    static func browserAttachmentURL(
        existingURL: String?,
        entryKind: String?,
        mergedFileRefs _: [SessionHistoryMessage.FileRef]
    ) -> String? {
        guard normalizedEntryKind(entryKind) != "dir" else {
            return nil
        }

        if let existingURL = normalizedURL(existingURL),
           !isLikelyLocalAttachmentURL(existingURL)
        {
            return existingURL
        }

        return normalizedURL(existingURL)
    }

    static func normalizedLocalRef(
        _ ref: SessionHistoryMessage.FileRef,
        environmentID: String
    ) -> SessionHistoryMessage.FileRef {
        SessionHistoryMessage.FileRef(
            environmentId: environmentID,
            path: ref.path
        )
    }

    static func isRedundantLocalRef(
        _ ref: SessionHistoryMessage.FileRef,
        canonical localRef: SessionHistoryMessage.FileRef
    ) -> Bool {
        guard ref.path == localRef.path else {
            return false
        }

        return normalizedLocalEnvironmentAlias(ref.environmentId) ==
            normalizedLocalEnvironmentAlias(localRef.environmentId)
    }

    private static func deduplicated(
        _ refs: [SessionHistoryMessage.FileRef]
    ) -> [SessionHistoryMessage.FileRef] {
        var seen = Set<String>()
        return refs.compactMap { ref in
            let normalized = normalized(ref)
            guard !normalized.path.isEmpty else {
                return nil
            }

            let key = "\(normalized.environmentId ?? "")\u{1F}|\(normalized.path)"
            guard seen.insert(key).inserted else {
                return nil
            }

            return normalized
        }
    }

    private static func normalized(
        _ ref: SessionHistoryMessage.FileRef
    ) -> SessionHistoryMessage.FileRef {
        let trimmedEnvironmentID = normalized(ref.environmentId)
        return SessionHistoryMessage.FileRef(
            environmentId: trimmedEnvironmentID?.isEmpty == false ? trimmedEnvironmentID : nil,
            path: ref.path.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLocalEnvironmentAlias(_ value: String?) -> String? {
        let normalizedValue = normalized(value)?.lowercased()
        if normalizedValue == "local" || normalizedValue == "local-vm" {
            return "local-vm"
        }
        return normalizedValue
    }

    private static func normalizedURL(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedEntryKind(_ entryKind: String?) -> String {
        let normalized = entryKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized == "dir" ? "dir" : "file"
    }

    private static func isLikelyLocalAttachmentURL(_ value: String) -> Bool {
        value.hasPrefix("file://") ||
            value.hasPrefix("~/") ||
            value.hasPrefix("/Users/") ||
            value.hasPrefix("/private/") ||
            value.hasPrefix("/var/") ||
            value.hasPrefix("/tmp/") ||
            value.hasPrefix("/home/") ||
            value.hasPrefix("/Volumes/") ||
            value.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    private static func isLikelyVFSPath(_ value: String) -> Bool {
        value.hasPrefix("/.agent/") ||
            value.hasPrefix(".agent/")
    }
}

extension SessionHistoryMessage.FileRef {
    var isVFSReference: Bool {
        let environmentID = environmentId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return environmentID == "vfs" || path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/.agent/")
    }
}
