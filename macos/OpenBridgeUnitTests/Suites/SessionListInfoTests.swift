@testable import OpenBridge
import Testing

struct SessionListInfoTests {
    @Test
    func `sorted newest first orders by updatedAt then createdAt then id`() {
        let oldest = SessionListInfo(
            id: "a",
            title: "Oldest",
            messageCount: nil,
            lastMessagePreview: nil,
            createdAt: 100,
            updatedAt: 100
        )
        let newerCreated = SessionListInfo(
            id: "b",
            title: "Newer created",
            messageCount: nil,
            lastMessagePreview: nil,
            createdAt: 200,
            updatedAt: 100
        )
        let newestUpdated = SessionListInfo(
            id: "c",
            title: "Newest updated",
            messageCount: nil,
            lastMessagePreview: nil,
            createdAt: 50,
            updatedAt: 300
        )
        let sameTimestampsHigherID = SessionListInfo(
            id: "z",
            title: "Tie breaker",
            messageCount: nil,
            lastMessagePreview: nil,
            createdAt: 200,
            updatedAt: 100
        )

        let sorted = SessionListInfo.sortedNewestFirst([
            oldest,
            newerCreated,
            newestUpdated,
            sameTimestampsHigherID,
        ])

        #expect(sorted.map(\.id) == ["c", "z", "b", "a"])
    }
}
