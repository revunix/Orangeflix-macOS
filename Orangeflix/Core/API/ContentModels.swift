import Foundation

// The answers of the v3 content endpoints. Missing or null fields decode to
// the zero value, like the Go client.

/// One episode of the v3 API.
struct Clip: Sendable, Hashable, Decodable {
    struct Images: Sendable, Hashable, Decodable {
        var thumbnail = ""
        var poster = ""
        var thumbnail2x = ""
    }

    struct Progress: Sendable, Hashable, Decodable {
        var percentage = 0
        var lastAccessed = ""
    }

    var id = ""
    var magazineId = 0
    var categoryId = 0
    var categoryTitle = ""
    var title = ""
    var projectTitle = ""
    var description = ""
    var shortDescription = ""
    var duration = ""
    var durationSeconds = 0
    /// The publication time in Unix seconds.
    var time: Int64 = 0
    var timeFormatted = ""
    var seqNr = 0
    var hideSeqNr = false
    var image = ""
    var images = Images()
    var participants: [Participant] = []
    var canAccess = false
    var hasDownload = false
    var isPremium = false
    var isEarlyAccess = false
    var isBookmarked = false
    var progress = Progress()

    /// Converts the clip into an episode.
    var episode: Episode {
        Episode(
            identifier: id, pid: magazineId, number: seqNr, title: title,
            formatName: projectTitle, description: description, duration: duration,
            date: time > 0 ? Date(timeIntervalSince1970: TimeInterval(time)) : nil,
            thumb: image.isEmpty ? images.thumbnail : image,
            participants: participants, durationSeconds: durationSeconds,
            categoryTitle: categoryTitle, progressPercent: progress.percentage,
            hasDownload: hasDownload, bookmarked: isBookmarked, canAccess: canAccess,
            isPremium: isPremium, isEarlyAccess: isEarlyAccess)
    }
}

extension Clip.Images {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        thumbnail = try c.zero("thumbnail")
        poster = try c.zero("poster")
        thumbnail2x = try c.zero("thumbnail2x")
    }
}

extension Clip.Progress {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        percentage = try c.zero("percentage")
        lastAccessed = try c.zero("lastAccessed")
    }
}

extension Clip {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        magazineId = try c.zero("magazineId")
        categoryId = try c.zero("categoryId")
        categoryTitle = try c.zero("categoryTitle")
        title = try c.zero("title")
        projectTitle = try c.zero("projectTitle")
        description = try c.zero("description")
        shortDescription = try c.zero("shortDescription")
        duration = try c.zero("duration")
        durationSeconds = try c.zero("durationSeconds")
        time = try c.zero("time")
        timeFormatted = try c.zero("timeFormatted")
        seqNr = try c.zero("seqNr")
        hideSeqNr = try c.zero("hideSeqNr")
        image = try c.zero("image")
        images = try c.optional("images") ?? Images()
        participants = try c.zero("participants")
        canAccess = try c.zero("canAccess")
        hasDownload = try c.zero("hasDownload")
        isPremium = try c.zero("isPremium")
        isEarlyAccess = try c.zero("isEarlyAccess")
        isBookmarked = try c.zero("isBookmarked")
        progress = try c.optional("progress") ?? Progress()
    }
}

/// One entry of the similar-clips rail.
struct SimilarClip: Sendable, Hashable, Decodable {
    var type = ""
    var id = ""
    var magazineId = 0
    var categoryId = 0
    var time: Int64 = 0
    var seqNr = 0
    var title = ""
    var shortDesc = ""
    var projectTitle = ""
    var image = ""
    var duration = ""
    var durationSeconds = 0
    /// Why the clip was picked ("similarity", …).
    var source = ""

    /// Converts the similar clip into an episode. The date is not taken
    /// over, like in the Go client.
    var episode: Episode {
        Episode(
            identifier: id, pid: magazineId, number: seqNr, title: title,
            formatName: projectTitle, description: shortDesc, duration: duration,
            thumb: image, durationSeconds: durationSeconds)
    }
}

