import Foundation

/// One entry of the calendar.
struct CalendarEntry: Sendable, Hashable, Decodable {
    /// The live part of a calendar entry.
    struct Live: Sendable, Hashable, Decodable {
        var id = ""
        var end: Int64 = 0
        var description = ""
        var hasAudience = false
    }

    /// The event part of a calendar entry.
    struct Event: Sendable, Hashable, Decodable {
        var id = 0
        var soldOut = false
        var hasCost = false
        var description = ""
        var address = ""
        var tickets = ""
        var hasAudience = false
    }

    var id = ""
    var url = ""
    /// The start in Unix seconds.
    var timestamp: Int64 = 0
    var premium = false
    var datetime = ""
    var weekday = ""
    var date = ""
    var time = ""
    var title = ""
    var description = ""
    var pid = 0
    var image = ""
    var imageDark = ""
    var type = ""
    var live: Live?
    var event: Event?
}

extension CalendarEntry.Live {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        end = try c.zero("end")
        description = try c.zero("description")
        hasAudience = try c.zero("hasAudience")
    }
}

extension CalendarEntry.Event {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        soldOut = try c.zero("soldOut")
        hasCost = try c.zero("hasCost")
        description = try c.zero("description")
        address = try c.zero("address")
        tickets = try c.zero("tickets")
        hasAudience = try c.zero("hasAudience")
    }
}

extension CalendarEntry {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        url = try c.zero("url")
        timestamp = try c.zero("timestamp")
        premium = try c.zero("premium")
        datetime = try c.zero("datetime")
        weekday = try c.zero("weekday")
        date = try c.zero("date")
        time = try c.zero("time")
        title = try c.zero("title")
        description = try c.zero("description")
        pid = try c.zero("pid")
        image = try c.zero("image")
        imageDark = try c.zero("imageDark")
        type = try c.zero("type")
        live = try c.optional("live")
        event = try c.optional("event")
    }
}

/// The current live show.
struct LivestreamShow: Sendable, Hashable, Decodable {
    var id = ""
    var pid = 0
    var title = ""
    var description = ""
    var begin: Int64 = 0
    var end: Int64 = 0
    var chat = false
    var isLive = false
}

extension LivestreamShow {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        pid = try c.zero("pid")
        title = try c.zero("title")
        description = try c.zero("description")
        begin = try c.zero("begin")
        end = try c.zero("end")
        chat = try c.zero("chat")
        isLive = try c.zero("isLive")
    }
}

/// A possible replay of the latest show.
struct LivestreamReplay: Sendable, Hashable, Decodable {
    var possible = false
    var id = ""
    var canAccess = false
    var pid = 0
    var projectTitle = ""
    var title = ""
    var description = ""
    var begin: Int64 = 0
    var end: Int64 = 0
    var beginFormatted = ""
    var clipId = ""
    var url: [String: String] = [:]
}

extension LivestreamReplay {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        possible = try c.zero("possible")
        id = try c.zero("id")
        canAccess = try c.zero("canAccess")
        pid = try c.zero("pid")
        projectTitle = try c.zero("projectTitle")
        title = try c.zero("title")
        description = try c.zero("description")
        begin = try c.zero("begin")
        end = try c.zero("end")
        beginFormatted = try c.zero("beginFormatted")
        clipId = try c.zero("clipId")
        url = try c.zero("url")
    }
}

/// The next scheduled show.
struct LivestreamScheduled: Sendable, Hashable, Decodable {
    var id = ""
    var pid = 0
    var title = ""
    var description = ""
    var begin: Int64 = 0
    var end: Int64 = 0
    var beginFormatted = ""
    /// Seconds until the start.
    var startsIn: Int64 = 0
    var chat = false
}

extension LivestreamScheduled {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        pid = try c.zero("pid")
        title = try c.zero("title")
        description = try c.zero("description")
        begin = try c.zero("begin")
        end = try c.zero("end")
        beginFormatted = try c.zero("beginFormatted")
        startsIn = try c.zero("startsIn")
        chat = try c.zero("chat")
    }
}

/// The answer of the live endpoint: the active, replay or upcoming stream.
struct LivestreamInfo: Sendable, Hashable, Decodable {
    var ok = false
    var isLive = false
    var lastWatchedAt: Int64 = 0
    var lastWatchedVia = ""
    var isPending = false
    /// `nil` when the API did not say.
    var canAccess: Bool?
    /// The stream URLs by MIME type.
    var url: [String: String] = [:]
    var replay: LivestreamReplay?
    var show: LivestreamShow?
    var scheduled: LivestreamScheduled?
    var message = ""

    /// Whether the account may watch the active stream.
    var hasAccess: Bool { canAccess == true }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        isLive = try c.zero("isLive")
        lastWatchedAt = try c.zero("lastWatchedAt")
        lastWatchedVia = try c.zero("lastWatchedVia")
        isPending = try c.zero("isPending")
        canAccess = try c.optional("canAccess")
        url = try c.zero("url")
        replay = try c.optional("replay")
        show = try c.optional("show")
        scheduled = try c.optional("scheduled")
        message = try c.zero("message")
    }
}

/// Records a live or replay position.
struct LivestreamProgressRequest: Sendable, Hashable, Encodable {
    enum Mode: String, Sendable, Hashable, Encodable {
        case live, replay
    }

    var mode: Mode = .live
    /// Seconds behind the live edge; left out when 0.
    var behindSec = 0
    /// Unix seconds; left out when 0.
    var watchedAt: Int64 = 0

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: APIKey.self)
        try c.encode(mode, forKey: APIKey("mode"))
        if behindSec != 0 { try c.encode(behindSec, forKey: APIKey("behindSec")) }
        if watchedAt != 0 { try c.encode(watchedAt, forKey: APIKey("watchedAt")) }
    }
}

/// The answer of a live progress ping.
struct LivestreamProgressResponse: Sendable, Hashable, Decodable {
    var ok = false
    var recorded = false
    var watchedAt: Int64 = 0

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        recorded = try c.zero("recorded")
        watchedAt = try c.zero("watchedAt")
    }
}

/// One message of a chat replay.
struct ClipChatMessage: Sendable, Hashable, Decodable {
    var username = ""
    var message = ""
    var time: Int64 = 0
    /// The position in the video in seconds.
    var videoTime: Double = 0
}

extension ClipChatMessage {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        username = try c.zero("username")
        message = try c.zero("message")
        time = try c.zero("time")
        videoTime = try c.zero("videoTime")
    }
}

/// The chat replay of a clip.
struct ClipChatReplay: Sendable, Hashable, Decodable {
    var ok = false
    var messages: [ClipChatMessage] = []
    var rangeStart: Double = 0
    var rangeEnd: Double = 0

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        messages = try c.zero("messages")
        let range = try c.nested("range")
        rangeStart = try range?.zero("start") ?? 0
        rangeEnd = try range?.zero("end") ?? 0
    }
}
