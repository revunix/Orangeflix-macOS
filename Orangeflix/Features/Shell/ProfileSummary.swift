import Foundation

/// The state of the subscription for the interface (Go `app.ProfileSummary`,
/// internal/app/v3.go:613-689).
struct ProfileSummary: Sendable, Hashable {
    /// Whether the account may watch the premium content.
    var hasAccess: Bool
    /// The level of the subscription.
    var tier: Int
    /// The kind of the access ("subscription").
    var accessType: String
    /// The time the subscription runs out; nil when unknown.
    var expiresAt: Date?
    /// Whether the subscription never runs out.
    var lifetime: Bool

    init(hasAccess: Bool, tier: Int = 0, accessType: String = "", expiresAt: Date? = nil, lifetime: Bool = false) {
        self.hasAccess = hasAccess
        self.tier = tier
        self.accessType = accessType
        self.expiresAt = expiresAt
        self.lifetime = lifetime
    }

    /// Go `App.ProfileSummary`: an `expiresAt` of 0 means "unknown".
    init(profile: AccountProfile) {
        let subscription = profile.subscription
        self.init(
            hasAccess: subscription.hasAccess,
            tier: subscription.tier,
            accessType: subscription.accessType,
            expiresAt: subscription.expiryDate,
            lifetime: subscription.lifetime)
    }

    /// The number of whole days until the subscription runs out (truncated
    /// toward zero like Go's int conversion); `Int.max` when it never runs
    /// out or the date is unknown.
    func daysLeft(now: Date = Date()) -> Int {
        guard !lifetime, let expiresAt else { return Int.max }
        return Self.days(until: expiresAt, now: now)
    }

    /// The warning for a subscription that ran out or runs out within 14
    /// days, "" otherwise.
    func expiryWarning(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard !lifetime, let expiresAt else { return "" }
        let days = Self.days(until: expiresAt, now: now)
        let day = Self.day(expiresAt, timeZone: timeZone)
        if days < 0 {
            return "Hinweis: Das Abo ist abgelaufen (\(day)); vielleicht ist deshalb keine Folge ladbar."
        }
        if days <= 14 {
            return "Hinweis: Das Abo läuft in \(days) Tag(en) ab (\(day))."
        }
        return ""
    }

    /// The short text of the Konto line: "kein Zugang" or
    /// "<AccessType or Zugang>[ bis dd.mm.yyyy][ (Stufe N)]".
    func summarize(timeZone: TimeZone = .current) -> String {
        guard hasAccess else { return "kein Zugang" }
        var text = accessType.isEmpty ? "Zugang" : accessType
        if let expiresAt {
            text += " bis " + Self.day(expiresAt, timeZone: timeZone)
        }
        if tier > 0 {
            text += " (Stufe \(tier))"
        }
        return text
    }

    /// Go `int(time.Until(t).Hours() / 24)`.
    private static func days(until date: Date, now: Date) -> Int {
        let hours = date.timeIntervalSince(now) / 3600
        return Int(hours / 24)
    }

    /// "02.01.2006" in the given zone (Go `Local().Format`).
    private static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}
