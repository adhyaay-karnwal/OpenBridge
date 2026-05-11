import Combine
import Foundation
import OSLog

private let localScheduleLogger = Logger(subsystem: "openbridge", category: "ScheduleRepository")

@MainActor
final class ScheduleRepository {
    static let shared = ScheduleRepository()

    let events = PassthroughSubject<ScheduleChangeEvent, Never>()
    let didReset = PassthroughSubject<Void, Never>()

    private let storeURL: URL
    private var schedules: [ScheduleDefinition] = []
    private var runtimeResetCancellable: AnyCancellable?
    private var schedulerTask: Task<Void, Never>?
    private var dispatchingScheduleIDs: Set<String> = []

    private init() {
        storeURL = Constant.applicationLibraryURL
            .appendingPathComponent("Agent", isDirectory: true)
            .appendingPathComponent("schedules.json", isDirectory: false)
        schedules = Self.loadStore(from: storeURL)
        runtimeResetCancellable = AgentSessionManager.shared.runtimeDidReset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.didReset.send(())
            }
        startSchedulerLoop()
    }

    deinit {
        schedulerTask?.cancel()
    }

    func list() async throws -> [ScheduleDefinition] {
        sortedVisibleSchedules()
    }

    @discardableResult
    func create(_ request: ScheduleCreateRequest) async throws -> ScheduleDefinition {
        let now = Date()
        let id = "local-schedule-\(UUID().uuidString)"
        let nextRunAt = LocalCron.nextRun(after: now, cronExpr: request.cronExpr, timezone: request.timezone)
        let schedule = ScheduleDefinition(
            id: id,
            name: request.name,
            description: request.description,
            prompt: request.prompt,
            cronExpr: request.cronExpr,
            countLimit: max(0, request.countLimit ?? 0),
            dateTimeLimit: request.dateTimeLimit,
            timezone: request.timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TimeZone.current.identifier : request.timezone,
            isPaused: false,
            isDeleted: false,
            willTriggerAgain: nextRunAt != nil,
            deletedAt: nil,
            runHistory: [],
            nextRunAt: nextRunAt,
            lastError: "",
            createdAt: now,
            updatedAt: now
        )
        schedules.append(schedule)
        try save()
        events.send(ScheduleChangeEvent(type: "created", schedule: schedule))
        return schedule
    }

    @discardableResult
    func update(scheduleID: String, request: ScheduleUpdateRequest) async throws -> ScheduleDefinition {
        let index = try indexForActiveSchedule(scheduleID)
        let current = schedules[index]
        let now = Date()
        let nextName = request.name ?? current.name
        let nextDescription = request.description ?? current.description
        let nextPrompt = request.prompt ?? current.prompt
        let nextCronExpr = request.cronExpr ?? current.cronExpr
        let nextTimezone = request.timezone ?? current.timezone
        let nextCountLimit = request.clearCountLimit ? 0 : (request.countLimit ?? current.countLimit)
        let nextDateTimeLimit = request.clearDateTimeLimit ? nil : (request.dateTimeLimit ?? current.dateTimeLimit)
        let nextRunAt = current.isPaused ? current.nextRunAt : Self.computeNextRun(
            cronExpr: nextCronExpr,
            timezone: nextTimezone,
            countLimit: nextCountLimit,
            dateTimeLimit: nextDateTimeLimit,
            runHistory: current.runHistory,
            after: now
        )
        let updated = ScheduleDefinition(
            id: current.id,
            name: nextName,
            description: nextDescription,
            prompt: nextPrompt,
            cronExpr: nextCronExpr,
            countLimit: max(0, nextCountLimit),
            dateTimeLimit: nextDateTimeLimit,
            timezone: nextTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TimeZone.current.identifier : nextTimezone,
            isPaused: current.isPaused,
            isDeleted: false,
            willTriggerAgain: nextRunAt != nil,
            deletedAt: nil,
            runHistory: current.runHistory,
            nextRunAt: nextRunAt,
            lastError: current.lastError,
            createdAt: current.createdAt,
            updatedAt: now
        )
        schedules[index] = updated
        try save()
        events.send(ScheduleChangeEvent(type: "updated", schedule: updated))
        return updated
    }

    @discardableResult
    func inspect(scheduleID: String) async throws -> ScheduleDefinition {
        try schedules[indexForActiveSchedule(scheduleID)]
    }

    func pause(scheduleID: String) async throws {
        _ = try mutate(scheduleID: scheduleID, eventType: "updated") { current in
            current.copy(isPaused: true, willTriggerAgain: false, updatedAt: Date())
        }
    }

    func resume(scheduleID: String) async throws {
        let now = Date()
        _ = try mutate(scheduleID: scheduleID, eventType: "updated") { current in
            let nextRunAt = Self.computeNextRun(
                cronExpr: current.cronExpr,
                timezone: current.timezone,
                countLimit: current.countLimit,
                dateTimeLimit: current.dateTimeLimit,
                runHistory: current.runHistory,
                after: now
            )
            return current.copy(
                isPaused: false,
                willTriggerAgain: nextRunAt != nil,
                nextRunAt: nextRunAt,
                updatedAt: now
            )
        }
    }

    func delete(scheduleID: String) async throws {
        let now = Date()
        _ = try mutate(scheduleID: scheduleID, eventType: "deleted") { current in
            current.copy(
                isDeleted: true,
                willTriggerAgain: false,
                deletedAt: now,
                nextRunAt: nil,
                clearNextRunAt: true,
                updatedAt: now
            )
        }
    }

    private func startSchedulerLoop() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.dispatchDueSchedules()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func dispatchDueSchedules() async {
        let now = Date()
        let dueSchedules = schedules.filter { schedule in
            guard !schedule.isPaused,
                  !schedule.isDeleted,
                  let nextRunAt = schedule.nextRunAt,
                  nextRunAt <= now,
                  !dispatchingScheduleIDs.contains(schedule.id)
            else {
                return false
            }
            return true
        }

        for schedule in dueSchedules {
            dispatchingScheduleIDs.insert(schedule.id)
            Task { [weak self] in
                await self?.dispatch(schedule)
            }
        }
    }

    private func dispatch(_ schedule: ScheduleDefinition) async {
        let runID = "local-run-\(UUID().uuidString)"
        let startedAt = Date()
        await MainActor.run {
            _ = try? markRunStarted(scheduleID: schedule.id, runID: runID, startedAt: startedAt)
        }

        do {
            let session = try await AgentSessionManager.shared.createSession(interactionMode: "scheduled")
            session.setLocalTitle(schedule.displayTitle)
            let content = [
                SessionHistoryMessage.Content(
                    type: "text",
                    text: schedule.prompt,
                    url: nil,
                    fileRef: nil,
                    fileRefs: nil,
                    fileName: nil,
                    mimeType: nil,
                    sizeBytes: nil,
                    entryKind: nil
                ),
            ]
            _ = try await session.sendSynchronously(content: content)
            await MainActor.run {
                _ = try? finishRun(
                    scheduleID: schedule.id,
                    runID: runID,
                    status: .succeeded,
                    error: "",
                    executionSessionID: session.sessionID
                )
            }
        } catch {
            await MainActor.run {
                _ = try? finishRun(
                    scheduleID: schedule.id,
                    runID: runID,
                    status: .failed,
                    error: error.localizedDescription,
                    executionSessionID: ""
                )
            }
        }

        dispatchingScheduleIDs.remove(schedule.id)
    }

    @discardableResult
    private func markRunStarted(scheduleID: String, runID: String, startedAt: Date) throws -> ScheduleDefinition {
        try mutate(scheduleID: scheduleID, eventType: "updated") { current in
            current.copy(
                runHistory: current.runHistory + [
                    ScheduleRunHistoryEntry(
                        id: runID,
                        startedAt: startedAt,
                        finishedAt: nil,
                        status: .running,
                        error: "",
                        executionSessionID: ""
                    ),
                ],
                nextRunAt: nil,
                clearNextRunAt: true,
                updatedAt: startedAt
            )
        }
    }

    @discardableResult
    private func finishRun(
        scheduleID: String,
        runID: String,
        status: ScheduleRunStatus,
        error: String,
        executionSessionID: String
    ) throws -> ScheduleDefinition {
        let now = Date()
        return try mutate(scheduleID: scheduleID, eventType: "updated") { current in
            let runHistory = current.runHistory.map { entry in
                guard entry.id == runID else { return entry }
                return ScheduleRunHistoryEntry(
                    id: entry.id,
                    startedAt: entry.startedAt,
                    finishedAt: now,
                    status: status,
                    error: error,
                    executionSessionID: executionSessionID
                )
            }
            let nextRunAt = Self.computeNextRun(
                cronExpr: current.cronExpr,
                timezone: current.timezone,
                countLimit: current.countLimit,
                dateTimeLimit: current.dateTimeLimit,
                runHistory: runHistory,
                after: now
            )
            return current.copy(
                willTriggerAgain: nextRunAt != nil,
                runHistory: runHistory,
                nextRunAt: nextRunAt,
                lastError: status == .failed ? error : "",
                updatedAt: now
            )
        }
    }

    @discardableResult
    private func mutate(
        scheduleID: String,
        eventType: String,
        transform: (ScheduleDefinition) -> ScheduleDefinition
    ) throws -> ScheduleDefinition {
        let index = try indexForSchedule(scheduleID)
        let updated = transform(schedules[index])
        schedules[index] = updated
        try save()
        events.send(ScheduleChangeEvent(type: eventType, schedule: updated))
        return updated
    }

    private func indexForActiveSchedule(_ scheduleID: String) throws -> Int {
        let index = try indexForSchedule(scheduleID)
        if schedules[index].isDeleted {
            throw ScheduleRepositoryError.notFound(scheduleID)
        }
        return index
    }

    private func indexForSchedule(_ scheduleID: String) throws -> Int {
        guard let index = schedules.firstIndex(where: { $0.id == scheduleID }) else {
            throw ScheduleRepositoryError.notFound(scheduleID)
        }
        return index
    }

    private func sortedVisibleSchedules() -> [ScheduleDefinition] {
        schedules
            .filter { !$0.isDeleted }
            .sorted { $0.nextSortDate < $1.nextSortDate }
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schedules)
        try data.write(to: storeURL, options: .atomic)
    }

    private static func loadStore(from url: URL) -> [ScheduleDefinition] {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ScheduleDefinition].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            localScheduleLogger.error("Failed to load local schedules: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func computeNextRun(
        cronExpr: String,
        timezone: String,
        countLimit: Int,
        dateTimeLimit: Date?,
        runHistory: [ScheduleRunHistoryEntry],
        after date: Date
    ) -> Date? {
        if countLimit > 0, runHistory.count(where: { $0.status == .succeeded }) >= countLimit {
            return nil
        }
        guard let nextRun = LocalCron.nextRun(after: date, cronExpr: cronExpr, timezone: timezone) else {
            return nil
        }
        if let dateTimeLimit, nextRun > dateTimeLimit {
            return nil
        }
        return nextRun
    }
}

