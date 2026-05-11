@testable import OpenBridge
import Foundation
import Testing

struct LocalizedTimeTests {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar.timeZone = utc
        formatter.timeZone = utc

        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }

    private func makeOptions(
        localeId: String = "en_US",
        now: String? = nil,
        relative: RelativeTimeOptions? = nil,
        absolute: AbsoluteTimeOptions = AbsoluteTimeOptions()
    ) -> LocalizedTimeOptions {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let locale = Locale(identifier: localeId)
        let nowDate = now.flatMap { parseDate($0) } ?? Date()
        return LocalizedTimeOptions(locale: locale, calendar: calendar, now: nowDate, relative: relative, absolute: absolute)
    }

    @Test
    func `absolute formatting`() throws {
        let date = try #require(parseDate("2024-10-10 13:30:28"))
        #expect(localizedTime(date, options: makeOptions()) == "Oct 10, 2024 at 1:30:28 PM")
        #expect(localizedTime(date, options: makeOptions(absolute: AbsoluteTimeOptions(accuracy: .minute))) == "Oct 10, 2024 at 1:30 PM")
        #expect(localizedTime(date, options: makeOptions(absolute: AbsoluteTimeOptions(accuracy: .day))) == "Oct 10, 2024")
        #expect(localizedTime(date, options: makeOptions(absolute: AbsoluteTimeOptions(accuracy: .day, noYear: true))) == "Oct 10")
        #expect(localizedTime(date, options: makeOptions(absolute: AbsoluteTimeOptions(accuracy: .year))) == "2024")
        #expect(localizedTime(date, options: makeOptions(absolute: AbsoluteTimeOptions(accuracy: .minute, noDate: true))) == "1:30 PM")
    }

    @Test
    func `relative formatting`() {
        #expect(localizedTime(parseDate("2024-10-10 13:30:28.005"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "1s ago")
        #expect(localizedTime(parseDate("2024-10-10 13:25:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "5m ago")
        #expect(localizedTime(parseDate("2024-10-10 12:59:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "31m ago")
        #expect(localizedTime(parseDate("2024-10-10 12:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "1h ago")
        #expect(localizedTime(parseDate("2024-10-9 13:30:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "yesterday")
        #expect(localizedTime(parseDate("2024-10-9 12:30:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "yesterday")
        #expect(localizedTime(parseDate("2024-10-8 23:59:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "2d ago")
        #expect(localizedTime(parseDate("2024-10-7 23:59:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "3d ago")
        #expect(localizedTime(parseDate("2024-10-4 00:00:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "6d ago")
        #expect(localizedTime(parseDate("2024-10-3 23:59:59"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "last wk.")
        #expect(localizedTime(parseDate("2024-9-29 23:59:59"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "last wk.")
        #expect(localizedTime(parseDate("2024-9-28 23:59:59"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "2w ago")
        #expect(localizedTime(parseDate("2024-9-15 00:00:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "last mo.")
        #expect(localizedTime(parseDate("2024-9-1 00:00:00"), options: makeOptions(now: "2024-9-30 13:30:30", relative: RelativeTimeOptions())) == "4w ago")
        #expect(localizedTime(parseDate("2024-9-10 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "last mo.")
        #expect(localizedTime(parseDate("2023-9-10 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "last yr.")
    }

    @Test
    func `relative accuracy`() {
        #expect(localizedTime(parseDate("2024-10-10 13:30:28.005"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .minute))) == "now")
        #expect(localizedTime(parseDate("2024-10-10 13:25:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .minute))) == "5m ago")
        #expect(localizedTime(parseDate("2024-10-10 12:59:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .hour))) == "now")
        #expect(localizedTime(parseDate("2024-10-10 12:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .day))) == "today")
        #expect(localizedTime(parseDate("2024-10-4 00:00:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .week))) == "last wk.")
        #expect(localizedTime(parseDate("2024-10-9 00:00:00"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .week))) == "this wk.")
        #expect(localizedTime(parseDate("2024-9-1 00:00:00"), options: makeOptions(now: "2024-9-30 13:30:30", relative: RelativeTimeOptions(accuracy: .month))) == "this mo.")
        #expect(localizedTime(parseDate("2024-9-10 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .year))) == "this yr.")
        #expect(localizedTime(parseDate("2023-9-10 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .year))) == "last yr.")
    }

    @Test
    func `relative disable yesterday and tomorrow`() {
        let opts = RelativeTimeOptions(yesterdayAndTomorrow: false)
        #expect(localizedTime(parseDate("2024-10-9 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "1d ago")
        #expect(localizedTime(parseDate("2024-10-11 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "in 1d")
    }

    @Test
    func `relative weekday`() {
        let opts = RelativeTimeOptions(weekday: true, yesterdayAndTomorrow: false)
        #expect(localizedTime(parseDate("2024-10-9 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "Wednesday")
        #expect(localizedTime(parseDate("2024-10-4 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "Friday")
        #expect(localizedTime(parseDate("2024-10-3 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "1w ago")
        #expect(localizedTime(parseDate("2024-10-11 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "Friday")
        #expect(localizedTime(parseDate("2024-10-16 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "Wednesday")
        #expect(localizedTime(parseDate("2024-10-17 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: opts)) == "in 1w")
    }

    @Test
    func `relative absolute mix`() {
        let maxOneDay = RelativeTimeOptions(max: (1, .day))
        #expect(localizedTime(parseDate("2024-10-9 14:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: maxOneDay)) == "23h ago")
        #expect(localizedTime(parseDate("2024-10-9 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: maxOneDay, absolute: AbsoluteTimeOptions(accuracy: .day))) == "Oct 9, 2024")

        let maxTwoDay = RelativeTimeOptions(max: (2, .day))
        #expect(localizedTime(parseDate("2024-10-9 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: maxTwoDay, absolute: AbsoluteTimeOptions(accuracy: .day))) == "yesterday")
        #expect(localizedTime(parseDate("2024-10-8 13:30:30"), options: makeOptions(now: "2024-10-10 13:30:30", relative: maxTwoDay, absolute: AbsoluteTimeOptions(accuracy: .day))) == "Oct 8, 2024")
    }

    @Test
    func `chinese locale`() {
        let localeId = "zh_Hans"
        #expect(localizedTime(parseDate("2024-10-10 13:30:28.005"), options: makeOptions(localeId: localeId)) == "2024年10月10日 13:30:28")
        #expect(localizedTime(parseDate("2024-10-10 13:30:28.005"), options: makeOptions(localeId: localeId, absolute: AbsoluteTimeOptions(accuracy: .day))) == "2024年10月10日")
        #expect(localizedTime(parseDate("2024-10-10 13:30:28.005"), options: makeOptions(localeId: localeId, now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "1秒前")
        #expect(localizedTime(parseDate("2024-10-9 13:30:30"), options: makeOptions(localeId: localeId, now: "2024-10-10 13:30:30", relative: RelativeTimeOptions())) == "昨天")
        #expect(localizedTime(parseDate("2024-10-8 13:30:30"), options: makeOptions(localeId: localeId, now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(weekday: true))) == "星期二")
        #expect(localizedTime(parseDate("2024-10-8 13:30:30"), options: makeOptions(localeId: localeId, now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .week))) == "本周")
        #expect(localizedTime(parseDate("2024-10-8 13:30:30"), options: makeOptions(localeId: localeId, now: "2024-10-10 13:30:30", relative: RelativeTimeOptions(accuracy: .month))) == "本月")
    }

    @Test
    func `invalid time returns empty`() {
        #expect(localizedTime(nil, options: makeOptions()) == "")
    }
}
