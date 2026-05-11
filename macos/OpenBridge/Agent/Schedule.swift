import Combine
import Foundation
import Observation
import OSLog

private let scheduleStoreLogger = Logger(subsystem: "openbridge", category: "ScheduleStore")

nonisolated enum ScheduleRunStatus: String, Codable, Sendable, Equatable {
    case running
    case succeeded
    case failed
}

nonisolated struct ScheduleRunHistoryEntry: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let startedAt: Date
    let finishedAt: Date?
    let status: ScheduleRunStatus
    let error: String
    let executionSessionID: String

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case finishedAt
        case status
        case error
        case executionSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        status = try container.decode(ScheduleRunStatus.self, forKey: .status)
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        executionSessionID = try container.decodeIfPresent(String.self, forKey: .executionSessionID) ?? ""
    }

    init(
        id: String,
        startedAt: Date,
        finishedAt: Date?,
        status: ScheduleRunStatus,
        error: String,
        executionSessionID: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.error = error
        self.executionSessionID = executionSessionID
    }
}

nonisolated struct ScheduleDefinition: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String
    let prompt: String
    let cronExpr: String
    let countLimit: Int
    let dateTimeLimit: Date?
    let timezone: String
    let isPaused: Bool
    let isDeleted: Bool
    let willTriggerAgain: Bool
    let deletedAt: Date?
    let runHistory: [ScheduleRunHistoryEntry]
    let nextRunAt: Date?
    let lastError: String
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case prompt
        case cronExpr
        case countLimit
        case dateTimeLimit
        case timezone
        case isPaused
        case isDeleted
        case willTriggerAgain
        case deletedAt
        case paused
        case runHistory
        case nextRunAt
        case lastError
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        prompt = try container.decode(String.self, forKey: .prompt)
        cronExpr = try container.decode(String.self, forKey: .cronExpr)
        countLimit = try container.decodeIfPresent(Int.self, forKey: .countLimit) ?? 0
        dateTimeLimit = try container.decodeIfPresent(Date.self, forKey: .dateTimeLimit)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused)
            ?? container.decodeIfPresent(Bool.self, forKey: .paused)
            ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        willTriggerAgain = try container.decodeIfPresent(Bool.self, forKey: .willTriggerAgain)
            ?? !isDeleted
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        runHistory = try container.decodeIfPresent([ScheduleRunHistoryEntry].self, forKey: .runHistory) ?? []
        nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(cronExpr, forKey: .cronExpr)
        try container.encode(countLimit, forKey: .countLimit)
        try container.encodeIfPresent(dateTimeLimit, forKey: .dateTimeLimit)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(willTriggerAgain, forKey: .willTriggerAgain)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(runHistory, forKey: .runHistory)
        try container.encodeIfPresent(nextRunAt, forKey: .nextRunAt)
        try container.encode(lastError, forKey: .lastError)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(
        id: String,
        name: String,
        description: String,
        prompt: String,
        cronExpr: String,
        countLimit: Int,
        dateTimeLimit: Date?,
        timezone: String,
        isPaused: Bool,
        isDeleted: Bool,
        willTriggerAgain: Bool,
        deletedAt: Date?,
        runHistory: [ScheduleRunHistoryEntry],
        nextRunAt: Date?,
        lastError: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.prompt = prompt
        self.cronExpr = cronExpr
        self.countLimit = countLimit
        self.dateTimeLimit = dateTimeLimit
        self.timezone = timezone
        self.isPaused = isPaused
        self.isDeleted = isDeleted
        self.willTriggerAgain = willTriggerAgain
        self.deletedAt = deletedAt
        self.runHistory = runHistory
        self.nextRunAt = nextRunAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var lastRunAt: Date? {
        runHistory.last?.startedAt
    }

    var hasError: Bool {
        !lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isRunningNow: Bool {
        runHistory.last?.status == .running
    }

    var displayTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = trimmedPrompt.split(whereSeparator: \.isNewline).first {
            return String(firstLine)
        }
        return String(localized: "Scheduled task")
    }

    var detailText: String {
        if isRunningNow {
            return String(localized: "Running now")
        }
        if hasError {
            return String(localized: "Last error: ") + lastError
        }
        if isPaused {
            return String(localized: "Paused")
        }
        if let nextRunAt {
            return String(localized: "Next run ") + scheduleTimestampText(nextRunAt)
        }
        if lastRunAt != nil {
            return String(localized: "Completed")
        }
        return String(localized: "No future runs")
    }

    var nextSortDate: Date {
        nextRunAt ?? .distantFuture
    }

    var shouldAppearInMenu: Bool {
        !isDeleted && (willTriggerAgain || isRunningNow || lastRunAt != nil)
    }
}

nonisolated struct ScheduleCreateRequest: Codable, Sendable, Equatable {
    let name: String
    let description: String
    let prompt: String
    let cronExpr: String
    let countLimit: Int?
    let dateTimeLimit: Date?
    let timezone: String
}