enum ScheduleRepositoryError: LocalizedError {
    case notFound(String)
    case invalidCron(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(scheduleID):
            "Schedule not found: \(scheduleID)"
        case let .invalidCron(cronExpr):
            "Unsupported cron expression: \(cronExpr)"
        }
    }
}

private extension ScheduleDefinition {
    func copy(
        name: String? = nil,
        description: String? = nil,
        prompt: String? = nil,
        cronExpr: String? = nil,
        countLimit: Int? = nil,
        dateTimeLimit: Date? = nil,
        clearDateTimeLimit: Bool = false,
        timezone: String? = nil,
        isPaused: Bool? = nil,
        isDeleted: Bool? = nil,
        willTriggerAgain: Bool? = nil,
        deletedAt: Date? = nil,
        clearDeletedAt: Bool = false,
        runHistory: [ScheduleRunHistoryEntry]? = nil,
        nextRunAt: Date? = nil,
        clearNextRunAt: Bool = false,
        lastError: String? = nil,
        updatedAt: Date? = nil
    ) -> ScheduleDefinition {
        ScheduleDefinition(
            id: id,
            name: name ?? self.name,
            description: description ?? self.description,
            prompt: prompt ?? self.prompt,
            cronExpr: cronExpr ?? self.cronExpr,
            countLimit: countLimit ?? self.countLimit,
            dateTimeLimit: clearDateTimeLimit ? nil : (dateTimeLimit ?? self.dateTimeLimit),
            timezone: timezone ?? self.timezone,
            isPaused: isPaused ?? self.isPaused,
            isDeleted: isDeleted ?? self.isDeleted,
            willTriggerAgain: willTriggerAgain ?? self.willTriggerAgain,
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt),
            runHistory: runHistory ?? self.runHistory,
            nextRunAt: clearNextRunAt ? nil : (nextRunAt ?? self.nextRunAt),
            lastError: lastError ?? self.lastError,
            createdAt: createdAt,
            updatedAt: updatedAt ?? self.updatedAt
        )
    }
}