extension SimilarClip {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        type = try c.zero("type")
        id = try c.zero("id")
        magazineId = try c.zero("magazineId")
        categoryId = try c.zero("categoryId")
        time = try c.zero("time")
        seqNr = try c.zero("seqNr")
        title = try c.zero("title")
        shortDesc = try c.zero("shortdesc")
        projectTitle = try c.zero("projectTitle")
        image = try c.zero("image")
        duration = try c.zero("duration")
        durationSeconds = try c.zero("durationSeconds")
        source = try c.zero("source")
    }
}

/// The detailed answer of the clip endpoint.
struct ClipDetail: Sendable, Hashable, Decodable {
    var clip = Clip()
    /// The raw similar part; its shape is not fixed.
    var similar: JSONValue?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        clip = try c.optional("clip") ?? Clip()
        similar = try c.optional("similar")
    }
}

/// Everything the clip page of the API says about one episode, for the page
/// of the episode: the clip, its chapters, words and related clips.
struct EpisodeDetails: Sendable, Hashable, Decodable {
    /// Chapters under one heading ("Kurz kommentiert"); the heading may be
    /// empty.
    struct ChapterSection: Sendable, Hashable {
        var title = ""
        var chapters: [PlaybackChapter] = []
    }

    var clip = Clip()
    var chapterSections: [ChapterSection] = []
    var keywords: [String] = []
    /// The thread of the episode in the forum.
    var commentsURL = ""
    /// The identifier of the next episode of the format; empty for the last.
    var nextIdentifier = ""
    var hasClosedCaptions = false
    var canPurchaseSingle = false
    var priceFormatted = ""
    var similar: [SearchResult] = []

    /// All chapters in the order of time.
    var chapters: [PlaybackChapter] { chapterSections.flatMap(\.chapters) }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        clip = try c.optional("clip") ?? Clip()
        if let page = try c.nested("clip") {
            if var sections = try? page.nestedUnkeyedContainer(forKey: APIKey("chapterSections")) {
                while !sections.isAtEnd {
                    let section = try sections.nestedContainer(keyedBy: APIKey.self)
                    chapterSections.append(ChapterSection(title: try section.zero("title"),
                                                          chapters: try section.zero("chapters")))
                }
            }
            keywords = try page.zero("keywords")
            commentsURL = try page.zero("commentsUrl")
            nextIdentifier = try page.zero("next")
            hasClosedCaptions = try page.zero("hasClosedCaptions")
            canPurchaseSingle = try page.zero("canPurchaseSingle")
            priceFormatted = try page.zero("priceFormatted")
        }
        similar = try c.nested("similar")?.zero("clips") ?? []
    }
}

/// What the playback answer adds to the page of an episode: how often each
/// part was watched and where the account stopped.
struct PlaybackInsights: Sendable, Hashable, Decodable {
    /// The share of viewers at each of equally long parts, 0…1.
    var heatmap: [Double] = []
    var progress = WatchProgress()
    var hasSubtitles = false

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        let clip = try c.nested("clip")
        // An episode without views sends the histogram as an empty list.
        let histogram = (try? clip?.nested("histogram")) ?? nil
        heatmap = (try? histogram?.zero("heatmap") as [Double]?) ?? []
        let subtitles: [Subtitle] = try clip?.zero("subtitles") ?? []
        hasSubtitles = subtitles.contains { !$0.url.isEmpty }
        progress = try c.optional("progress") ?? WatchProgress()
    }
}

/// One format of the live catalog.
struct Magazine: Sendable, Hashable, Decodable {
    struct TimeRange: Sendable, Hashable, Decodable {
        var min: Int64 = 0
        var max: Int64 = 0
    }

    struct Banner: Sendable, Hashable, Decodable {
        var oneX = ""
        var twoX = ""
    }

    struct Artwork: Sendable, Hashable, Decodable {
        var logo = ""
        var logoSquare = ""
        var logoSquareDark = ""
        var logoDark = ""
        var banner = Banner()
    }

    var pid = 0
    var title = ""
    var handle = ""
    var active = false
    var original = false
    var clipCount = 0
    var timeRange = TimeRange()
    var artwork = Artwork()
    /// The tags are strings or objects, depending on the format.
    var tags: [JSONValue] = []
}

extension Magazine.TimeRange {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        min = try c.zero("min")
        max = try c.zero("max")
    }
}

extension Magazine.Banner {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        oneX = try c.zero("1x")
        twoX = try c.zero("2x")
    }
}

