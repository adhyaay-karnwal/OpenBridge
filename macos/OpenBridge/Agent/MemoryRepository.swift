import Combine
import Foundation
import OSLog

private let localMemoryLogger = Logger(subsystem: "openbridge", category: "MemoryRepository")

struct MemoryEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var content: String
    var tags: [String]
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct MemoryCreateRequest: Sendable {
    let content: String
    let tags: [String]
}

struct MemoryUpdateRequest: Sendable {
    let content: String?
    let tags: [String]?
}

struct MemoryChangeEvent: Sendable {
    let type: String
    let memory: MemoryEntry
}

@MainActor
final class MemoryRepository {
    static let shared = MemoryRepository()

    let events = PassthroughSubject<MemoryChangeEvent, Never>()

    private let storeURL: URL
    private var memories: [MemoryEntry] = []

    private init() {
        storeURL = Constant.applicationLibraryURL
            .appendingPathComponent("Agent", isDirectory: true)
            .appendingPathComponent("memories.json", isDirectory: false)
        memories = Self.loadStore(from: storeURL)
    }

    func list(query: String? = nil) async throws -> [MemoryEntry] {
        let active = memories.filter { !$0.isDeleted }
        guard let query = normalized(query), !query.isEmpty else {
            return active.sorted { $0.updatedAt > $1.updatedAt }
        }

        let needle = query.lowercased()
        return active
            .filter { memory in
                memory.content.lowercased().contains(needle) ||
                    memory.tags.contains { $0.lowercased().contains(needle) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create(_ request: MemoryCreateRequest) async throws -> MemoryEntry {
        let content = normalized(request.content) ?? ""
        guard !content.isEmpty else {
            throw RuntimeError(localized: "Memory content cannot be empty")
        }

        let now = Date()
        let memory = MemoryEntry(
            id: "local-memory-\(UUID().uuidString)",
            content: content,
            tags: normalizedTags(request.tags),
            isDeleted: false,
            createdAt: now,
            updatedAt: now
        )
        memories.append(memory)
        try save()
        events.send(MemoryChangeEvent(type: "created", memory: memory))
        return memory
    }

    @discardableResult
    func update(memoryID: String, request: MemoryUpdateRequest) async throws -> MemoryEntry {
        let index = try indexForActiveMemory(memoryID)
        var memory = memories[index]
        if let content = request.content {
            let nextContent = normalized(content) ?? ""
            guard !nextContent.isEmpty else {
                throw RuntimeError(localized: "Memory content cannot be empty")
            }
            memory.content = nextContent
        }
        if let tags = request.tags {
            memory.tags = normalizedTags(tags)
        }
        memory.updatedAt = Date()
        memories[index] = memory
        try save()
        events.send(MemoryChangeEvent(type: "updated", memory: memory))
        return memory
    }

    @discardableResult
    func inspect(memoryID: String) async throws -> MemoryEntry {
        try memories[indexForActiveMemory(memoryID)]
    }

    func delete(memoryID: String) async throws {
        let index = try indexForActiveMemory(memoryID)
        var memory = memories[index]
        memory.isDeleted = true
        memory.updatedAt = Date()
        memories[index] = memory
        try save()
        events.send(MemoryChangeEvent(type: "deleted", memory: memory))
    }

    func systemPromptSection(limit: Int = 30) async -> String {
        let active = await Array((try? list())?.prefix(max(0, limit)) ?? [])
        guard !active.isEmpty else {
            return """
            # Memory

            Use `manage_memory` to save durable user preferences, stable facts, and recurring instructions that should help future conversations. Do not store secrets or one-off task details.
            """
        }

        let rendered = active.map { memory in
            let tags = memory.tags.isEmpty ? "" : " [\(memory.tags.joined(separator: ", "))]"
            return "- \(memory.id)\(tags): \(memory.content)"
        }.joined(separator: "\n")

        return """
        # Memory

        Durable memories stored locally on this Mac:
        \(rendered)

        Use `manage_memory` to add, update, inspect, list, search, or delete durable user preferences and stable facts. Do not store secrets or one-off task details.
        """
    }

    private func indexForActiveMemory(_ memoryID: String) throws -> Int {
        let id = memoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = memories.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
            throw RuntimeError(localized: "Memory not found: \(memoryID)")
        }
        return index
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.localMemory.encode(memories)
        try data.write(to: storeURL, options: .atomic)
    }

    private static func loadStore(from url: URL) -> [MemoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder.localMemory.decode([MemoryEntry].self, from: data)
        } catch {
            localMemoryLogger.error("Failed to load local memories: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

private func normalized(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedTags(_ tags: [String]) -> [String] {
    var seen: Set<String> = []
    return tags.compactMap { tag in
        guard let normalized = normalized(tag) else { return nil }
        let key = normalized.lowercased()
        guard !seen.contains(key) else { return nil }
        seen.insert(key)
        return normalized
    }
}

private extension JSONEncoder {
    static var localMemory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var localMemory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
