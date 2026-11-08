import Foundation

// The models of the session endpoints. They list the devices that are signed
// in on the account and end single sessions.

// MARK: - Session

/// One active session of the account.
struct AccountSession: Sendable, Hashable, Decodable, Identifiable {
    /// The id the server knows the session by.
    var id = ""
    /// The start in Unix seconds; nil when the server does not say.
    var createdAt: Int64?
    /// The last renewal of the token in Unix seconds.
    var lastRefreshedAt: Int64?
    /// The name of the device, as the account named it.
    var deviceName: String?
    /// The client the session belongs to.
    var client: SessionClientInfo?
    /// The browser string of the client.
    var userAgent: String?
    /// The address the session logged in from.
    var ip: String?
    /// The address the session was last seen from.
    var lastIp: String?
    /// The moment the address changed, in Unix seconds.
    var lastSeenAt: Int64?
    /// Whether the session lasts longer than a day.
    var extended = false
    /// Whether this is the session that asks.
    var current = false

    /// The start as a date.
    var createdDate: Date? {
        guard let createdAt, createdAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    /// The last renewal as a date.
    var refreshedDate: Date? {
        guard let lastRefreshedAt, lastRefreshedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastRefreshedAt))
    }

    /// The name the interface shows: the device, else the client, else the
    /// browser string.
    var label: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        if let client, !client.deviceType.isEmpty { return client.deviceType }
        if let userAgent, !userAgent.isEmpty { return userAgent }
        return "Sitzung"
    }

    init(from decoder: any Decoder) throws {
        // The fields are read one by one: one field of another shape must
        // not spoil the rest.
        let raw = try JSONValue(from: decoder)
        id = raw.firstString(of: ["id"]) ?? ""
        createdAt = raw.int("createdAt").map(Int64.init)
        lastRefreshedAt = raw.int("lastRefreshedAt").map(Int64.init)
        deviceName = raw.string("deviceName")
        if let client = raw.object("client") {
            self.client = SessionClientInfo(raw: JSONValue.object(client))
        }
        userAgent = raw.string("userAgent")
        ip = raw.string("ip")
        lastIp = raw.string("lastIp")
        lastSeenAt = raw.int("lastSeenAt").map(Int64.init)
        extended = raw.bool("extended") ?? false
        current = raw.bool("current") ?? false
    }
}

/// The client a session belongs to. The client names itself; it is no proof
/// of a trusted app.
struct SessionClientInfo: Sendable, Hashable, Decodable {
    /// The name of the client ("orangeflix-tv").
    var id = ""
    /// The platform ("tizen").
    var platform = ""
    /// The kind of the device ("tv").
    var deviceType = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        id = try c.zero("id")
        platform = try c.zero("platform")
        deviceType = try c.zero("deviceType")
    }

    /// Reads the client out of the raw answer.
    init(raw: JSONValue) {
        id = raw.firstString(of: ["id"]) ?? ""
        platform = raw.firstString(of: ["platform"]) ?? ""
        deviceType = raw.firstString(of: ["deviceType", "type"]) ?? ""
    }
}

/// The answer of the list of the sessions.
struct SessionList: Sendable, Hashable, Decodable {
    var ok = false
    /// The sessions of the account.
    var sessions: [AccountSession] = []

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        let raw: [JSONValue]? = c.tolerant("sessions")
        sessions = (raw ?? []).compactMap { element in
            try? element.decode(AccountSession.self)
        }
    }
}

// MARK: - Recovery

/// The short-lived credential that may list and end the sessions of the
/// account. It comes with a login that was refused because the account has
/// too many sessions.
struct SessionRecovery: Sendable, Hashable, Decodable {
    /// The token for the session endpoints.
    var token = ""
    /// The lifetime of the token in seconds.
    var expiresIn = 0

    /// The moment the token runs out.
    var expiresAt: Date? {
        expiresIn > 0 ? Date().addingTimeInterval(TimeInterval(expiresIn)) : nil
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        token = try c.zero("token")
        expiresIn = try c.zero("expiresIn")
    }
}