extension Magazine.Artwork {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        logo = try c.zero("logo")
        logoSquare = try c.zero("logoSquare")
        logoSquareDark = try c.zero("logoSquareDark")
        logoDark = try c.zero("logoDark")
        banner = try c.optional("banner") ?? Magazine.Banner()
    }
}

extension Magazine {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        pid = try c.zero("pid")
        title = try c.zero("title")
        handle = try c.zero("handle")
        active = try c.zero("active")
        original = try c.zero("original")
        clipCount = try c.zero("clipCount")
        timeRange = try c.optional("timeRange") ?? TimeRange()
        artwork = try c.optional("artwork") ?? Artwork()
        tags = try c.zero("tags")
    }
}

/// Filters the catalog. `nil`/empty means "no filter".
struct MagazineQuery: Sendable, Hashable {
    var active: Bool?
    var ids: [Int] = []
}

/// Describes one page of the feed. Zero values mean "not set"; `count`
/// defaults to fifty.
struct FeedQuery: Sendable, Hashable {
    var offset = 0
    var count = 0
    var before: Int64 = 0
    var main = false
    var withAccess = false
    var includePremium = false
    var includeEarlyAccess = false
    var pinned = false
    var order = ""
    var magazineId = 0
    var categoryId = 0
    var tags = ""
    var tagMode = ""
    var timeFrom: Int64 = 0
    var timeTo: Int64 = 0
}

/// The watch state of a clip, written by the website and the app while a
/// clip plays, so a later run can continue where the playback stopped.
struct WatchProgress: Sendable, Hashable, Decodable {
    var hasStarted = false
    var percentage = 0
    /// The position in seconds.
    var lastPosition = 0
    var lastAccessed = ""
}

extension WatchProgress {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        hasStarted = try c.zero("hasStarted")
        percentage = try c.zero("percentage")
        lastPosition = try c.zero("lastPosition")
        lastAccessed = try c.zero("lastAccessed")
    }
}

/// One entry of the watch progress list.
struct WatchProgressEntry: Sendable, Hashable, Decodable {
    var id = ""
    var percentage = 0
    var hasStarted = false
    var lastAccessed = ""
}

extension WatchProgressEntry {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        percentage = try c.zero("percentage")
        hasStarted = try c.zero("hasStarted")
        lastAccessed = try c.zero("lastAccessed")
    }
}

/// A subtitle track of a clip.
struct Subtitle: Sendable, Hashable, Decodable {
    var lang = ""
    var url = ""
}

extension Subtitle {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        lang = try c.zero("lang")
        url = try c.zero("url")
    }
}

/// The answer of the playback request. The file URLs work without any
/// credentials.
struct Playback: Sendable, Hashable, Decodable {
    var clipId = ""
    var title = ""
    var duration = ""
    var durationSeconds = 0
    var subtitles: [Subtitle] = []
    /// Whether the account may play the stream.
    var access = false
    /// The download files of the delivery network.
    var files: [ClipFile] = []
    /// The stream URLs by type.
    var streams: [String: String] = [:]
    var hlsId = ""
    /// The position the account stopped at.
    var progress = WatchProgress()
    /// The chapters of the episode, filled from the clip page.
    var chapters: [PlaybackChapter] = []
    /// The WebVTT file with the pictures of the timeline, from the clip page.
    var thumbnailTrack = ""
    /// Whether the clip page named the chapters.
    var hasChapterData = false

    /// The URLs of the subtitles, empty ones left out.
    var subtitleURLs: [String] {
        subtitles.map(\.url).filter { !$0.isEmpty }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        let clip = try c.nested("clip")
        clipId = try clip?.zero("id") ?? ""
        title = try clip?.zero("title") ?? ""
        duration = try clip?.zero("duration") ?? ""
        durationSeconds = try clip?.zero("durationSeconds") ?? 0
        subtitles = try clip?.zero("subtitles") ?? []

        let stream = try c.nested("stream")
        access = try stream?.zero("access") ?? false
        hlsId = try stream?.zero("hlsId") ?? ""
        let media = try stream?.nested("media")
        files = try media?.zero("files") ?? []
        streams = try media?.zero("streams") ?? [:]
        progress = try c.optional("progress") ?? WatchProgress()
    }
}

