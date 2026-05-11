//
//  LocalizedTime.swift
//  OpenBridge
//
//  Ported from AFFiNE packages/frontend/i18n/src/utils/time.ts
//

import Foundation

public nonisolated enum TimeUnit: Int, CaseIterable {
    case second = 1
    case minute
    case hour
    case day
    case week
    case month
    case year
}

public nonisolated struct RelativeTimeOptions {
    /// Upper bound for relative rendering; fall back to absolute when exceeded.
    public var max: (Int, TimeUnit)
    /// Smallest unit to display (e.g. .minute hides seconds).
    public var accuracy: TimeUnit
    /// When true, show weekday names for dates within the same week.
    public var weekday: Bool
    /// When true, use "yesterday"/"tomorrow" wording for adjacent days.
    public var yesterdayAndTomorrow: Bool

    public init(
        max: (Int, TimeUnit) = (1000, .year),
        accuracy: TimeUnit = .second,
        weekday: Bool = false,
        yesterdayAndTomorrow: Bool = true
    ) {
        self.max = max
        self.accuracy = accuracy
        self.weekday = weekday
        self.yesterdayAndTomorrow = yesterdayAndTomorrow
    }
}

public nonisolated struct AbsoluteTimeOptions {
    /// Smallest unit to include (e.g. .minute hides seconds).
    public var accuracy: TimeUnit
    /// When true, omit the year portion from output.
    public var noYear: Bool
    /// When true, omit the date portion and only show time.
    public var noDate: Bool

    public init(
        accuracy: TimeUnit = .second,
        noYear: Bool = false,
        noDate: Bool = false
    ) {
        self.accuracy = accuracy
        self.noYear = noYear
        self.noDate = noDate
    }
}

public nonisolated struct LocalizedTimeOptions {
    /// Locale to use for date formatting.
    public var locale: Locale
    /// Calendar to derive components; locale applied to it.
    public var calendar: Calendar
    /// Reference "now" used to compute relative time.
    public var now: Date
    /// Relative formatting rules; nil forces absolute formatting.
    public var relative: RelativeTimeOptions?
    /// Absolute formatting rules used when relative is not applied.
    public var absolute: AbsoluteTimeOptions

    public init(
        locale: Locale = .current,
        calendar: Calendar = .current,
        now: Date = Date(),
        relative: RelativeTimeOptions? = nil,
        absolute: AbsoluteTimeOptions = AbsoluteTimeOptions()
    ) {
        var calendar = calendar
        calendar.locale = locale
        self.locale = locale
        self.calendar = calendar
        self.now = now
        self.relative = relative
        self.absolute = absolute
    }

    mutating func withRelative(_ options: RelativeTimeOptions = .init()) {
        relative = options
    }

    mutating func withAbsolute(_ options: AbsoluteTimeOptions = .init()) {
        absolute = options
    }
}

private nonisolated enum RelativeProcessResult {
    case display(String)
    case stop
    case `continue`
}

