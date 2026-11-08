import Foundation
import Testing

@testable import OrangeflixLogic

/// The retry, throttling and encoding rules of the API layer. These are the
/// rules that decide whether a request is repeated or a login is refused, and
/// they are pure functions, so they are tested without a network.
@Suite("APIHTTP")
struct APIHTTPTests {

    // MARK: Backoff

    /// The first pause is one second plus up to 25 percent jitter.
    @Test("backoff starts at one second and stays within the jitter window")
    func backoffFirstAttempt() {
        for _ in 0..<50 {
            let delay = APIHTTP.backoff(attempt: 1)
            let seconds = delay.seconds
            #expect(seconds >= 1.0)
            #expect(seconds <= 1.25)
        }
    }

    /// The pause doubles with every attempt.
    @Test("backoff doubles per attempt")
    func backoffDoubles() {
        for attempt in 1...5 {
            let lower = pow(2.0, Double(attempt - 1))
            let delay = APIHTTP.backoff(attempt: attempt).seconds
            #expect(delay >= lower)
            #expect(delay <= lower * 1.25)
        }
    }

    /// The pause is capped at 30 seconds, however many attempts were made.
    @Test("backoff is capped at 30 seconds")
    func backoffIsCapped() {
        for attempt in [10, 20, 40, 1000] {
            let delay = APIHTTP.backoff(attempt: attempt).seconds
            #expect(delay <= 30 * 1.25)
        }
    }

    /// A negative or zero attempt must not shift by a negative amount.
    @Test("backoff survives a nonsensical attempt number")
    func backoffWithBadAttempt() {
        let delay = APIHTTP.backoff(attempt: 0).seconds
        #expect(delay >= 1.0)
        #expect(delay <= 1.25)
    }

    // MARK: Retry-After

    /// A number of seconds is read as seconds.
    @Test("Retry-After as a number of seconds")
    func retryAfterSecondsHeader() {
        let delay = APIHTTP.retryAfterHeader("120", now: Date())
        #expect(delay?.seconds == 120)
    }

