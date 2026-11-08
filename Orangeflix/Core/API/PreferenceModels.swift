import Foundation

// The models of the endpoints of the account: its preferences, the optional
// personal data (address, birthday, credits) and the legal confirmations.

// MARK: - Preferences

/// The categories the main feed leaves out, per format. The key is the
/// format (the pid), the value the categories (the subpids).
typealias FeedExclusionFilter = [Int: [Int]]

/// The preferences of the account.
struct UserPreferences: Sendable, Hashable, Decodable {
    /// How the main feed is shown, 1…3.
    var feedStyle = 1
    /// Whether the account wants the old player.
    var legacyPlayer = false
    /// The categories the main feed leaves out.
    var exclusionFilter: FeedExclusionFilter = [:]
    /// How the account is notified.
    var notifications = NotificationSettings()
    /// The optional personal data the account stored.
    var optionalInfo = OptionalInfoStatus()
    /// The legal confirmations of the account.
    var privacy = PrivacyStatus()

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        // The answer is read field by field: one field of another shape must
        // not spoil the rest.
        let preferences: JSONValue? = c.tolerant("preferences")
        feedStyle = preferences?.int("feedStyle") ?? 1
        legacyPlayer = preferences?.bool("legacyPlayer") ?? false
        exclusionFilter = FeedExclusionFilter.read(from: preferences?["exclusionFilter"])
        notifications = NotificationSettings(raw: preferences?["notifications"])
        let rawOptionalInfo: JSONValue? = c.tolerant("optionalInfo")
        let rawPrivacy: JSONValue? = c.tolerant("privacy")
        optionalInfo = OptionalInfoStatus(raw: rawOptionalInfo)
        privacy = PrivacyStatus(raw: rawPrivacy)
    }
}

extension FeedExclusionFilter {
    /// Reads the map of the excluded categories; the keys are the formats.
    static func read(from raw: JSONValue?) -> FeedExclusionFilter {
        guard let members = raw?.objectValue else { return [:] }
        var filter: FeedExclusionFilter = [:]
        for (key, value) in members {
            guard let pid = Int(key) else { continue }
            let subpids = (value.arrayValue ?? []).compactMap(\.intValue)
            if !subpids.isEmpty { filter[pid] = subpids }
        }
        return filter
    }
}

/// How the account is notified.
struct NotificationSettings: Sendable, Hashable, Decodable {
    /// The way the notifications go out, 1…3.
    var method = 0
    /// The name of the way, as the server writes it.
    var methodName = ""
    /// Whether the notifications are on.
    var enabled = false

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        method = try c.zero("method")
        methodName = try c.zero("methodName")
        enabled = try c.zero("enabled")
    }

    /// Reads the settings out of the raw answer.
    init(raw: JSONValue?) {
        method = raw?.int("method") ?? 0
        methodName = raw?.string("methodName") ?? ""
        enabled = raw?.bool("enabled") ?? false
    }
}

/// Whether the account stored the optional personal data. The values
/// themselves stay on the server.
struct OptionalInfoStatus: Sendable, Hashable, Decodable {
    var addressCollected = false
    var birthdayCollected = false
    var abonameCollected = false
    var creditsCollected = false

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        addressCollected = try c.zero("addressCollected")
        birthdayCollected = try c.zero("birthdayCollected")
        abonameCollected = try c.zero("abonameCollected")
        creditsCollected = try c.zero("creditsCollected")
    }

    /// Reads the state out of a map of flags; the server names the fields
    /// with or without the ending "Collected".
    init(raw: JSONValue?) {
        guard let members = raw?.objectValue else { return }
        addressCollected = (members["addressCollected"] ?? members["address"])?.boolValue ?? false
        birthdayCollected = (members["birthdayCollected"] ?? members["birthday"])?.boolValue ?? false
        abonameCollected = (members["abonameCollected"] ?? members["aboname"])?.boolValue ?? false
        creditsCollected = (members["creditsCollected"] ?? members["credits"])?.boolValue ?? false
    }
}

