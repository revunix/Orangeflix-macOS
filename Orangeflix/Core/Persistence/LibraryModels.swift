import Foundation

/// Keys of the `settings` table, identical to the Go CLI so a shared
/// library.db keeps its values.
enum LibrarySettingKey {
    /// The remembered login name.
    static let username = "username"
    /// The download quality chosen in the terminal interface.
    static let quality = "quality"
    /// The directory layout chosen in the terminal interface.
    static let layout = "layout"
    /// The theme of the terminal interface ("dark", "light", "auto").
    static let theme = "theme"
    /// The download folder chosen in the terminal interface (a plain path;
    /// the app keeps its own security-scoped bookmark instead).
    static let downloadsDir = "downloads_dir"
}

/// One format of the library.
struct LibraryFormat: Sendable, Hashable, Codable, CustomStringConvertible {
    var pid: Int
    var slug: String
    var title: String
    var status: String
    /// Whether the format is checked and downloaded.
    var enabled: Bool
    /// When the format was added; nil only if the stored stamp is unreadable.
    var addedAt: Date?
    /// The time of the last new-episode check.
    var checkedAt: Date?
    /// The number of new episodes of the last check.
    var newCount: Int
    /// The error of the last check, "" when it succeeded.
    var lastError: String

    /// "Title (#pid)", or "Format pid (#pid)" without title.
    var description: String {
        let name = title.isEmpty ? "Format \(pid)" : title
        return "\(name) (#\(pid))"
    }
}

/// One episode as the API reports it.
struct LibraryEpisodeRef: Sendable, Hashable, Codable {
    var identifier: String
    var number: Int
    var title: String
    /// The release date; nil corresponds to Go's zero time (stored as "").
    var date: Date?

    init(identifier: String, number: Int = 0, title: String = "", date: Date? = nil) {
        self.identifier = identifier
        self.number = number
        self.title = title
        self.date = date
    }
}

/// A stored episode with its history.
struct LibraryEpisode: Sendable, Hashable, Codable {
    var episode: LibraryEpisodeRef
    /// When the episode was first reported; nil only if unreadable.
    var firstSeen: Date?
    /// When the episode was downloaded; nil while it is pending.
    var downloadedAt: Date?
    /// The file the episode was downloaded to.
    var path: String

    var identifier: String { episode.identifier }
    var number: Int { episode.number }
    var title: String { episode.title }
    var date: Date? { episode.date }
}

/// RFC 3339 time stamps exactly as Go writes (`time.RFC3339`, UTC, whole
/// seconds) and reads them (offsets and fractional seconds accepted).
enum LibraryTimestamp {
    private static let plain = Date.ISO8601FormatStyle(timeZone: .gmt)
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)

    static func format(_ date: Date) -> String {
        // Go truncates to whole seconds.
        plain.format(Date(timeIntervalSince1970: (date.timeIntervalSince1970).rounded(.down)))
    }

    static func now() -> String { format(Date()) }

    /// nil for "" or an unreadable value (like Go's parseStamp).
    static func parse(_ value: String) -> Date? {
        if value.isEmpty { return nil }
        if let date = try? plain.parse(value) { return date }
        return try? fractional.parse(value)
    }
}

/// Shortens an error message for the `last_error` column: at most 500 bytes
/// (cut at a character boundary), surrounding white space removed.
func trimLibraryError(_ error: (any Error)?) -> String {
    guard let error else { return "" }
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    var bytes = 0
    var end = message.unicodeScalars.startIndex
    for index in message.unicodeScalars.indices {
        let size = message.unicodeScalars[index].utf8.count
        if bytes + size > 500 { break }
        bytes += size
        end = message.unicodeScalars.index(after: index)
    }
    return String(message.unicodeScalars[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
}