    /// An HTTP date is read as the distance to now.
    @Test("Retry-After as an HTTP date")
    func retryAfterDateHeader() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let later = now.addingTimeInterval(90)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let delay = APIHTTP.retryAfterHeader(formatter.string(from: later), now: now)
        #expect(delay != nil)
        #expect(abs((delay?.seconds ?? 0) - 90) < 1)
    }

    /// Garbage in the header is not a pause.
    @Test("Retry-After with unusable content is ignored")
    func retryAfterGarbage() {
        #expect(APIHTTP.retryAfterHeader("", now: Date()) == nil)
        #expect(APIHTTP.retryAfterHeader("   ", now: Date()) == nil)
        #expect(APIHTTP.retryAfterHeader("soon", now: Date()) == nil)
    }

    /// A negative number is not a pause.
    @Test("Retry-After with a negative number is ignored")
    func retryAfterNegative() {
        #expect(APIHTTP.retryAfterHeader("-5", now: Date()) == nil)
    }

    /// The announced pause is clamped into a useful range: at least a second,
    /// at most five minutes.
    @Test("the announced pause is clamped")
    func serverDelayIsClamped() {
        #expect(APIHTTP.clampServerDelay(.seconds(0)).seconds == 1)
        #expect(APIHTTP.clampServerDelay(.seconds(-30)).seconds == 1)
        #expect(APIHTTP.clampServerDelay(.seconds(600)).seconds == 300)
        #expect(APIHTTP.clampServerDelay(.seconds(42)).seconds == 42)
    }

    /// The pause is read from the body when the header is missing, also from
    /// the nested error object.
    @Test("the pause is read from the body")
    func retryAfterFromBody() {
        let plain = Data(#"{"retryAfter": 45}"#.utf8)
        #expect(APIHTTP.retryAfterSeconds(plain) == 45)
        let nested = Data(#"{"error": {"retryAfter": 60}}"#.utf8)
        #expect(APIHTTP.retryAfterSeconds(nested) == 60)
        let none = Data(#"{"ok": true}"#.utf8)
        #expect(APIHTTP.retryAfterSeconds(none) == nil)
        let zero = Data(#"{"retryAfter": 0}"#.utf8)
        #expect(APIHTTP.retryAfterSeconds(zero) == nil)
    }

    /// The header wins over the body.
    @Test("the header wins over the body")
    func headerWinsOverBody() {
        let body = Data(#"{"retryAfter": 300}"#.utf8)
        let delay = APIHTTP.rateLimitDelay(retryAfter: "10", body: body, attempt: 1)
        #expect(delay.seconds == 10)
    }

    /// Without a header and a body the own backoff is used.
    @Test("without an announcement the backoff is used")
    func fallsBackToBackoff() {
        let delay = APIHTTP.rateLimitDelay(retryAfter: nil, body: Data(), attempt: 1)
        #expect(delay.seconds >= 1.0)
        #expect(delay.seconds <= 1.25)
    }

    // MARK: Rate limit marker

    /// The legacy API reports the rate limit as plain text with status 200.
    @Test("the plain text rate limit marker is recognised")
    func rateLimitMarker() {
        #expect(APIHTTP.isRateLimited(Data("RATE LIMITED".utf8)))
        #expect(APIHTTP.isRateLimited(Data("rate limited".utf8)))
        #expect(APIHTTP.isRateLimited(Data("  Rate   Limited  ".utf8)))
        #expect(!APIHTTP.isRateLimited(Data(#"{"ok": true}"#.utf8)))
    }

    // MARK: URL encoding

    /// The unreserved characters of RFC 3986 stay as they are.
    @Test("unreserved characters are not escaped")
    func unreservedCharacters() {
        let plain = "abcXYZ019-_.~"
        #expect(APIHTTP.queryEscape(plain) == plain)
        #expect(APIHTTP.pathEscape(plain) == plain)
    }

    /// A space becomes "+" in a query and "%20" in a path, like Go.
    @Test("a space is escaped per context")
    func spaceEscaping() {
        #expect(APIHTTP.queryEscape("a b") == "a+b")
        #expect(APIHTTP.pathEscape("a b") == "a%20b")
    }

    /// Non-ASCII is escaped byte by byte as UTF-8.
    @Test("non-ASCII is escaped as UTF-8 bytes")
    func utf8Escaping() {
        #expect(APIHTTP.queryEscape("ä") == "%C3%A4")
        #expect(APIHTTP.pathEscape("ä") == "%C3%A4")
    }

    /// The characters Go leaves alone in a path are left alone here.
    @Test("path characters of Go stay unescaped")
    func pathAllowedCharacters() {
        for character in "$&+:=@" {
            #expect(APIHTTP.pathEscape(String(character)) == String(character))
        }
        // ... but they are escaped in a query.
        #expect(APIHTTP.queryEscape("&") == "%26")
        #expect(APIHTTP.queryEscape("+") == "%2B")
    }

    /// A slash is escaped in a path segment and in a query.
    @Test("a slash is escaped")
    func slashEscaping() {
        #expect(APIHTTP.pathEscape("a/b") == "a%2Fb")
        #expect(APIHTTP.queryEscape("a/b") == "a%2Fb")
    }

    /// The query is sorted by key, and equal keys keep their order.
    @Test("the query is sorted by key")
    func queryOrder() {
        let encoded = APIHTTP.encodeQuery([("b", "2"), ("a", "1"), ("c", "3")])
        #expect(encoded == "a=1&b=2&c=3")
    }

    /// Equal keys keep the order they were given in.
    @Test("equal keys keep their order")
    func queryStableOrder() {
        let encoded = APIHTTP.encodeQuery([("a", "1"), ("a", "2")])
        #expect(encoded == "a=1&a=2")
    }

    // MARK: Messages

    /// A long body is cut and marked.
    @Test("a long error body is shortened")
    func bodyIsTruncated() {
        let long = String(repeating: "x", count: 500)
        let text = APIHTTP.truncateBody(Data(long.utf8))
        #expect(text.count == APIDefaults.errorBodyLimit + 3)
        #expect(text.hasSuffix("..."))
    }

    /// White space in an error body is collapsed, so a message stays one line.
    @Test("white space in an error body is collapsed")
    func bodyWhiteSpace() {
        let text = APIHTTP.truncateBody(Data("  a \n\n b\tc  ".utf8))
        #expect(text == "a b c")
    }

    /// The reason is read from a string or from an object.
    @Test("the error reason is read from both shapes")
    func errorMessageShapes() {
        #expect(APIHTTP.apiErrorMessage(Data(#"{"error": "kaputt"}"#.utf8)) == "kaputt")
        #expect(APIHTTP.apiErrorMessage(Data(#"{"error": {"message": "auch kaputt"}}"#.utf8)) == "auch kaputt")
    }

    /// A retry hint in the error object ends up in the message.
    @Test("a retry hint is part of the message")
    func errorMessageWithRetry() {
        let body = Data(#"{"error": {"message": "zu schnell", "retryAfter": 30}}"#.utf8)
        let message = APIHTTP.apiErrorMessage(body)
        #expect(message.contains("zu schnell"))
        #expect(message.contains("30"))
    }

    /// A body that is not JSON falls back to its text.
    @Test("a body that is not JSON falls back to its text")
    func errorMessageFallback() {
        #expect(APIHTTP.apiErrorMessage(Data("nicht json".utf8)) == "nicht json")
    }
}

// MARK: - Helpers

extension Duration {
    /// The duration in seconds, for comparisons in tests.
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