private enum LocalCron {
    static func nextRun(after date: Date, cronExpr: String, timezone: String) -> Date? {
        let fields = cronExpr.split(separator: " ").map(String.init)
        guard fields.count == 5,
              let minute = CronField(fields[0], range: 0 ... 59),
              let hour = CronField(fields[1], range: 0 ... 23),
              let dayOfMonth = CronField(fields[2], range: 1 ... 31),
              let month = CronField(fields[3], range: 1 ... 12),
              let dayOfWeek = CronField(fields[4], range: 0 ... 7)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        var candidate = calendar.date(byAdding: .minute, value: 1, to: date) ?? date.addingTimeInterval(60)
        candidate = calendar.dateInterval(of: .minute, for: candidate)?.start ?? candidate

        for _ in 0 ..< 527_040 {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            let cronWeekday = ((components.weekday ?? 1) + 5) % 7
            let weekdayMatches = dayOfWeek.contains(cronWeekday) || (cronWeekday == 0 && dayOfWeek.contains(7))
            if minute.contains(components.minute ?? -1),
               hour.contains(components.hour ?? -1),
               dayOfMonth.contains(components.day ?? -1),
               month.contains(components.month ?? -1),
               weekdayMatches
            {
                return candidate
            }
            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate.addingTimeInterval(60)
        }
        return nil
    }

