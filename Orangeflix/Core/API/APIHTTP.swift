import Foundation

/// Defaults shared by the v3 and the legacy client.
enum APIDefaults {
    /// The base of the version 3 API, the API the Orangeflix app uses.
    static let v3BaseURL = "https://massengeschmack.tv/api/v3/"
    /// The legacy API. The API and the download host still live under the
    /// old name.
    static let legacyBaseURL = "https://massengeschmack.tv/api/v1/"
    /// The base of the RSS feeds.
    static let feedURL = "https://massengeschmack.tv/feed/"
    /// Identifies this Mac app. A browser string is stored with the session and
    /// shown on the account page as that browser.
    static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Orangeflix/\(version) (Macintosh; macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion))"
    }

    /// Caps the size of an API answer.
    static let maxResponseBytes = 8 << 20
    /// The number of characters of an error body that end up in a message.
    static let errorBodyLimit = 200
    /// The tries of a legacy request.
    static let legacyAttempts = 4
    /// The tries of a v3 request.
    static let v3Attempts = 3
    /// The longest pause of the own backoff.
    static let maxBackoff: Duration = .seconds(30)
    /// The longest pause the API may announce.
    static let maxServerDelay: Duration = .seconds(300)

    /// A session without cookies and caches with the total timeout of the Go
    /// client (120 seconds).
    static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The default pause: waits the duration, returns early on cancellation.
    static let sleep: @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }
}

/// An answer that was read completely.
struct APIResponse: Sendable {
    let status: Int
    let body: Data
}

/// Describes how a request is repeated. Transport errors, server errors and
/// rate limits are retried; every other answer goes back to the caller.
struct APIRetryPolicy: Sendable {
    var attempts: Int
    /// Repeats a request after HTTP 429. A login must not be repeated, it
    /// would only extend the lock of the account.
    var retryRateLimit: Bool
    /// Turns the body of a rate limit into a message.
    var describe: @Sendable (Data) -> String = { APIHTTP.truncateBody($0) }
    /// Reports a rate limit that hides in a successful answer.
    var rateLimited: (@Sendable (Data) -> Bool)? = nil
}

/// Sends requests with the retry and throttling behaviour of the Go client.
struct APIHTTP: Sendable {
    let session: URLSession
    let sleep: @Sendable (Duration) async -> Void

    /// Performs the request; every attempt sends the same request again.
    func send(_ request: URLRequest, policy: APIRetryPolicy) async throws -> APIResponse {
        let attempts = max(policy.attempts, 1)
        var lastError: APIError = .transport("keine Antwort")
        for attempt in 1...attempts {
            try Task.checkCancellation()
            let delay: Duration
            do {
                let (data, response) = try await session.data(for: request)
                let body = data.count > APIDefaults.maxResponseBytes ? data.prefix(APIDefaults.maxResponseBytes) : data
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                if status == 429 {
                    lastError = .rateLimited(policy.describe(body))
                    if !policy.retryRateLimit { throw lastError }
                    delay = Self.rateLimitDelay(retryAfter: retryAfter, body: body, attempt: attempt)
                } else if status >= 500 {
                    lastError = .http(status: status, message: Self.truncateBody(body))
                    delay = Self.backoff(attempt: attempt)
                } else if status < 400, let rateLimited = policy.rateLimited, rateLimited(body) {
                    lastError = .rateLimited("")
                    delay = Self.rateLimitDelay(retryAfter: retryAfter, body: body, attempt: attempt)
                } else {
                    return APIResponse(status: status, body: Data(body))
                }
            } catch let error as APIError {
                throw error
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                lastError = .transport(error.localizedDescription)
                delay = Self.backoff(attempt: attempt)
            }
            if attempt < attempts {
                await sleep(delay)
            }
        }
        throw lastError
    }

    // MARK: Delays

    /// The delay before the next attempt. It doubles with every attempt, is
    /// capped at 30 seconds and carries up to 25 percent jitter, so parallel
    /// clients do not retry in lockstep.
    static func backoff(attempt: Int) -> Duration {
        let shift = min(max(attempt - 1, 0), 30)
        let base = min(Int64(1) << Int64(shift), 30) * 1_000_000_000
        let jitter = Int64.random(in: 0...(base / 4))
        return .nanoseconds(base + jitter)
    }

