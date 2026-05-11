@testable import OpenBridge
import Testing

struct ConversationListLiquidVirtualizationTests {
    @Test
    func `layout appends load more footer after content padding`() {
        let layout = ConversationListLiquidVirtualization.buildLayout(
            sections: [
                ConversationListSection(
                    title: "today",
                    items: [
                        session(id: "a", updatedAt: 300),
                        session(id: "b", updatedAt: 200),
                    ]
                ),
            ],
            style: .liquidPopup,
            includesLoadMoreFooter: true,
            loadMoreFooterHeight: 28
        )

        #expect(layout.rows.last?.id == "load-more")
        #expect(layout.contentHeight == layout.rows.last?.maxY)
    }

    @Test
    func `visible rows only cover viewport slice when overscan is disabled`() {
        let layout = ConversationListLiquidVirtualization.buildLayout(
            sections: [
                ConversationListSection(
                    title: "today",
                    items: (0 ..< 10).map { index in
                        session(id: "session-\(index)", updatedAt: Int64(10 - index))
                    }
                ),
            ],
            style: .liquidPopup,
            includesLoadMoreFooter: false,
            loadMoreFooterHeight: 28
        )

        let visibleRows = layout.visibleRows(
            offset: 150,
            visibleHeight: 104,
            overscan: 0
        )

        #expect(visibleRows.count < layout.rows.count)
        #expect(visibleRows.first?.id == "session-3")
        #expect(visibleRows.last?.id == "session-5")
    }

    @Test
    func `section builder groups consecutive sessions by localized day bucket`() throws {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let sessions = [
            session(
                id: "today-1",
                updatedAt: Int64(now.timeIntervalSince1970)
            ),
            session(
                id: "today-2",
                updatedAt: Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
            ),
            session(
                id: "yesterday",
                updatedAt: Int64(yesterday.timeIntervalSince1970)
            ),
        ]

        let sections = ConversationListSectionBuilder.buildSections(from: sessions)

        #expect(sections.count == 2)
        #expect(sections[0].items.map(\.id) == ["today-1", "today-2"])
        #expect(sections[1].items.map(\.id) == ["yesterday"])

        let options = LocalizedTimeOptions(
            relative: RelativeTimeOptions(
                accuracy: .day,
                weekday: true,
                yesterdayAndTomorrow: true
            )
        )
        #expect(sections[0].title == localizedTime(now, options: options))
        #expect(sections[1].title == localizedTime(yesterday, options: options))
    }
}

private func session(id: String, updatedAt: Int64) -> SessionListInfo {
    SessionListInfo(
        id: id,
        title: id,
        messageCount: nil,
        lastMessagePreview: nil,
        createdAt: updatedAt,
        updatedAt: updatedAt
    )
}