    private struct CronField {
        private let values: Set<Int>

        init?(_ raw: String, range: ClosedRange<Int>) {
            var parsed = Set<Int>()
            for part in raw.split(separator: ",").map(String.init) {
                guard let values = Self.parsePart(part, range: range) else { return nil }
                parsed.formUnion(values)
            }
            values = parsed
        }

        func contains(_ value: Int) -> Bool {
            values.contains(value)
        }

        private static func parsePart(_ part: String, range: ClosedRange<Int>) -> Set<Int>? {
            let stepParts = part.split(separator: "/", maxSplits: 1).map(String.init)
            guard stepParts.count <= 2 else { return nil }
            let base = stepParts[0]
            let step = stepParts.count == 2 ? Int(stepParts[1]) : 1
            guard let step, step > 0 else { return nil }

            let baseRange: ClosedRange<Int>
            if base == "*" {
                baseRange = range
            } else if base.contains("-") {
                let bounds = base.split(separator: "-", maxSplits: 1).compactMap { Int($0) }
                guard bounds.count == 2,
                      range.contains(bounds[0]),
                      range.contains(bounds[1]),
                      bounds[0] <= bounds[1]
                else {
                    return nil
                }
                baseRange = bounds[0] ... bounds[1]
            } else if let value = Int(base), range.contains(value) {
                baseRange = value ... value
            } else {
                return nil
            }

            return Set(stride(from: baseRange.lowerBound, through: baseRange.upperBound, by: step))
        }
    }
}