nonisolated struct ScheduleUpdateRequest: Codable, Sendable, Equatable {
    let name: String?
    let description: String?
    let prompt: String?
    let cronExpr: String?
    let countLimit: Int?
    let dateTimeLimit: Date?
    let timezone: String?
    let clearCountLimit: Bool
    let clearDateTimeLimit: Bool
}

nonisolated struct ScheduleChangeEvent: Sendable, Equatable {
    let type: String
    let schedule: ScheduleDefinition
}

nonisolated struct ScheduleEventSnapshot: Sendable {
    let type: String
    let scheduleID: String
    let scheduleJSON: String
}

@MainActor
@Observable
final class ScheduleStore {
    static let shared = ScheduleStore()

    struct Item: Identifiable, Equatable {
        let id: String
        let scheduleID: String
        let title: String
        let subtitle: String
        let nextRunAt: Date?
        let isRunningNow: Bool
        let hasError: Bool
        let isPaused: Bool
        let willTriggerAgain: Bool
        let createdAt: Date

        init(definition: ScheduleDefinition) {
            id = definition.id
            scheduleID = definition.id
            title = definition.displayTitle
            subtitle = definition.detailText
            nextRunAt = definition.nextRunAt
            isRunningNow = definition.isRunningNow
            hasError = definition.hasError
            isPaused = definition.isPaused
            willTriggerAgain = definition.willTriggerAgain
            createdAt = definition.createdAt
        }
    }

    private(set) var definitions: [ScheduleDefinition] = []
    private(set) var updateTrigger = 0

    @ObservationIgnored
    let didChange = PassthroughSubject<Void, Never>()

    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored
    private var inFlightOperationIDs: Set<String> = []

    var items: [Item] {
        definitions
            .filter(\.shouldAppearInMenu)
            .sorted { $0.nextSortDate < $1.nextSortDate }
            .map(Item.init(definition:))
    }

    var hasSchedules: Bool {
        !items.isEmpty
    }

    private init() {
        setupSubscriptions()
        Task {
            await refresh()
        }
    }

    func pause(scheduleID: String) async throws {
        guard beginOperation(scheduleID) else { return }
        defer { endOperation(scheduleID) }
        try await ScheduleRepository.shared.pause(scheduleID: scheduleID)
        await refresh()
    }

    func resume(scheduleID: String) async throws {
        guard beginOperation(scheduleID) else { return }
        defer { endOperation(scheduleID) }
        try await ScheduleRepository.shared.resume(scheduleID: scheduleID)
        await refresh()
    }

    func delete(scheduleID: String) async throws {
        guard beginOperation(scheduleID) else { return }
        defer { endOperation(scheduleID) }
        scheduleStoreLogger.notice("delete requested scheduleID=\(scheduleID, privacy: .public)")
        try await ScheduleRepository.shared.delete(scheduleID: scheduleID)
        scheduleStoreLogger.notice("delete completed scheduleID=\(scheduleID, privacy: .public)")
        await refresh()
    }

    private func setupSubscriptions() {
        ScheduleRepository.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.apply(event: event)
            }
            .store(in: &cancellables)

        ScheduleRepository.shared.didReset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleRuntimeReset()
            }
            .store(in: &cancellables)
    }

    func refresh() async {
        do {
            definitions = try await ScheduleRepository.shared.list()
            updateTrigger += 1
            didChange.send()
        } catch {
            scheduleStoreLogger.error("reload failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(event: ScheduleChangeEvent) {
        if event.type == "deleted" || event.schedule.isDeleted {
            definitions.removeAll { $0.id == event.schedule.id }
        } else if let index = definitions.firstIndex(where: { $0.id == event.schedule.id }) {
            definitions[index] = event.schedule
        } else {
            definitions.append(event.schedule)
        }
        updateTrigger += 1
        didChange.send()
    }

    private func handleRuntimeReset() {
        definitions = []
        updateTrigger += 1
        didChange.send()
        Task {
            await refresh()
        }
    }

    private func beginOperation(_ scheduleID: String) -> Bool {
        if inFlightOperationIDs.contains(scheduleID) {
            return false
        }
        inFlightOperationIDs.insert(scheduleID)
        return true
    }

    private func endOperation(_ scheduleID: String) {
        inFlightOperationIDs.remove(scheduleID)
    }
}

nonisolated func scheduleTimestampText(_ date: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let timeFormatter = DateFormatter()
    timeFormatter.locale = .current
    timeFormatter.timeStyle = .short
    timeFormatter.dateStyle = .none

    if calendar.isDateInToday(date) {
        return String(localized: "today at ") + timeFormatter.string(from: date)
    }
    if calendar.isDateInTomorrow(date) {
        return String(localized: "tomorrow at ") + timeFormatter.string(from: date)
    }

    let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
    if date < nextWeek {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE h:mm a")
        return formatter.string(from: date)
    }

    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy h:mm a")
    return formatter.string(from: date)
}
