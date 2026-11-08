import Foundation

/// The client of the legacy API (basic authentication) and the RSS feeds.
/// The app uses it as the fallback when the v3 API delivers no episodes or
/// no files, and for `toHTTPS`.
struct LegacyAPIClient: Sendable {
    var baseURL: String
    var feedURL: String
    var userAgent: String
    var username: String
    var password: String
    var attempts: Int
    private let http: APIHTTP

    init(
        username: String = "",
        password: String = "",
        baseURL: String = APIDefaults.legacyBaseURL,
        feedURL: String = APIDefaults.feedURL,
        userAgent: String = APIDefaults.userAgent,
        attempts: Int = APIDefaults.legacyAttempts,
        urlSession: URLSession = APIDefaults.urlSession,
        sleep: @escaping @Sendable (Duration) async -> Void = APIDefaults.sleep
    ) {
        self.username = username
        self.password = password
        self.baseURL = baseURL
        self.feedURL = feedURL
        self.userAgent = userAgent
        self.attempts = attempts > 0 ? attempts : APIDefaults.legacyAttempts
        self.http = APIHTTP(session: urlSession, sleep: sleep)
    }

    // MARK: Transport

    /// Performs a GET request and returns the body. Transient failures and
    /// the rate limit are retried; the legacy API reports the rate limit as
    /// the plain text "RATE LIMITED" with status 200.
    func get(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw APIError.invalidURL(address) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        // The credentials travel in the header, never in the URL.
        if !username.isEmpty || !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic " + token, forHTTPHeaderField: "Authorization")
        }
        let policy = APIRetryPolicy(attempts: attempts, retryRateLimit: true,
                                    rateLimited: { APIHTTP.isRateLimited($0) })
        let response = try await http.send(request, policy: policy)
        if response.status == 401 { throw APIError.invalidCredentials }
        if response.status >= 400 {
            throw APIError.http(status: response.status, message: APIHTTP.truncateBody(response.body))
        }
        return response.body
    }

    private func endpoint(_ items: [(String, String)]) -> String {
        let base = baseURL.split(separator: "?", maxSplits: 1).first.map(String.init) ?? baseURL
        return base + "?" + APIHTTP.encodeQuery(items)
    }

    // MARK: Feed

    /// One page of the episode list of a format. The API expects the format
    /// id in brackets: `from=[23]`.
    func feed(pid: Int, page: Int) async throws -> [Episode] {
        let data = try await get(endpoint([("action", "getFeed"), ("from", "[\(pid)]"), ("page", String(page))]))
        let answer = try APIJSON.decode(LegacyFeedAnswer.self, from: data)
        return answer.eps.compactMap { item in
            var episode = item.episode
            if episode.identifier.isEmpty { return nil }
            if episode.number == 0 { episode.number = Self.numberFromIdentifier(episode.identifier) }
            return episode
        }
    }

    /// Every episode of a format over the JSON feed, oldest first. Pages are
    /// read until three empty pages in a row or a page without new episodes
    /// (the API repeats the last page); at most 200 pages.
    func episodes(pid: Int) async throws -> [Episode] {
        var seen = Set<String>()
        var all: [Episode] = []
        var emptyPages = 0
        for page in 1...200 {
            let episodes = try await feed(pid: pid, page: page)
            if episodes.isEmpty {
                emptyPages += 1
                if emptyPages >= 3 { break }
                continue
            }
            emptyPages = 0
            var added = 0
            for episode in episodes where seen.insert(episode.identifier).inserted {
                all.append(episode)
                added += 1
            }
            if added == 0 { break }
        }
        return Self.sortedByNumber(all)
    }

    // MARK: Clip

    /// The metadata and the download files of one episode. The files need
    /// the basic-auth credentials of this client.
    func clip(_ identifier: String) async throws -> LegacyClip {
        let data = try await get(endpoint([("action", "getClip"), ("identifier", identifier)]))
        let answer = try APIJSON.decode(LegacyClipAnswer.self, from: data)
        var episode = answer.item.episode
        // The clip answer only knows the thumbnail field.
        episode.thumb = answer.item.thumbnail
        if episode.number == 0 { episode.number = Self.numberFromIdentifier(episode.identifier) }
        let files = answer.files.filter { !$0.url.isEmpty }
        if files.isEmpty { throw APIError.noFiles(identifier) }
        return LegacyClip(episode: episode, files: files)
    }

    // MARK: URLs

    /// Normalises an API supplied URL to HTTPS: protocol-relative and
    /// host-less paths are resolved against the API host, plain HTTP is
    /// upgraded, every other scheme is rejected.
    func toHTTPS(_ raw: String) throws -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { throw APIError.invalidURL("leere Adresse") }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/") {
            guard let host = hostOfBaseURL, !host.isEmpty else {
                throw APIError.invalidURL("die relative Adresse \(raw) lässt sich nicht auflösen")
            }
            value = "https://" + host + value
        }
        guard var components = URLComponents(string: value) else {
            throw APIError.invalidURL(raw)
        }
        let scheme = components.scheme?.lowercased()
        if scheme == "http" {
            components.scheme = "https"
            if components.port == 80 { components.port = nil }
        } else if scheme == "https" {
            components.scheme = "https"
        } else {
            throw APIError.invalidURL("nur HTTPS ist erlaubt: \(raw)")
        }
        guard let result = components.string else { throw APIError.invalidURL(raw) }
        return result
    }

    /// The host (with port) of the API base URL.
    private var hostOfBaseURL: String? {
        guard let components = URLComponents(string: baseURL), let host = components.host else { return nil }
        if let port = components.port { return "\(host):\(port)" }
        return host
    }

    // MARK: Helpers

    /// The trailing number of an identifier such as "mt420"; 0 without one.
    static func numberFromIdentifier(_ identifier: String) -> Int {
        let digits = identifier.utf8.reversed().prefix { $0 >= 48 && $0 <= 57 }
        if digits.isEmpty { return 0 }
        return Int(String(decoding: digits.reversed(), as: UTF8.self)) ?? 0
    }

    /// Sorts episodes by their number, oldest first; equal numbers keep
    /// their order.
    static func sortedByNumber(_ episodes: [Episode]) -> [Episode] {
        episodes.enumerated()
            .sorted { $0.element.number == $1.element.number ? $0.offset < $1.offset : $0.element.number < $1.element.number }
            .map(\.element)
    }
}