/// Swift equivalent of the AFFiNE `localizedTime` helper. Provides relative or absolute,
/// locale-aware time strings with configurable precision.
@discardableResult
// swiftlint:disable:next function_body_length cyclomatic_complexity
public nonisolated func localizedTime(_ time: Date?, options: LocalizedTimeOptions = LocalizedTimeOptions()) -> String {
    guard let time else { return "" }
    let calendar = options.calendar
    let now = options.now

    if let relativeOption = options.relative {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = options.locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = relativeOption.yesterdayAndTomorrow ? .named : .numeric

        func start(of component: Calendar.Component, for date: Date) -> Date {
            calendar.dateInterval(of: component, for: date)?.start ?? date
        }

        func trunc(_ value: Double) -> Int {
            Int(value.rounded(.towardZero))
        }

        func shouldStop(unit: TimeUnit, diff: Double) -> Bool {
            relativeOption.max.1 == unit && abs(diff) >= Double(relativeOption.max.0)
        }

        func processSecond() -> RelativeProcessResult {
            let diffSeconds = time.timeIntervalSince(now)
            if abs(diffSeconds) < 1 {
                return .display(formatter.localizedString(for: now, relativeTo: now))
            }
            if shouldStop(unit: .second, diff: diffSeconds) {
                return .stop
            }
            if abs(diffSeconds) < 60 {
                return .display(formatter.localizedString(from: DateComponents(second: trunc(diffSeconds))))
            }
            return .continue
        }

        func processMinute() -> RelativeProcessResult {
            let diffMinutes = time.timeIntervalSince(now) / 60
            if abs(diffMinutes) < 1 {
                return .display(formatter.localizedString(for: now, relativeTo: now))
            }
            if shouldStop(unit: .minute, diff: diffMinutes) {
                return .stop
            }
            if abs(diffMinutes) < 60 {
                return .display(formatter.localizedString(from: DateComponents(minute: trunc(diffMinutes))))
            }
            return .continue
        }

        func processHour() -> RelativeProcessResult {
            let diffHours = time.timeIntervalSince(now) / 3600
            if abs(diffHours) < 1 {
                return .display(formatter.localizedString(for: now, relativeTo: now))
            }
            if shouldStop(unit: .hour, diff: diffHours) {
                return .stop
            }
            if abs(diffHours) < 24 {
                return .display(formatter.localizedString(from: DateComponents(hour: trunc(diffHours))))
            }
            return .continue
        }

        func processDay() -> RelativeProcessResult {
            let startOfTime = start(of: .day, for: time)
            let startOfNow = start(of: .day, for: now)
            let diffDays = calendar.dateComponents([.day], from: startOfNow, to: startOfTime).day ?? 0
            if abs(diffDays) < 1 {
                return .display(formatter.localizedString(from: DateComponents(day: 0)))
            }
            if shouldStop(unit: .day, diff: Double(diffDays)) {
                return .stop
            }
            if relativeOption.yesterdayAndTomorrow, abs(diffDays) < 2 {
                return .display(formatter.localizedString(from: DateComponents(day: diffDays)))
            } else if relativeOption.weekday, abs(diffDays) < 7 {
                let weekdayFormatter = DateFormatter()
                weekdayFormatter.locale = options.locale
                weekdayFormatter.calendar = calendar
                weekdayFormatter.timeZone = calendar.timeZone
                weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
                return .display(weekdayFormatter.string(from: startOfTime))
            } else if abs(diffDays) < 7 {
                return .display(formatter.localizedString(from: DateComponents(day: diffDays)))
            }
            return .continue
        }

        func processWeek() -> RelativeProcessResult {
            let startOfTime = start(of: .weekOfYear, for: time)
            let startOfNow = start(of: .weekOfYear, for: now)
            let diffWeeks = calendar.dateComponents([.weekOfYear], from: startOfNow, to: startOfTime).weekOfYear ?? 0
            if abs(diffWeeks) < 1 {
                return .display(formatter.localizedString(from: DateComponents(weekOfMonth: 0)))
            }
            if shouldStop(unit: .week, diff: Double(diffWeeks)) {
                return .stop
            }
            let inSameMonth = calendar.isDate(time, equalTo: now, toGranularity: .month)
            if inSameMonth || abs(diffWeeks) < 3 {
                return .display(formatter.localizedString(from: DateComponents(weekOfMonth: diffWeeks)))
            }
            return .continue
        }

        func processMonth() -> RelativeProcessResult {
            let startOfTime = start(of: .month, for: time)
            let startOfNow = start(of: .month, for: now)
            let diffMonths = calendar.dateComponents([.month], from: startOfNow, to: startOfTime).month ?? 0
            if abs(diffMonths) < 1 {
                return .display(formatter.localizedString(from: DateComponents(month: 0)))
            }
            if shouldStop(unit: .month, diff: Double(diffMonths)) {
                return .stop
            }
            if abs(diffMonths) < 12 {
                return .display(formatter.localizedString(from: DateComponents(month: diffMonths)))
            }
            return .continue
        }

        func processYear() -> RelativeProcessResult {
            let startOfTime = start(of: .year, for: time)
            let startOfNow = start(of: .year, for: now)
            let diffYears = calendar.dateComponents([.year], from: startOfNow, to: startOfTime).year ?? 0
            if abs(diffYears) < 1 {
                return .display(formatter.localizedString(from: DateComponents(year: 0)))
            }
            if shouldStop(unit: .year, diff: Double(diffYears)) {
                return .stop
            }
            return .display(formatter.localizedString(from: DateComponents(year: diffYears)))
        }

        let processors: [(TimeUnit, () -> RelativeProcessResult)] = [
            (.second, processSecond),
            (.minute, processMinute),
            (.hour, processHour),
            (.day, processDay),
            (.week, processWeek),
            (.month, processMonth),
            (.year, processYear),
        ]

        var shouldFallbackToAbsolute = false
        for (unit, processor) in processors {
            if unit.rawValue < relativeOption.accuracy.rawValue {
                continue
            }
            let result = processor()
            switch result {
            case let .display(value):
                return value
            case .stop:
                shouldFallbackToAbsolute = true
            case .continue:
                continue
            }
            if shouldFallbackToAbsolute {
                break
            }
        }
    }

    let absolute = options.absolute
    let formatter = DateFormatter()
    formatter.locale = options.locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone

    var templateParts: [String] = []
    if !absolute.noDate {
        if absolute.accuracy.rawValue <= TimeUnit.month.rawValue {
            templateParts.append("MMM")
        }
        if absolute.accuracy.rawValue <= TimeUnit.day.rawValue {
            templateParts.append("d")
        }
        if !absolute.noYear {
            templateParts.append("y")
        }
    }
    if absolute.accuracy.rawValue <= TimeUnit.hour.rawValue {
        templateParts.append("j")
    }
    if absolute.accuracy.rawValue <= TimeUnit.minute.rawValue {
        templateParts.append("m")
    }
    if absolute.accuracy.rawValue <= TimeUnit.second.rawValue {
        templateParts.append("s")
    }

    if let format = DateFormatter.dateFormat(
        fromTemplate: templateParts.joined(separator: " "),
        options: 0,
        locale: options.locale
    ), !format.isEmpty {
        formatter.dateFormat = format
    } else {
        formatter.dateStyle = absolute.noDate ? .none : .medium
        formatter.timeStyle = absolute.accuracy.rawValue <= TimeUnit.hour.rawValue ? .short : .medium
    }

    return formatter.string(from: time)
}
