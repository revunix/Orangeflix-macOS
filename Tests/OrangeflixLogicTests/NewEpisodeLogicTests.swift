import Foundation
import Testing
@testable import OrangeflixLogic

@Suite("New episode notifications")
struct NewEpisodeLogicTests {
    private func episode(_ id: String, pid: Int, at seconds: Double?, format: String = "Format") -> Episode {
        var episode = Episode()
        episode.identifier = id
        episode.pid = pid
        episode.formatName = format
        episode.date = seconds.map(Date.init(timeIntervalSince1970:))
        return episode
    }

    @Test("a hidden format keeps its choice but is not announced")
    func hiddenFormatsStayQuiet() {
        #expect(NewEpisodeLogic.announced(notified: [1, 2, 3], hidden: [2, 9]) == [1, 3])
        #expect(NewEpisodeLogic.announced(notified: [2], hidden: [2]).isEmpty)
        #expect(NewEpisodeLogic.announced(notified: [], hidden: [2]).isEmpty)
    }

    @Test("the first check announces nothing")
    func firstCheckIsQuiet() {
        let feed = [episode("a", pid: 1, at: 200)]
        #expect(NewEpisodeLogic.fresh(feed, since: nil, formats: [1]).isEmpty)
    }

    @Test("only episodes after the watermark of chosen formats count")
    func filtersByTimeAndFormat() {
        let feed = [
            episode("old", pid: 1, at: 100),
            episode("same", pid: 1, at: 150),
            episode("new", pid: 1, at: 200),
            episode("other", pid: 2, at: 300),
            episode("undated", pid: 1, at: nil),
        ]
        let groups = NewEpisodeLogic.fresh(feed, since: 150, formats: [1])
        #expect(groups.map(\.pid) == [1])
        #expect(groups[0].episodes.map(\.identifier) == ["new"])
    }

    @Test("episodes are grouped by format, newest first")
    func groupsByFormat() {
        let feed = [
            episode("a1", pid: 1, at: 200, format: "A"),
            episode("b1", pid: 2, at: 400, format: "B"),
            episode("a2", pid: 1, at: 300, format: "A"),
            episode("a2", pid: 1, at: 300, format: "A"),
        ]
        let groups = NewEpisodeLogic.fresh(feed, since: 100, formats: [1, 2])
        #expect(groups.map(\.formatName) == ["B", "A"])
        #expect(groups[1].episodes.map(\.identifier) == ["a2", "a1"])
    }
}
