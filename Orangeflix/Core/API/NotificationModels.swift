import Foundation

// The models of the notification endpoints. The API does not fix the shape of
// its answers here, so the models read the fields they know and keep the rest
// of the answer in the raw value.

// MARK: - Catalog

/// One event the app can notify about.
struct NotificationEvent: Identifiable, Sendable, Hashable {
    var id: String { key }

    /// The name of the event ("release", "live", …).
    var key = ""
    /// The name the interface shows.
    var label = ""
    /// The channels the event can use ("push", "email").
    var channels: [String] = []
    /// Whether the event is on when the account made no choice.
    var enabledByDefault = false
    /// Whether the account may change the event.
    var configurable = true

    init(raw: JSONValue) {
        key = raw.firstString(of: ["type", "key", "event", "eventType", "id"]) ?? ""
        label = raw.firstString(of: ["label", "title", "name", "displayName"]) ?? key
        channels = (raw.array("channels") ?? []).compactMap { element in
            if let name = element.stringValue { return name }
            return element.objectValue.flatMap { $0["name"]?.stringValue ?? $0["key"]?.stringValue }
        }
        enabledByDefault = raw.firstBool(of: ["enabledByDefault", "defaultEnabled", "default", "enabled"]) ?? false
        configurable = raw.firstBool(of: ["configurable", "isConfigurable"]) ?? true
    }
}

/// Every event the app can notify about.
struct NotificationEventCatalog: Sendable, Hashable {
    /// The events of the catalog.
    var events: [NotificationEvent] = []

    init(raw: JSONValue) {
        // The catalog comes as a list or behind a named field.
        let list = raw.arrayValue
            ?? raw.array("events")
            ?? raw.array("catalog")
            ?? raw.array("items")
            ?? []
        events = list.map { NotificationEvent(raw: $0) }.filter { !$0.key.isEmpty }
    }
}

// MARK: - Preferences

/// The state of one event type.
struct NotificationEventPreference: Sendable, Hashable {
    /// Whether the event is on.
    var enabled = false
    /// The state of every channel of the event.
    var channels: [String: Bool] = [:]

    init(raw: JSONValue) {
        enabled = raw.firstBool(of: ["enabled", "active", "on"]) ?? false
        channels = NotificationModels.channels(of: raw.object("channels") ?? [:])
    }
}

/// The effective notification preferences of the account.
struct NotificationPreferences: Sendable, Hashable {
    /// The state of the channels of the account ("email", "push").
    var channels: [String: Bool] = [:]
    /// The state of every event type.
    var events: [String: NotificationEventPreference] = [:]
    /// The formats the notifications are sent for.
    var subscriptions: [NotificationSubscription] = []
    /// Whether new formats join the notifications on their own.
    var autoIncludeNewShows = true

    init(raw: JSONValue) {
        if let rawChannels = raw.object("channels") {
            channels = NotificationModels.channels(of: rawChannels)
        } else {
            // The channels may stand at the top of the answer; the known
            // fields of the answer are not channels.
            var members = raw.objectValue ?? [:]
            for key in ["ok", "events", "subscriptions", "preferences", "optionalInfo", "privacy"] {
                members.removeValue(forKey: key)
            }
            channels = NotificationModels.channels(of: members)
        }
        if let rawEvents = raw.object("events") {
            events = rawEvents.mapValues { NotificationEventPreference(raw: $0) }
        }
        if let rawSubscriptions = raw.object("subscriptions") {
            autoIncludeNewShows = rawSubscriptions["autoIncludeNewShows"]?.boolValue ?? true
            subscriptions = (rawSubscriptions["shows"]?.arrayValue ?? []).map { NotificationSubscription(raw: $0) }
        } else if let shows = raw.array("shows") {
            subscriptions = shows.map { NotificationSubscription(raw: $0) }
        }
    }

    /// The state of one event type; nil when the catalog does not know it.
    func preference(for key: String) -> NotificationEventPreference? {
        events[key]
    }
}

/// One format the notifications are sent for.
struct NotificationSubscription: Sendable, Hashable, Identifiable {
    var id: Int { pid }

    /// The format.
    var pid = 0
    /// The categories of the format that are meant; empty when none is.
    var subpids: [Int] = []
    /// Whether every category is meant.
    var all = false

    init(raw: JSONValue) {
        pid = raw.firstInt(of: ["pid", "magazineId", "id"]) ?? 0
        switch raw["subpids"] {
        case .string(let text):
            all = text.lowercased() == "all"
        case .array(let elements):
            subpids = elements.compactMap(\.intValue)
        default:
            break
        }
    }
}

/// The device the app registers for the push notifications.
struct NotificationDevice: Identifiable, Sendable, Hashable {
    var id: String { deviceID }

    /// The id the account knows the device by.
    var deviceID = ""
    /// The platform of the device ("macos", "ios").
    var platform = ""
    /// The name of the device ("Orangeflix für macOS").
    var name = ""
    /// The registration in Unix seconds.
    var createdAt: Int64 = 0
    /// The last use of the device in Unix seconds.
    var lastSeenAt: Int64 = 0

