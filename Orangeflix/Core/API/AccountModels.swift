import Foundation

/// The subscription state of the account.
struct AccountSubscription: Sendable, Hashable, Decodable {
    var hasAccess = false
    var lzk: Int64 = 0
    var lifetime = false
    var activeSub = 0
    var captureAmount = 0
    var computedCaptureAmount = 0
    /// The next payment in Unix seconds.
    var nextCapture: Int64 = 0
    var lzkFormatted = ""
    var activeSubDesc = ""
    var captureAmountFormatted = ""
    var tier = 0
    var nextCaptureFormatted = ""
    var accessType = ""
    /// The end of the access in Unix seconds, 0 when unknown or unlimited.
    var expiresAt: Int64 = 0

    /// The end of the access, `nil` when unknown or unlimited.
    var expiryDate: Date? {
        expiresAt > 0 ? Date(timeIntervalSince1970: TimeInterval(expiresAt)) : nil
    }
}

extension AccountSubscription {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        hasAccess = try c.zero("hasAccess")
        lzk = try c.zero("lzk")
        lifetime = try c.zero("lifetime")
        activeSub = try c.zero("activeSub")
        captureAmount = try c.zero("captureAmount")
        computedCaptureAmount = try c.zero("computedCaptureAmount")
        nextCapture = try c.zero("nextCapture")
        lzkFormatted = try c.zero("lzkFormatted")
        activeSubDesc = try c.zero("activeSubDesc")
        captureAmountFormatted = try c.zero("captureAmountFormatted")
        tier = try c.zero("tier")
        nextCaptureFormatted = try c.zero("nextCaptureFormatted")
        accessType = try c.zero("accessType")
        expiresAt = try c.zero("expiresAt")
    }
}

/// The account of the user.
struct AccountProfile: Sendable, Hashable, Decodable {
    var ok = false
    var avatar = ""
    var chatname = ""
    /// The name the account shows.
    var name = ""
    var createdAt: Int64 = 0
    var lastLogin: Int64 = 0
    /// The feed marker; the API sends a number or a string.
    var feedSeenAt: JSONValue?
    var subscription = AccountSubscription()
    var hasTotp = false
    /// The optional personal data the account stored. The server names it
    /// twice: in the state and in the features; both are read.
    var optionalInfo = OptionalInfoStatus()

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        let user = try c.nested("user")
        avatar = try user?.zero("avatar") ?? ""
        chatname = try user?.zero("chatname") ?? ""
        name = try user?.zero("name") ?? ""
        createdAt = try user?.zero("createdAt") ?? 0
        lastLogin = try user?.zero("lastLogin") ?? 0
        feedSeenAt = try user?.optional("feedSeenAt")
        subscription = try c.optional("subscription") ?? AccountSubscription()

        let rawFeatures: JSONValue? = c.tolerant("features")
        hasTotp = rawFeatures?.bool("hasTotp") ?? false

        let rawInfo: JSONValue? = c.tolerant("optionalInfo")
        var state = OptionalInfoStatus(raw: rawInfo)
        if !state.addressCollected { state.addressCollected = rawFeatures?.bool("hasAddress") ?? false }
        if !state.birthdayCollected { state.birthdayCollected = rawFeatures?.bool("hasBirthday") ?? false }
        if !state.abonameCollected { state.abonameCollected = rawFeatures?.bool("hasAboname") ?? false }
        if !state.creditsCollected { state.creditsCollected = rawFeatures?.bool("hasCredits") ?? false }
        optionalInfo = state
    }
}

/// A short-lived JWT for an external service (chat, voting).
struct ServiceToken: Sendable, Hashable, Decodable {
    var ok = false
    var jwt = ""
    /// The decoded claims as the API sends them.
    var claims: JSONValue?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        jwt = try c.zero("jwt")
        claims = try c.optional("jwtd")
    }
}

