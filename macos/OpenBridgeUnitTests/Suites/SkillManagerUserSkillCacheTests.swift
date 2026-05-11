@testable import OpenBridge
import Foundation
import Testing

struct SkillManagerUserSkillCacheTests {
    @Test
    func `should refresh user skills when no prior refresh exists`() {
        #expect(SkillManager.shouldRefreshUserSkills(lastRefreshAt: nil, ttl: 30, now: Date()) == true)
    }

    @Test
    func `should not refresh user skills when cache is still fresh`() {
        let now = Date()
        let lastRefreshAt = now.addingTimeInterval(-10)

        #expect(
            SkillManager.shouldRefreshUserSkills(
                lastRefreshAt: lastRefreshAt,
                ttl: 30,
                now: now
            ) == false
        )
    }

    @Test
    func `should refresh user skills when cache expired or force requested`() {
        let now = Date()
        let lastRefreshAt = now.addingTimeInterval(-31)

        #expect(
            SkillManager.shouldRefreshUserSkills(
                lastRefreshAt: lastRefreshAt,
                ttl: 30,
                now: now
            ) == true
        )
        #expect(
            SkillManager.shouldRefreshUserSkills(
                lastRefreshAt: now,
                ttl: 30,
                force: true,
                now: now
            ) == true
        )
    }

    @Test
    func `failed refresh keeps the previous user skill cache timestamp`() {
        let previous = Date(timeIntervalSince1970: 12)
        let now = Date(timeIntervalSince1970: 34)

        #expect(
            SkillManager.updatedUserSkillRefreshTimestamp(
                previous: previous,
                didRefreshSucceed: false,
                now: now
            ) == previous
        )
        #expect(
            SkillManager.updatedUserSkillRefreshTimestamp(
                previous: previous,
                didRefreshSucceed: true,
                now: now
            ) == now
        )
    }

}