    /// The pause after a rate limit. The pause the API announces is kept, in
    /// the Retry-After header or in the body, otherwise the backoff is used.
    static func rateLimitDelay(retryAfter: String?, body: Data, attempt: Int, now: Date = Date()) -> Duration {
        if let retryAfter, let delay = retryAfterHeader(retryAfter, now: now) {
            return clampServerDelay(delay)
        }
        if let seconds = retryAfterSeconds(body) {
            return clampServerDelay(.seconds(seconds))
        }
        return backoff(attempt: attempt)
    }

    static func clampServerDelay(_ delay: Duration) -> Duration {
        min(max(delay, .seconds(1)), APIDefaults.maxServerDelay)
    }

    /// Reads the Retry-After header: a number of seconds or an HTTP date.
    static func retryAfterHeader(_ value: String, now: Date) -> Duration? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let seconds = Int(trimmed), seconds >= 0 {
            return .seconds(seconds)
        }
        if let when = parseHTTPDate(trimmed) {
            let interval = when.timeIntervalSince(now)
            return .nanoseconds(Int64((interval * 1_000_000_000).rounded()))
        }
        return nil
    }

    /// Parses the three date formats HTTP allows (RFC 1123, RFC 850, ANSI C).
    static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for layout in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = layout
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// Reads the pause the API announces in the body; it sits sometimes in
    /// the error object.
    static func retryAfterSeconds(_ body: Data) -> Int? {
        struct Inner: Decodable { let retryAfter: Int? }
        struct Answer: Decodable { let retryAfter: Int?; let error: Inner? }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: body) else { return nil }
        if let seconds = answer.retryAfter, seconds > 0 { return seconds }
        if let seconds = answer.error?.retryAfter, seconds > 0 { return seconds }
        return nil
    }

    /// Reports whether the body carries the plain-text rate limit marker of
    /// the legacy API.
    static func isRateLimited(_ body: Data) -> Bool {
        truncateBody(body).uppercased().contains("RATE LIMITED")
    }

    // MARK: Messages

    /// Shortens an error body for a message: the whitespace is collapsed and
    /// the text is cut after 200 bytes.
    static func truncateBody(_ body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let bytes = Array(text.utf8)
        if bytes.count > APIDefaults.errorBodyLimit {
            return String(decoding: bytes[..<APIDefaults.errorBodyLimit], as: UTF8.self) + "..."
        }
        return text
    }

    /// Reads the reason of a failed v3 request. The API names it in the field
    /// "error", either as a string or as an object with a message.
    static func apiErrorMessage(_ body: Data) -> String {
        struct Detailed: Decodable { let message: String?; let code: Int?; let retryAfter: Int? }
        enum Field: Decodable {
            case message(String)
            case detailed(Detailed)
            case other
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .message(text)
                } else if let detailed = try? container.decode(Detailed.self) {
                    self = .detailed(detailed)
                } else {
                    self = .other
                }
            }
        }
        struct Envelope: Decodable { let error: Field? }

        if let envelope = try? JSONDecoder().decode(Envelope.self, from: body), let field = envelope.error {
            switch field {
            case .message(let text) where !text.isEmpty:
                return text
            case .detailed(let detailed):
                if let message = detailed.message, !message.isEmpty {
                    if let seconds = detailed.retryAfter, seconds > 0 {
                        return "\(message) (erneut versuchen in \(seconds) Sekunden)"
                    }
                    return message
                }
            default:
                break
            }
        }
        return truncateBody(body)
    }

    // MARK: URL encoding (Go's net/url rules)

    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)
    private static let pathAllowed = unreserved.union("$&+:=@".utf8)
    private static let hex = Array("0123456789ABCDEF".utf8)

    private static func escape(_ value: String, allowed: Set<UInt8>, spaceAsPlus: Bool) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if allowed.contains(byte) {
                out.append(byte)
            } else if spaceAsPlus && byte == 0x20 {
                out.append(UInt8(ascii: "+"))
            } else {
                out.append(UInt8(ascii: "%"))
                out.append(hex[Int(byte >> 4)])
                out.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Escapes one path segment like `url.PathEscape`.
    static func pathEscape(_ value: String) -> String {
        escape(value, allowed: pathAllowed, spaceAsPlus: false)
    }

    /// Escapes a query component like `url.QueryEscape`.
    static func queryEscape(_ value: String) -> String {
        escape(value, allowed: unreserved, spaceAsPlus: true)
    }

    /// Encodes the query like `url.Values.Encode`: sorted by key.
    static func encodeQuery(_ items: [(String, String)]) -> String {
        items.enumerated()
            .sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }
            .map { queryEscape($0.element.0) + "=" + queryEscape($0.element.1) }
            .joined(separator: "&")
    }
}
