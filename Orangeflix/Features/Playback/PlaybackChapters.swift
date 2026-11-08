import Foundation

/// One chapter of an episode: its name and the stretch of the video it covers.
/// The API delivers them with the clip (`chapterSections`), in seconds.
struct PlaybackChapter: Identifiable, Hashable, Sendable, Decodable {
    var id = ""
    var title = ""
    var start: Double = 0
    var end: Double = 0

    /// The chapter the given position lies in.
    static func current(_ chapters: [PlaybackChapter], at seconds: Double) -> PlaybackChapter? {
        chapters.last { seconds >= $0.start }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        title = try c.zero("title")
        // The API sends whole seconds; a fractional value is read as well.
        if let value: JSONValue = try c.optional("start") { start = Self.seconds(value) }
        if let value: JSONValue = try c.optional("end") { end = Self.seconds(value) }
    }

    private static func seconds(_ value: JSONValue) -> Double {
        if case .number(let number) = value { return number }
        if case .string(let text) = value, let number = Double(text) { return number }
        return 0
    }
}

/// The chapters of an episode from the clip answer, which groups them in
/// sections (`chapterSections[].chapters[]`).
struct ClipChapters: Sendable, Hashable, Decodable {
    var sections: [Section] = []

    struct Section: Sendable, Hashable, Decodable {
        var title = ""
        var chapters: [PlaybackChapter] = []

        init(from decoder: any Decoder) throws {
            let c = try decoder.apiContainer()
            title = try c.zero("title")
            chapters = try c.zero("chapters")
        }
    }

    /// All chapters in playing order, with the section titles possible.
    var all: [PlaybackChapter] {
        sections.flatMap(\.chapters)
            .filter { $0.title.isEmpty == false || $0.start > 0 }
            .sorted { $0.start < $1.start }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        sections = try c.zero("chapterSections")
    }
}

/// The parts of the clip page the player needs: the chapters and the picture
/// track of the timeline.
struct ClipPage: Sendable, Hashable, Decodable {
    var chapters: [PlaybackChapter] = []
    var thumbnailTrack = ""

    init(from decoder: any Decoder) throws {
        let clip = try decoder.apiContainer().nested("clip")
        let sections = try clip?.zero("chapterSections") ?? [ClipChapters.Section]()
        chapters = sections.flatMap(\.chapters).sorted { $0.start < $1.start }
        thumbnailTrack = try clip?.zero("vttThumbnails") ?? ""
    }
}