    init(raw: JSONValue) {
        deviceID = raw.firstString(of: ["deviceId", "id", "token"]) ?? ""
        platform = raw.firstString(of: ["platform", "os", "kind"]) ?? ""
        name = raw.firstString(of: ["deviceName", "name", "label", "title"]) ?? ""
        createdAt = Int64(raw.firstInt(of: ["createdAt", "created"]) ?? 0)
        lastSeenAt = Int64(raw.firstInt(of: ["lastSeenAt", "lastUsedAt", "updatedAt"]) ?? 0)
    }
}

/// The number of messages the test notification queued.
struct NotificationTestResult: Sendable, Hashable {
    /// The messages per channel.
    var queued: [String: Int] = [:]
    /// The total of all channels.
    var total: Int { queued.values.reduce(0, +) }
}

// MARK: - Bodies

/// The body of a change of the notification preferences. Every part that is
/// nil keeps its value.
struct NotificationPreferenceUpdate: Encodable {
    /// The state of the channels of the account.
    var channels: [String: NotificationChannelUpdate]?
    /// The state of the event types.
    var events: [String: NotificationEventUpdate]?
    /// The formats the notifications are sent for.
    var subscriptions: NotificationSubscriptionUpdate?

    init(channels: [String: NotificationChannelUpdate]? = nil,
         events: [String: NotificationEventUpdate]? = nil,
         subscriptions: NotificationSubscriptionUpdate? = nil) {
        self.channels = channels
        self.events = events
        self.subscriptions = subscriptions
    }
}

/// The state of one channel.
struct NotificationChannelUpdate: Encodable {
    var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }
}

/// The state of one event type.
struct NotificationEventUpdate: Encodable {
    /// Whether the event is on.
    var enabled: Bool?
    /// The state of every channel of the event.
    var channels: [String: Bool]?

    init(enabled: Bool? = nil, channels: [String: Bool]? = nil) {
        self.enabled = enabled
        self.channels = channels
    }
}

/// The formats the notifications are sent for.
struct NotificationSubscriptionUpdate: Encodable {
    /// The formats with their categories.
    var shows: [NotificationSubscriptionShow]?
    /// Whether new formats join the notifications on their own.
    var autoIncludeNewShows: Bool?

    init(shows: [NotificationSubscriptionShow]? = nil, autoIncludeNewShows: Bool? = nil) {
        self.shows = shows
        self.autoIncludeNewShows = autoIncludeNewShows
    }
}

/// One format with the categories it is notified about.
struct NotificationSubscriptionShow: Encodable {
    /// The format.
    var pid: Int
    /// The categories: all of them, none of them or a list.
    var subpids: NotificationSubpidSelection

    init(pid: Int, subpids: NotificationSubpidSelection) {
        self.pid = pid
        self.subpids = subpids
    }
}

/// The categories of a format that are notified about.
enum NotificationSubpidSelection: Encodable {
    /// Every category.
    case all
    /// No category.
    case none
    /// The named categories.
    case some([Int])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case .none: try container.encode("none")
        case .some(let values): try container.encode(values)
        }
    }
}

// MARK: - Reading the raw answers

/// Reads the answers of the notification endpoints, whose shape the API does
/// not fix.
enum NotificationModels {
    /// The state of the channels of an answer. The API writes them either as
    /// `{"email": true}` or as `{"email": {"enabled": true}}`.
    static func channels(of members: [String: JSONValue]) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for (name, value) in members {
            if let flag = value.boolValue {
                result[name] = flag
            } else if let flag = value.firstBool(of: ["enabled", "active", "on"]) {
                result[name] = flag
            }
        }
        return result
    }

    /// Reads the catalog out of an answer; the list may stand alone or behind
    /// a named field.
    static func catalog(from data: Data) throws -> NotificationEventCatalog {
        let raw = try APIJSON.decode(JSONValue.self, from: data)
        return NotificationEventCatalog(raw: raw)
    }

    /// Reads the preferences out of an answer.
    static func preferences(from data: Data) throws -> NotificationPreferences {
        let raw = try APIJSON.decode(JSONValue.self, from: data)
        return NotificationPreferences(raw: raw)
    }

    /// Reads the devices out of an answer; the list may stand alone or behind
    /// a named field.
    static func devices(from data: Data) throws -> [NotificationDevice] {
        let raw = try APIJSON.decode(JSONValue.self, from: data)
        let list = raw.arrayValue
            ?? raw.array("devices")
            ?? raw.array("items")
            ?? []
        return list.map { NotificationDevice(raw: $0) }.filter { !$0.deviceID.isEmpty }
    }

    /// Reads the result of the test notification out of an answer.
    static func testResult(from data: Data) throws -> NotificationTestResult {
        let raw = try APIJSON.decode(JSONValue.self, from: data)
        var result = NotificationTestResult()
        if let members = raw.object("channels") {
            for (name, value) in members {
                if let count = value.intValue {
                    result.queued[name] = count
                } else if let count = value.objectValue?.first(where: { $0.key == "queued" })?.value.intValue {
                    result.queued[name] = count
                }
            }
        } else if let members = raw.objectValue {
            for (name, value) in members where name != "ok" {
                if let count = value.intValue { result.queued[name] = count }
            }
        }
        return result
    }
}
