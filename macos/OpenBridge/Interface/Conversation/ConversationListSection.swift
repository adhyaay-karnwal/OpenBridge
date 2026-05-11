import Foundation

struct ConversationListSection: Identifiable, Sendable {
    let title: String
    let items: [SessionListInfo]

    var id: String {
        "\(title)-\(items.first?.id ?? "empty")"
    }
}

enum ConversationListSectionBuilder {
    static func buildSections(from sessions: [SessionListInfo]) -> [ConversationListSection] {
        let options = LocalizedTimeOptions(
            relative: RelativeTimeOptions(
                accuracy: .day,
                weekday: true,
                yesterdayAndTomorrow: true
            )
        )
        let calendar = options.calendar

        var sections: [ConversationListSection] = []
        var currentDayStart: Date?
        var currentTitle: String?
        var currentItems: [SessionListInfo] = []

        for session in sessions {
            let date = Date(timeIntervalSince1970: TimeInterval(session.updatedAt))
            let dayStart = calendar.startOfDay(for: date)

            if currentDayStart != dayStart {
                if let currentTitle, !currentItems.isEmpty {
                    sections.append(ConversationListSection(title: currentTitle, items: currentItems))
                }
                currentDayStart = dayStart
                currentTitle = localizedTime(date, options: options)
                currentItems = [session]
            } else {
                currentItems.append(session)
            }
        }

        if let currentTitle, !currentItems.isEmpty {
            sections.append(ConversationListSection(title: currentTitle, items: currentItems))
        }

        return sections
    }
}