/// The legal confirmations of the account.
struct PrivacyStatus: Sendable, Hashable, Decodable {
    var acceptedPrivacy1 = false
    var acceptedPrivacy2 = false
    var acceptedAgb2 = false

    /// Whether every confirmation the server asks for is given.
    var isComplete: Bool { acceptedPrivacy1 && acceptedPrivacy2 && acceptedAgb2 }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        acceptedPrivacy1 = try c.zero("acceptedPrivacy1")
        acceptedPrivacy2 = try c.zero("acceptedPrivacy2")
        acceptedAgb2 = try c.zero("acceptedAgb2")
    }

    /// Reads the confirmations out of the raw answer.
    init(raw: JSONValue?) {
        acceptedPrivacy1 = raw?.bool("acceptedPrivacy1") ?? false
        acceptedPrivacy2 = raw?.bool("acceptedPrivacy2") ?? false
        acceptedAgb2 = raw?.bool("acceptedAgb2") ?? false
    }
}

/// The marker that says until when the account has seen the feed.
struct FeedSeenMarker: Sendable, Hashable, Decodable {
    /// The moment of the last visit in Unix seconds; nil when the account
    /// has never visited.
    var feedSeenAt: Int64?

    /// The moment as a date; nil when the account has never visited.
    var date: Date? {
        guard let feedSeenAt, feedSeenAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(feedSeenAt))
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        // The API sends a number or a string.
        let raw: JSONValue? = try c.optional("feedSeenAt")
        switch raw {
        case .number(let number): feedSeenAt = Int64(number)
        case .string(let text): feedSeenAt = Int64(text)
        default: feedSeenAt = nil
        }
    }
}

// MARK: - Bodies

/// The body of a change of the preferences of the account. Only the parts
/// that are not nil are changed.
struct UserPreferencesUpdate: Encodable {
    /// How the main feed is shown, 1…3.
    var feedStyle: Int?
    /// Whether the account wants the old player.
    var legacyPlayer: Bool?
    /// The name the account shows.
    var name: String?
    /// The name in the chat.
    var chatname: String?
    /// The categories the main feed leaves out.
    var exclusionFilter: FeedExclusionFilter?
    /// How the account is notified.
    var notifications: NotificationSettingsUpdate?

    init(feedStyle: Int? = nil, legacyPlayer: Bool? = nil, name: String? = nil,
         chatname: String? = nil, exclusionFilter: FeedExclusionFilter? = nil,
         notifications: NotificationSettingsUpdate? = nil) {
        self.feedStyle = feedStyle
        self.legacyPlayer = legacyPlayer
        self.name = name
        self.chatname = chatname
        self.exclusionFilter = exclusionFilter
        self.notifications = notifications
    }
}

/// How the account is notified.
struct NotificationSettingsUpdate: Encodable {
    /// The way the notifications go out, 1…3.
    var method: Int?
    /// Whether the notifications are on.
    var enabled: Bool?

    init(method: Int? = nil, enabled: Bool? = nil) {
        self.method = method
        self.enabled = enabled
    }
}

/// The categories the main feed leaves out. The change may leave them
/// alone, clear them or name new ones.
enum ExclusionFilterChange: Encodable {
    /// The filter stays as it is.
    case keep
    /// The filter is emptied.
    case clear
    /// The filter gets these categories.
    case set(FeedExclusionFilter)

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .keep, .clear:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .set(let value):
            try value.encode(to: encoder)
        }
    }
}

/// The body of a change of the preferences of the feed.
struct FeedPreferencesUpdate: Encodable {
    /// The names of the fields in the body.
    private enum CodingKeys: String, CodingKey {
        case feedStyle
        case exclusionFilter
    }

    /// How the main feed is shown, 1…3.
    var feedStyle: Int?
    /// The categories the main feed leaves out.
    var exclusionFilter: ExclusionFilterChange?

    init(feedStyle: Int? = nil, exclusionFilter: ExclusionFilterChange? = nil) {
        self.feedStyle = feedStyle
        self.exclusionFilter = exclusionFilter
    }