// MARK: Legacy answers

/// One episode of the legacy feed and clip answers.
private struct LegacyEpisodeItem: Decodable {
    let episode: Episode
    /// The "thumbnail" field alone.
    let thumbnail: String

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        let thumbnail: String = try c.zero("thumbnail")
        let img: String = try c.zero("img")
        let date: Int64 = try c.zero("date")
        episode = Episode(
            identifier: try c.zero("identifier"),
            pid: try c.zero("pid"),
            number: try c.zero("enum"),
            title: try c.zero("title"),
            formatName: try c.zero("pdesc"),
            description: try c.zero("desc"),
            duration: try c.zero("duration"),
            // The legacy API always sets the date, 0 is the epoch.
            date: Date(timeIntervalSince1970: TimeInterval(date)),
            thumb: thumbnail.isEmpty ? img : thumbnail)
        self.thumbnail = thumbnail
    }
}

private struct LegacyFeedAnswer: Decodable {
    let eps: [LegacyEpisodeItem]

    init(from decoder: any Decoder) throws {
        eps = try decoder.apiContainer().zero("eps")
    }
}

private struct LegacyClipAnswer: Decodable {
    let item: LegacyEpisodeItem
    let files: [ClipFile]

    init(from decoder: any Decoder) throws {
        item = try LegacyEpisodeItem(from: decoder)
        files = try decoder.apiContainer().zero("files")
    }
}
