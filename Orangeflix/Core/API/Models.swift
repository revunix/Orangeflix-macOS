import Foundation

/// One entry of a format feed.
struct Episode: Sendable, Hashable, Codable {
    /// The stable id of the episode ("mt420"): the key in the library and the
    /// parameter of the clip request.
    var identifier = ""
    /// The format the episode belongs to.
    var pid = 0
    /// The episode number within the format.
    var number = 0
    /// The episode title ("Folge 420").
    var title = ""
    /// The name of the format ("Die Mediatheke").
    var formatName = ""
    /// The long text of the episode.
    var description = ""
    /// The running time as the API reports it ("00:31:52").
    var duration = ""
    /// The publication date; `nil` when the API did not report one.
    var date: Date?
    /// The thumbnail URL.
    var thumb = ""
    /// The guests of the format.
    var participants: [Participant] = []
    /// The running time in seconds.
    var durationSeconds = 0
    /// The category of the episode.
    var categoryTitle = ""
    /// The share of the episode that was watched.
    var progressPercent = 0
    /// Whether the episode can be downloaded.
    var hasDownload = false
    var bookmarked = false
    /// Whether this account may watch the episode. Premium and VIP episodes
    /// are false without that tier. Unknown sources stay visible.
    var canAccess = true
    /// Exclusive to the premium tier; the API omits these unless asked.
    var isPremium = false
    /// Published early for the higher tier.
    var isEarlyAccess = false
}

/// A guest or host appearing in an episode.
struct Participant: Sendable, Hashable, Codable {
    var id = ""
    var name = ""
    var description = ""
    var image = ""
}

extension Participant {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        name = try c.zero("name")
        description = try c.zero("description")
        image = try c.zero("image")
    }
}

/// One downloadable file of a clip.
struct ClipFile: Sendable, Hashable, Codable {
    /// The download URL. It carries a token and is only valid for a short
    /// time, so it is resolved right before the download.
    var url = ""
    /// The quality description ("HD 1080p", "Audio m4a").
    var desc = ""
    /// The file size in bytes.
    var size: Int64 = 0
    /// The pixel size ("1920x1080").
    var dimensions = ""
    /// The file type ("film", "music"), JSON key "t".
    var kind = ""
    /// The server-side file key for the official download endpoint.
    var file = ""

    enum CodingKeys: String, CodingKey {
        case url, desc, size, dimensions, file
        case kind = "t"
    }

    /// The vertical resolution in pixels, 0 when the dimensions are unknown.
    var height: Int {
        guard let separator = dimensions.firstIndex(of: "x") else { return 0 }
        let value = dimensions[dimensions.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(value) ?? 0
    }
}

extension ClipFile {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        url = try c.zero("url")
        desc = try c.zero("desc")
        size = try c.zero("size")
        dimensions = try c.zero("dimensions")
        kind = try c.zero("t")
        file = try c.zero("file")
    }
}

/// The metadata of one episode of the legacy API together with its files.
struct LegacyClip: Sendable, Hashable {
    var episode: Episode
    /// The available qualities of the episode.
    var files: [ClipFile]
}

/// The status of a format. Unknown values are kept as they are.
struct FormatStatus: RawRepresentable, Sendable, Hashable, Codable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let active = FormatStatus(rawValue: "active")
    static let seasonal = FormatStatus(rawValue: "seasonal")
    static let archived = FormatStatus(rawValue: "archived")

    /// The German label of the status.
    var label: String {
        switch self {
        case .active: return "aktiv"
        case .seasonal: return "saisonal"
        case .archived: return "archiviert"
        default: return rawValue
        }
    }
}

/// One show of the catalog.
struct Format: Sendable, Hashable, Codable {
    /// The numeric id of the format.
    var pid = 0
    /// The short name ("mediatheke").
    var slug = ""
    /// The display name ("Die Mediatheke").
    var title = ""
    /// Active, seasonal or archived.
    var status = FormatStatus(rawValue: "")
    /// The number of episodes of the format.
    var clipCount = 0
    /// The URL of the artwork of the format.
    var logo = ""
    /// The square cover of the format (light and dark variant).
    var cover = ""
    var coverDark = ""
    /// The wide banner of the format.
    var banner = ""
    /// Whether the format is an own production.
    var original = false
    /// The short handle of the format ("PK").
    var handle = ""
    /// The air date of the most recent episode ("2026-10-10").
    var lastEpisode = ""
    /// The date of the most recent episode; lists are sorted by it.
    var lastEpisodeTime: Date?
    /// Whether a new episode came out recently (set by the App layer).
    var newEpisode = false
    /// Whether the user has already been in this format (set by the App layer).
    var opened = false
    /// A one line description of the format.
    var description = ""

    /// The German label of the status.
    var statusLabel: String { status.label }
}
