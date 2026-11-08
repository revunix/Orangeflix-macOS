import Foundation

/// One item of the queue of the player.
struct PlaybackEntry: Identifiable, Hashable, Sendable {
    /// What the entry plays.
    enum Kind: String, Hashable, Sendable {
        /// An episode of the library.
        case episode
        /// The running live stream.
        case live
        /// The replay of the last show.
        case replay
    }

    /// The id of the episode; "live" for the stream.
    var identifier: String
    /// The name that the interface shows.
    var title: String
    /// The line above the title: the format and the number, "Live", "Replay".
    var detail: String = ""
    /// The address of the file or the stream.
    var url: URL
    /// The position the playback starts at, 0 for the beginning.
    var resume: Int = 0
    /// The length of the episode in seconds.
    var durationSeconds: Int = 0
    /// The addresses of the subtitles.
    var subtitleURLs: [URL] = []
    /// The headers the address needs (the legacy API wants the basic auth).
    var headers: [String: String] = [:]
    /// What the entry plays.
    var kind: Kind = .episode
    /// The moment the replay began (the wall clock), nil for the others.
    var start: Date?
    /// The chapters of the episode; empty for live and replays.
    var chapters: [PlaybackChapter] = []
    /// The WebVTT file with the pictures of the timeline.
    var thumbnailTrack: URL?

    var id: String { identifier }
}

/// What the APIs know about the files of an episode (Go `episodeSource`).
struct PlaybackSource: Sendable {
    /// The available qualities.
    var files: [ClipFile]
    /// The addresses of the subtitles.
    var subtitles: [String]
    /// The watch state of the account.
    var progress: WatchProgress
    /// The length returned with the playback source, when known.
    var durationSeconds: Int = 0
    /// The headers the address of the file needs.
    var headers: [String: String]
    /// The chapters from the clip page.
    var chapters: [PlaybackChapter] = []
    /// The picture track of the timeline from the clip page.
    var thumbnailTrack = ""
}

/// The failures of the playback.
enum PlaybackError: LocalizedError, Equatable, Sendable {
    /// No episode was given.
    case noEpisodes
    /// The metadata of an episode could not be read.
    case metadataFailed(String, String)
    /// There is no file for the episode.
    case noFile(String, String)
    /// The address of the file cannot be read.
    case invalidAddress(String)
    /// The stream has no address.
    case noPlayableStream(isReplay: Bool)
    /// The replay has no data.
    case noReplay
    /// The player cannot read the file.
    case notPlayable(String)

    var errorDescription: String? {
        switch self {
        case .noEpisodes:
            "keine Folge ausgewählt"
        case .metadataFailed(let identifier, let reason):
            "die Metadaten von \(identifier) konnten nicht geladen werden: \(reason)"
        case .noFile(let identifier, let reason):
            "für \(identifier) gibt es keine Datei: \(reason)"
        case .invalidAddress(let identifier):
            "ungültige Adresse für \(identifier)"
        case .noPlayableStream(let isReplay):
            isReplay
                ? "Das Replay kann nicht abgespielt werden: es gibt keine Adresse."
                : "Die Sendung kann nicht abgespielt werden: es gibt keine Adresse."
        case .noReplay:
            "keine Replay-Angaben"
        case .notPlayable(let reason):
            "Die Datei kann nicht abgespielt werden: \(reason)"
        }
    }
}
