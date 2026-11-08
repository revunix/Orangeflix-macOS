import Foundation
import Testing
@testable import OrangeflixLogic

@Suite("Recents dismissal")
struct RecentsDismissalTests {
    private let removedAt = 1_800_000_000.0

    private func iso(_ seconds: Double) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    @Test("a clip that was never removed shows")
    func notRemoved() {
        #expect(!RecentsDismissal.isHidden(lastAccessed: iso(removedAt), dismissedAt: nil))
    }

    @Test("a removed clip stays hidden, also after the server stamps the reset")
    func stampedByReset() {
        #expect(RecentsDismissal.isHidden(lastAccessed: iso(removedAt - 3600), dismissedAt: removedAt))
        #expect(RecentsDismissal.isHidden(lastAccessed: iso(removedAt + 5), dismissedAt: removedAt))
        #expect(RecentsDismissal.isHidden(lastAccessed: "", dismissedAt: removedAt))
    }

    @Test("a clip watched again later comes back")
    func watchedAgain() {
        #expect(!RecentsDismissal.isHidden(lastAccessed: iso(removedAt + 3600), dismissedAt: removedAt))
    }

    @Test("both date formats of the API are read")
    func dateFormats() {
        #expect(RecentsDismissal.date("2026-11-08T15:20:00.123Z") != nil)
        #expect(RecentsDismissal.date("2026-11-08T15:20:00+01:00") != nil)
        #expect(RecentsDismissal.date("2026-11-08 15:20:00")?.timeIntervalSince1970 == 1_794_151_200)
    }

    @Test("pruning keeps only removals that still hide a listed clip")
    func pruning() {
        let dismissed = ["a": removedAt, "b": removedAt, "gone": removedAt]
        let kept = RecentsDismissal.pruned(dismissed, visibleIn: [
            (id: "a", lastAccessed: iso(removedAt)),
            (id: "b", lastAccessed: iso(removedAt + 86_400)),
        ])
        #expect(kept == ["a": removedAt])
    }
}
