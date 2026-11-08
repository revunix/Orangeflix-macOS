import Foundation

extension Magazine: APIZeroValue {}
extension AccountSubscription: APIZeroValue {}

/// The endpoints of the v3 API the app uses. Every call carries the access
/// token when one is known and renews a rejected token once.
extension OrangeflixAPI {
    // MARK: Account

    /// The account of the user with the state of the subscription.
    func profile() async throws -> AccountProfile {
        try await request(AccountProfile.self, "GET", "user/me")
    }

    /// The subscription status.
    func subscription() async throws -> AccountSubscription {
        try await requestField("subscription", as: AccountSubscription.self, "GET", "user/subscription")
    }

    /// Ends the session of the access token. The local tokens are kept; the
    /// App layer drops them and their stored copy.
    func logout() async throws {
        _ = try await requestData("POST", "auth/logout")
    }

    // MARK: Catalog and feed

    /// The catalog of the formats. Works without a token.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func magazines(_ query: MagazineQuery = MagazineQuery(), refresh: Bool = false) async throws -> [Magazine] {
        var items: [(String, String)] = []
        if let active = query.active { items.append(("active", active ? "true" : "false")) }
        if !query.ids.isEmpty { items.append(("magazineIds", query.ids.map(String.init).joined(separator: ","))) }
        return try await requestField("magazines", as: [Magazine].self, "GET", "content/magazines", query: items,
                                      cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.catalog))
    }

    /// One format of the catalog.
    func magazine(pid: Int) async throws -> Magazine {
        try await requestField("magazine", as: Magazine.self, "GET", "content/magazines/\(pid)")
    }

    /// One page of the episodes; `count` defaults to fifty.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func feed(_ options: FeedQuery, refresh: Bool = false, cacheMaxAge: TimeInterval? = nil) async throws -> [Clip] {
        var items: [(String, String)] = [
            ("count", String(options.count > 0 ? options.count : 50)),
            ("offset", String(options.offset)),
        ]
        if options.before > 0 { items.append(("before", String(options.before))) }
        if options.main { items.append(("main", "true")) }
        if options.withAccess { items.append(("withAccess", "true")) }
        if options.includePremium { items.append(("includePremium", "true")) }
        if options.includeEarlyAccess { items.append(("includeEarlyAccess", "true")) }
        if options.pinned { items.append(("pinned", "true")) }
        if !options.order.isEmpty { items.append(("order", options.order)) }
        if options.magazineId > 0 { items.append(("magazineId", String(options.magazineId))) }
        if options.categoryId > 0 { items.append(("categoryId", String(options.categoryId))) }
        if !options.tags.isEmpty { items.append(("tags", options.tags)) }
        if !options.tagMode.isEmpty { items.append(("tagMode", options.tagMode)) }
        if options.timeFrom > 0 { items.append(("timeFrom", String(options.timeFrom))) }
        if options.timeTo > 0 { items.append(("timeTo", String(options.timeTo))) }
        return try await requestField("clips", as: [Clip].self, "GET", "content/feed", query: items,
                                      cache: refresh ? nil : APICachePolicy(maxAge: cacheMaxAge ?? CacheTTL.episodes))
    }

    /// The details of one clip; `share` is an optional sharing code.
    func clip(_ identifier: String, share: String = "") async throws -> ClipDetail {
        let items: [(String, String)] = share.isEmpty ? [] : [("share", share)]
        return try await request(ClipDetail.self, "GET", "content/clips/" + APIHTTP.pathEscape(identifier), query: items)
    }

    /// The clip page of one episode with everything the page of the episode
    /// shows. Shares its stored answer with `playback(_:)`.
    func episodeDetails(_ identifier: String, refresh: Bool = false) async throws -> EpisodeDetails {
        let data = try await requestData("GET", "content/clips/" + APIHTTP.pathEscape(identifier),
                                         cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.clipPage))
        return try APIJSON.decode(EpisodeDetails.self, from: data)
    }

    /// The heat map of the views and the position of the account, from the
    /// playback answer; the short-lived file URLs in it are not kept.
    func playbackInsights(_ identifier: String) async throws -> PlaybackInsights {
        try await request(PlaybackInsights.self, "GET", "playback/" + APIHTTP.pathEscape(identifier))
    }

    /// Clips related to a clip; `limit` defaults to ten.
    func similarClips(_ identifier: String, limit: Int = 10) async throws -> [SimilarClip] {
        try await requestField("clips", as: [SimilarClip].self, "GET",
                               "content/clips/" + APIHTTP.pathEscape(identifier) + "/similar",
                               query: [("limit", String(limit > 0 ? limit : 10))])
    }

    /// The page of a guest or host; `limit` defaults to fifty.
    func host(_ identifier: String, offset: Int = 0, limit: Int = 50) async throws -> HostPage {
        try await request(HostPage.self, "GET", "content/hosts/" + APIHTTP.pathEscape(identifier),
                          query: [("offset", String(offset)), ("limit", String(limit > 0 ? limit : 50))],
                          cache: APICachePolicy(maxAge: CacheTTL.guestDirectory))
    }

    /// Looks for clips in titles, descriptions, chapters and transcripts;
    /// `magazineId` narrows the search to one format, `personId` to one
    /// guest or host.
    func search(_ text: String, limit: Int = 30, offset: Int = 0, magazineId: Int? = nil,
                personId: String? = nil) async throws -> SearchPage {
        var query = [("q", text), ("limit", String(limit > 0 ? limit : 30)), ("offset", String(offset))]
        if let magazineId { query.append(("magazineId", String(magazineId))) }
        if let personId, !personId.isEmpty { query.append(("personId", personId)) }
        return try await request(SearchPage.self, "GET", "search", query: query)
    }

    // MARK: Playback and progress

    /// The files, subtitles and the watch position of an episode. The clip
    /// page is requested first, like the website does; it carries the
    /// chapters and the picture track of the timeline.
    func playback(_ identifier: String) async throws -> Playback {
        let escaped = APIHTTP.pathEscape(identifier)
        // The clip page carries chapters and the picture track and barely
        // changes; the file URLs of `playback/` are short-lived and stay
        // uncached.
        let detail = try await requestData("GET", "content/clips/" + escaped,
                                           cache: APICachePolicy(maxAge: CacheTTL.clipPage))
        var playback = try await request(Playback.self, "GET", "playback/" + escaped)
        let page = try? APIJSON.decode(ClipPage.self, from: detail)
        if let page {
            playback.chapters = page.chapters
            playback.thumbnailTrack = page.thumbnailTrack
            playback.hasChapterData = true
        }
        return playback
    }

    /// Stores the position the user reached; the API turns it into the
    /// percentage the website shows. Negative values are sent as 0.
    /// Sets the progress as a share (0–100); needs no running time.
    func updateProgress(_ identifier: String, percentage: Int) async throws {
        let body = try APIJSON.encode(["percentage": min(max(percentage, 0), 100)])
        _ = try await requestData("POST", "playback/" + APIHTTP.pathEscape(identifier) + "/progress", body: body)
    }

    func updateProgress(_ identifier: String, seconds: Int) async throws {
        let body = try APIJSON.encode(["time": max(seconds, 0)])
        _ = try await requestData("POST", "playback/" + APIHTTP.pathEscape(identifier) + "/progress", body: body)
    }

    /// The watch progress of all started clips.
    func playbackProgress() async throws -> [WatchProgressEntry] {
        try await requestField("progress", as: [WatchProgressEntry].self, "GET", "playback/progress")
    }

    /// Resolves one download file (`ClipFile.file`) to its short-lived URL.
    func playbackDownloadURL(clipID: String, file: String) async throws -> String {
        if file.isEmpty { throw APIError.invalidRequest("Der Download braucht eine Datei.") }
        let url = try await requestField("url", as: String.self, "GET",
                                         "playback/" + APIHTTP.pathEscape(clipID) + "/download",
                                         query: [("file", file)])
        if url.isEmpty { throw APIError.invalidRequest("Die Download-Antwort enthält keine Adresse.") }
        return url
    }

    // MARK: Lists

    /// The bookmarks of the account; `limit` defaults to fifty.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func bookmarks(limit: Int = 50, offset: Int = 0, refresh: Bool = false) async throws -> [Clip] {
        try await requestField("clips", as: [Clip].self, "GET", "bookmarks",
                               query: [("limit", String(limit > 0 ? limit : 50)), ("offset", String(offset))],
                               cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.bookmarks))
    }

    /// Whether a clip is on the list.
    func bookmarkStatus(_ identifier: String) async throws -> Bool {
        try await requestField("isBookmarked", as: Bool.self, "GET", "bookmarks/" + APIHTTP.pathEscape(identifier))
    }

    /// Checks several clips at once.
    func bookmarkStatuses(_ identifiers: [String]) async throws -> [String: Bool] {
        let body = try APIJSON.encode(["clipIds": identifiers])
        return try await requestField("bookmarks", as: [String: Bool].self, "POST", "bookmarks/batch-check", body: body)
    }

    /// Puts a clip on the list.
    func addBookmark(_ identifier: String) async throws {
        _ = try await requestData("POST", "bookmarks/" + APIHTTP.pathEscape(identifier))
        // The stored lists are one entry short now.
        await invalidateCache("bookmarks")
    }

    /// Removes a clip from the list.
    func removeBookmark(_ identifier: String) async throws {
        _ = try await requestData("DELETE", "bookmarks/" + APIHTTP.pathEscape(identifier))
        await invalidateCache("bookmarks")
    }

    /// The clips the account watched most recently; `limit` defaults to fifty.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func recents(limit: Int = 50, refresh: Bool = false) async throws -> [Clip] {
        try await requestField("clips", as: [Clip].self, "GET", "content/recents",
                               query: [
                                   ("limit", String(limit > 0 ? limit : 50)),
                                   ("includePremium", "true"),
                                   ("includeEarlyAccess", "true"),
                               ],
                               cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.recents))
    }

    // MARK: Calendar, announcements, live

    /// The upcoming calendar entries; `limit` defaults to one hundred.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func calendar(limit: Int = 100, refresh: Bool = false) async throws -> [CalendarEntry] {
        try await requestField("entries", as: [CalendarEntry].self, "GET", "calendar",
                               query: [("limit", String(limit > 0 ? limit : 100))],
                               cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.calendar))
    }

    /// The active alerts and campaigns; `surface` defaults to "overview",
    /// `limit` to ten.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func announcements(surface: String = "overview", limit: Int = 10, refresh: Bool = false) async throws -> [Announcement] {
        try await requestField("announcements", as: [Announcement].self, "GET", "announcements",
                               query: [("surface", surface.isEmpty ? "overview" : surface),
                                       ("limit", String(limit > 0 ? limit : 10))],
                               cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.announcements))
    }

    /// The active, replay or upcoming livestream.
    /// - Parameter refresh: skips the stored copy and asks the API.
    func liveActive(refresh: Bool = false) async throws -> LivestreamInfo {
        try await request(LivestreamInfo.self, "GET", "live/active",
                          cache: refresh ? nil : APICachePolicy(maxAge: CacheTTL.live))
    }

    /// Stores the live or replay position.
    func recordLiveProgress(_ progress: LivestreamProgressRequest) async throws -> LivestreamProgressResponse {
        try await request(LivestreamProgressResponse.self, "POST", "live/progress", body: try APIJSON.encode(progress))
    }

    /// A short-lived chat token.
    func chatToken() async throws -> ServiceToken {
        try await request(ServiceToken.self, "GET", "chat/token")
    }

    /// A short-lived voting token.
    func votingToken() async throws -> ServiceToken {
        try await request(ServiceToken.self, "GET", "voting/token")
    }

    /// The chat replay of a clip between `start` and `end` seconds.
    func chatReplay(clipID: String, start: Double = 0, end: Double) async throws -> ClipChatReplay {
        if end <= 0 { throw APIError.invalidRequest("Der Chat-Mitschnitt braucht ein Ende.") }
        var items: [(String, String)] = [("end", Self.formatSeconds(end))]
        if start > 0 { items.append(("start", Self.formatSeconds(start))) }
        return try await request(ClipChatReplay.self, "GET", "chat/" + APIHTTP.pathEscape(clipID) + "/replay.json", query: items)
    }

    // MARK: Public service endpoints (no token needed)

    /// The public project metadata.
    func meta() async throws -> APIMeta {
        try await request(APIMeta.self, "GET", "meta")
    }

    /// The total length of all episodes in seconds.
    func totalClipDuration() async throws -> Int64 {
        try await requestField("totalClipDurations", as: Int64.self, "GET", "meta/totalClipDurations")
    }

    /// The health of the API.
    func health() async throws -> APIHealth {
        try await request(APIHealth.self, "GET", "health")
    }

    /// The current server time.
    func serverTime() async throws -> APIServerTime {
        try await request(APIServerTime.self, "GET", "time")
    }

    /// Formats seconds like Go's `FormatFloat(v, 'f', -1, 64)`: the shortest
    /// form without exponent ("9", "1.5").
    nonisolated static func formatSeconds(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let text = String(value)
        guard text.contains("e") else { return text }
        return Decimal(value).description
    }
}
