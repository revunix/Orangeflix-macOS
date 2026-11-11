import Foundation

/// The facts of the Konto page as German texts, from the answers of
/// `user/me` and `playback/progress`. A fact the API left empty is nil, so
/// the page leaves its row out.
struct AccountFacts {
    let profile: AccountProfile
    /// The started episodes; nil while unknown.
    var progress: [WatchProgressEntry]?

    private static let german = Locale(identifier: "de_DE")

    private var subscription: AccountSubscription { profile.subscription }

    // MARK: Profil

    var chatname: String? { Self.text(profile.chatname) }
    /// The name the account shows; it may be empty.
    var displayName: String? { Self.text(profile.name) }
    var memberSince: String? { Self.date(unix: profile.createdAt).map(Self.day) }
    var lastLogin: String? { Self.date(unix: profile.lastLogin).map(Self.dayAndTime) }

    /// The time the feed was looked at last; the API sends seconds or a text.
    var feedSeen: String? {
        switch profile.feedSeenAt {
        case .number(let value): Self.date(unix: Int64(value)).map(Self.dayAndTime)
        case .string(let value): Self.date(text: value).map(Self.dayAndTime) ?? Self.text(value)
        default: nil
        }
    }

    var twoFactor: String { profile.hasTotp ? "eingerichtet" : "nicht eingerichtet" }

    /// The address of the picture when the API names a whole one.
    var avatarURL: URL? {
        guard profile.avatar.hasPrefix("http"), let url = URL(string: profile.avatar) else { return nil }
        return url
    }

    // MARK: Abo

    var hasAccess: String { subscription.hasAccess ? "ja" : "nein" }
    var accessType: String? {
        guard let raw = Self.text(subscription.accessType) else { return nil }
        switch raw.lowercased() {
        case "subscription": return "Abonnement"
        case "lifetime": return "Dauerzugang"
        case "voucher", "gift", "code": return "Gutschein"
        case "trial": return "Testzugang"
        default: return raw
        }
    }
    var plan: String? {
        Self.text(subscription.activeSubDesc) ?? (subscription.activeSub > 0 ? "Nr. \(subscription.activeSub)" : nil)
    }
    var nextPayment: String? {
        Self.text(subscription.nextCaptureFormatted) ?? Self.date(unix: subscription.nextCapture).map(Self.day)
    }
    /// The amount of the next payment; the API's own text when it sends one.
    var amount: String? {
        Self.text(subscription.captureAmountFormatted)
            ?? (subscription.captureAmount > 0 ? "\(subscription.captureAmount)" : nil)
    }
    /// The amount the server computed, when it differs from `amount`.
    var computedAmount: String? {
        let value = subscription.computedCaptureAmount
        return value > 0 && value != subscription.captureAmount ? "\(value)" : nil
    }

    // MARK: Nutzung

    var startedCount: Int? { progress?.filter(\.hasStarted).count }
    /// Episodes watched to at least 90 percent.
    var finishedCount: Int? { progress?.filter { $0.percentage >= 90 }.count }
    var lastWatched: String? {
        progress?.compactMap { Self.date(text: $0.lastAccessed) }.max().map(Self.dayAndTime)
    }

    // MARK: Formatting

    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Seconds since 1970; a value in milliseconds is recognised by its size.
    static func date(unix: Int64) -> Date? {
        guard unix > 0 else { return nil }
        let seconds = unix > 100_000_000_000 ? Double(unix) / 1000 : Double(unix)
        return Date(timeIntervalSince1970: seconds)
    }

    /// An ISO 8601 time, with or without fractions, or a number of seconds.
    static func date(text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let seconds = Int64(trimmed) { return date(unix: seconds) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(german))
    }

    private static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute().locale(german))
    }
}
