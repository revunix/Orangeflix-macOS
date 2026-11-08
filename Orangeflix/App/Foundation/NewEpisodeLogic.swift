import Foundation

/// Picks the episodes a new-episode notification announces.
enum NewEpisodeLogic {
    /// The new episodes of one format, newest first.
    struct Group: Equatable {
        let pid: Int
        let formatName: String
        let episodes: [Episode]
    }

    /// The episodes of the chosen formats published after `since`, grouped
    /// by format in the order of their newest episode. Without `since` (the
    /// first check) nothing is new. Episodes without a date never count.
    static func fresh(_ episodes: [Episode], since: Double?, formats: Set<Int>) -> [Group] {
        guard let since else { return [] }
        var seen = Set<String>()
        let new = episodes
            .filter { episode in
                guard formats.contains(episode.pid), let date = episode.date,
                      date.timeIntervalSince1970 > since,
                      seen.insert(episode.identifier).inserted else { return false }
                return true
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        var groups: [Group] = []
        for episode in new {
            if let index = groups.firstIndex(where: { $0.pid == episode.pid }) {
                groups[index] = Group(pid: episode.pid, formatName: groups[index].formatName,
                                      episodes: groups[index].episodes + [episode])
            } else {
                let name = episode.formatName.isEmpty ? "Orangeflix" : episode.formatName
                groups.append(Group(pid: episode.pid, formatName: name, episodes: [episode]))
            }
        }
        return groups
    }
}