/// The public project metadata.
struct APIMeta: Sendable, Hashable, Decodable {
    var ok = false
    var totalClipDurations: Int64 = 0

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        totalClipDurations = try c.zero("totalClipDurations")
    }
}

/// The health answer of the API.
struct APIHealth: Sendable, Hashable, Decodable {
    var ok = false
    var version = ""
    var timestamp: Int64 = 0

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        version = try c.zero("version")
        timestamp = try c.zero("timestamp")
    }
}

/// The server time.
struct APIServerTime: Sendable, Hashable, Decodable {
    var ok = false
    var timestamp: Int64 = 0
    var iso = ""
    var formatted = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        timestamp = try c.zero("timestamp")
        iso = try c.zero("iso")
        formatted = try c.zero("formatted")
    }
}

/// A guest or host of a format.
struct HostProfile: Sendable, Hashable, Decodable {
    var id = ""
    var name = ""
    var nameUrl = ""
    var description = ""
    var image = ""
    var social: [String: String] = [:]
    var clip = ""
    var clipCount = 0
}

extension HostProfile {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        name = try c.zero("name")
        nameUrl = try c.zero("nameUrl")
        description = try c.zero("description")
        image = try c.zero("image")
        social = try c.zero("social")
        clip = try c.zero("clip")
        clipCount = try c.zero("clipCount")
    }
}

/// A short video of a host page.
struct HostVideo: Sendable, Hashable, Decodable {
    var index = 0
    var label = ""
    var hls = ""
    var mp4 = ""
    var clipName = ""
}

extension HostVideo {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        index = try c.zero("index")
        label = try c.zero("label")
        hls = try c.zero("hls")
        mp4 = try c.zero("mp4")
        clipName = try c.zero("clipName")
    }
}

/// The page of a guest or host.
struct HostPage: Sendable, Hashable, Decodable {
    var ok = false
    var host = HostProfile()
    var nameUrl = ""
    var headerText = ""
    var headerLink = ""
    var recents: [Clip] = []
    var hasRecents = false
    var pagination = Pagination()
    var videos: [HostVideo] = []
    var magazines: [Magazine] = []

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        host = try c.optional("host") ?? HostProfile()
        nameUrl = try c.zero("nameUrl")
        headerText = try c.zero("headerText")
        headerLink = try c.zero("headerLink")
        recents = try c.zero("recents")
        hasRecents = try c.zero("hasRecents")
        pagination = try c.optional("pagination") ?? Pagination()
        videos = try c.zero("videos")
        magazines = try c.zero("magazines")
    }
}

/// An alert or a promotional campaign.
struct Announcement: Sendable, Hashable, Decodable {
    var type = ""
    var id = ""
    var title = ""
    var bodyMarkdown = ""
    var bodyHtml = ""
    var url = ""
    var external = false
    var expiresAt: Int64 = 0
    var date: Int64 = 0
    var datetime = ""
    var timeDescription = ""
    var shortDescription = ""
    var description = ""
    var magazineId = 0
    var image = ""
    var coverImage = ""
    var label = ""
    var ctaLabel = ""
    var priority = 0
}

extension Announcement {
    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        type = try c.zero("type")
        id = try c.zero("id")
        title = try c.zero("title")
        bodyMarkdown = try c.zero("bodyMarkdown")
        bodyHtml = try c.zero("bodyHtml")
        url = try c.zero("url")
        external = try c.zero("external")
        expiresAt = try c.zero("expiresAt")
        date = try c.zero("date")
        datetime = try c.zero("datetime")
        timeDescription = try c.zero("timeDescription")
        shortDescription = try c.zero("shortDescription")
        description = try c.zero("description")
        magazineId = try c.zero("magazineId")
        image = try c.zero("image")
        coverImage = try c.zero("coverImage")
        label = try c.zero("label")
        ctaLabel = try c.zero("ctaLabel")
        priority = try c.zero("priority")
    }
}