/// One page of the search: the hits and where the next page starts. The
/// `totalHits` of the answer counts places, not episodes, and changes from
/// page to page; the end of the list is the missing `nextOffset`.
struct SearchPage: Sendable, Hashable, Decodable {
    var hits: [SearchResult] = []
    /// The offset of the next page; nil after the last one.
    var nextOffset: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        hits = try c.zero("clips")
        let offset: Int = try c.zero("offset")
        let next: Int = try c.zero("nextOffset")
        // A page without hits has nothing after it either.
        nextOffset = next > offset && !hits.isEmpty ? next : nil
    }
}

/// A place inside an episode the search found: a chapter or a passage of
/// the spoken text. `text` marks the search term with `<em>`.
struct SearchMoment: Sendable, Hashable, Decodable {
    var text = ""
    /// The heading above the chapter ("Kurz kommentiert"); empty for a passage.
    var section = ""
    var startSeconds = 0
    var endSeconds = 0
    /// The start as the API writes it ("6:53:45").
    var startFormatted = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        let highlighted: String = try c.zero("highlighted")
        let snippet: String = try c.zero("snippet")
        let title: String = try c.zero("title")
        text = [highlighted, snippet, title].first { !$0.isEmpty } ?? ""
        section = try c.zero("sectionTitle")
        startSeconds = try c.zero("startSeconds")
        endSeconds = try c.zero("endSeconds")
        startFormatted = try c.zero("startFormatted")
    }
}

/// One hit of the search: an episode with the places that matched.
struct SearchResult: Sendable, Hashable, Decodable {
    /// Where the term was found; the API orders the hits by relevance.
    enum Kind: String, Sendable, Hashable {
        /// Title or description.
        case clip
        /// The name of a chapter.
        case chapter
        /// The spoken text.
        case transcript
    }

    var id = ""
    var kind = Kind.clip
    var magazineId = 0
    var title = ""
    var projectTitle = ""
    var duration = ""
    var durationSeconds = 0
    var seqNr = 0
    var hideSeqNr = false
    /// The publication in Unix seconds; 0 when unknown.
    var time: Int64 = 0
    var image = ""
    var shortDescription = ""
    var description = ""
    /// The description with the term marked (`<em>`), when it matched there.
    var highlightedDescription = ""
    /// The chapter that matched.
    var chapter: SearchMoment?
    /// The passages of the spoken text that matched, in the order of time.
    var passages: [SearchMoment] = []

    var date: Date? { time > 0 ? Date(timeIntervalSince1970: TimeInterval(time)) : nil }

    /// Converts the hit into an episode, like the Go app's search.
    var episode: Episode {
        var episode = Episode()
        episode.identifier = id
        episode.pid = magazineId
        episode.number = hideSeqNr ? 0 : seqNr
        episode.title = title
        episode.formatName = projectTitle
        episode.description = description.isEmpty ? shortDescription : description
        episode.duration = duration
        episode.durationSeconds = durationSeconds
        episode.date = date
        episode.thumb = image
        return episode
    }
}

extension SearchResult {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        kind = Kind(rawValue: try c.zero("type")) ?? .clip
        magazineId = try c.zero("magazineId")
        title = try c.zero("title")
        projectTitle = try c.zero("projectTitle")
        duration = try c.zero("duration")
        durationSeconds = try c.zero("durationSeconds")
        seqNr = try c.zero("seqNr")
        hideSeqNr = try c.zero("hideSeqNr")
        time = try c.zero("time")
        image = try c.zero("image")
        shortDescription = try c.zero("shortdesc")
        description = try c.zero("desc")
        let highlights: [String: String] = (try? c.zero("highlights")) ?? [:]
        highlightedDescription = highlights["desc"] ?? highlights["shortdesc"] ?? ""
        chapter = try c.optional("chapter")
        passages = try c.zero("transcriptMatches")
        if passages.isEmpty, let single: SearchMoment = try c.optional("transcript") {
            passages = [single]
        }
        passages.sort { $0.startSeconds < $1.startSeconds }
    }
}

/// One page of a list.
struct Pagination: Sendable, Hashable, Decodable {
    var offset = 0
    var limit = 0
    var count = 0
    var total = 0
}

extension Pagination {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        offset = try c.zero("offset")
        limit = try c.zero("limit")
        count = try c.zero("count")
        total = try c.zero("total")
    }
}