    /// The filter is written only when it changes; an emptied filter goes
    /// out as `null`.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(feedStyle, forKey: .feedStyle)
        switch exclusionFilter {
        case .none, .some(.keep):
            break
        case .some(.clear):
            try container.encodeNil(forKey: .exclusionFilter)
        case .some(.set(let value)):
            try container.encode(value, forKey: .exclusionFilter)
        }
    }
}

/// The shipping address of the account.
struct AddressInput: Encodable {
    /// The name on the parcel.
    var name: String
    /// The street and the number.
    var address: String
    /// The second line of the address.
    var address2: String?
    /// The postal code.
    var zip: String
    /// The city.
    var city: String
    /// The country as two letters ("DE").
    var country: String

    init(name: String, address: String, address2: String? = nil, zip: String, city: String, country: String) {
        self.name = name
        self.address = address
        self.address2 = address2
        self.zip = zip
        self.city = city
        self.country = country
    }
}

/// The birthday of the account.
struct BirthdayInput: Encodable {
    /// The day of the month, 1…31.
    var day: Int
    /// The month, 1…12.
    var month: Int
    /// The year; nil when the account does not want to name it.
    var year: Int?

    init(day: Int, month: Int, year: Int? = nil) {
        self.day = day
        self.month = month
        self.year = year
    }
}

/// The mention of the account in the credits.
struct CreditsInput: Encodable {
    /// The name in the credits.
    var name: String
    /// The format the credits belong to.
    var mag: String

    init(name: String, mag: String) {
        self.name = name
        self.mag = mag
    }
}

/// The answer of a change of the preferences. The server names the fields it
/// changed; the new preferences have to be read again.
struct PreferencesUpdateResponse: Sendable, Hashable, Decodable {
    var ok = false
    /// The message of the server.
    var message = ""
    /// The fields the server changed; its shape is not fixed.
    var updated: JSONValue?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        message = try c.zero("message")
        updated = try c.optional("updated")
    }
}

/// The answer of a change of the optional personal data.
struct OptionalInfoUpdateResponse: Sendable, Hashable, Decodable {
    var ok = false
    /// The message of the server.
    var message = ""
    /// The state of the personal data after the change.
    var optionalInfo = OptionalInfoStatus()
    /// The raw answer of the server; it writes the state as a map of flags.
    var rawOptionalInfo: JSONValue?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        message = try c.zero("message")
        let raw: JSONValue? = try c.optional("optionalInfo")
        rawOptionalInfo = raw
        optionalInfo = OptionalInfoStatus(raw: raw)
    }
}

// MARK: - Legal

/// A confirmation the server wants the user to give.
struct UiAction: Sendable, Hashable, Decodable, Identifiable {
    var id: String { type + ":" + endpoint }

    /// What has to be confirmed ("accept_agb", "accept_privacy").
    var type = ""
    /// Whether the confirmation is needed.
    var required = false
    /// The version of the text.
    var version: Int64 = 0
    /// The version the account already confirmed; nil when none.
    var acceptedVersion: Int64?
    /// The endpoint that records the confirmation.
    var endpoint = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        type = try c.zero("type")
        required = try c.zero("required")
        version = try c.zero("version")
        acceptedVersion = try c.optional("acceptedVersion")
        endpoint = try c.zero("endpoint")
    }

    /// Reads the confirmation out of the raw answer.
    init(raw: JSONValue) {
        type = raw.firstString(of: ["type", "action"]) ?? ""
        required = raw.firstBool(of: ["required", "needed"]) ?? false
        version = Int64(raw.firstInt(of: ["version"]) ?? 0)
        acceptedVersion = raw.firstInt(of: ["acceptedVersion"]).map(Int64.init)
        endpoint = raw.firstString(of: ["endpoint"]) ?? ""
    }
}

/// The answer of a confirmation of the legal texts.
struct LegalAcceptance: Sendable, Hashable, Decodable {
    var ok = false
    /// The message of the server.
    var message = ""
    /// The confirmations that are still open.
    var uiActions: [UiAction] = []

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        message = try c.zero("message")
        let raw: [JSONValue]? = c.tolerant("uiActions")
        uiActions = (raw ?? []).map { UiAction(raw: $0) }
    }
}
