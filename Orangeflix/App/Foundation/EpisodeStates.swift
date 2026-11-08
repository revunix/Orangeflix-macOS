import Foundation
import Observation

/// Episode state that changed during this session — watch progress from the
/// player, bookmarks toggled anywhere, files downloaded or deleted. Every
/// list merges it over the data it loaded, so a change shows up everywhere
/// at once (the TUI mutates `episodes`, `clipList` and `searchResults` in
/// place for the same reason).
@MainActor @Observable final class EpisodeStates {
    /// Watch progress in percent by episode identifier.
    private(set) var progress: [String: Int] = [:]
    /// Bookmark state by episode identifier.
    private(set) var bookmarked: [String: Bool] = [:]
    /// Downloaded file by episode identifier; `nil` value = deleted.
    private(set) var files: [String: URL?] = [:]

    func setProgress(_ identifier: String, percent: Int) {
        progress[identifier] = max(0, min(100, percent))
    }

    func setBookmarked(_ identifier: String, _ on: Bool) {
        bookmarked[identifier] = on
    }

    func markDownloaded(_ identifier: String, file: URL) {
        files[identifier] = .some(file)
    }

    func clearDownloaded(_ identifier: String) {
        files[identifier] = .some(nil)
    }

    /// The episode with the session's progress and bookmark state applied.
    func apply(_ episode: Episode) -> Episode {
        var episode = episode
        if let percent = progress[episode.identifier] { episode.progressPercent = percent }
        if let on = bookmarked[episode.identifier] { episode.bookmarked = on }
        return episode
    }

    /// The downloaded file: the session's state if it changed, otherwise the
    /// path stored in the library.
    func file(for identifier: String, stored: String?) -> URL? {
        if let changed = files[identifier] { return changed }
        guard let stored, !stored.isEmpty else { return nil }
        return URL(fileURLWithPath: stored)
    }
}
