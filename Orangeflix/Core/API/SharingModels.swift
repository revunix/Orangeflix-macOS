import Foundation

// The models of the sharing endpoints. A sharing link lets another person
// watch a clip without an account; the account may create a few per month.

// MARK: - Limit

extension SharingLimit: APIZeroValue {}

/// Whether the account may create sharing links and how many it may still
/// create this month.
struct SharingLimit: Sendable, Hashable, Decodable {
    /// Whether the account may create sharing links at all.
    var eligible = false
    /// The tier of the account.
    var tier = 0
    /// The tier the sharing links need.
    var requiredTier = 0
    /// The links per month; nil when no limit applies.
    var monthlyLimit: Int?
    /// The links created this month.
    var used = 0
    /// The links that may still be created; nil when no limit applies.
    var remaining: Int?
    /// The views one link allows.
    var accessLimitPerLink = 0

    /// Whether there are links left this month.
    var hasQuota: Bool {
        guard let remaining else { return true }
        return remaining > 0
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        eligible = try c.zero("eligible")
        tier = try c.zero("tier")
        requiredTier = try c.zero("requiredTier")
        monthlyLimit = try c.optional("monthlyLimit")
        used = try c.zero("used")
        remaining = try c.optional("remaining")
        accessLimitPerLink = try c.zero("accessLimitPerLink")
    }
}

// MARK: - Links

extension SharingLink: APIZeroValue {}

/// The link the API created; it carries the address to share.
struct SharingLink: Sendable, Hashable, Decodable, Identifiable {
    /// The code identifies the link.
    var id: String { code }

    /// The code that identifies the link.
    var code = ""
    /// The clip the link shows.
    var clipId = ""
    /// The address that may be given to another person.
    var url = ""
    /// The views the link allows.
    var accessLimit = 0
    /// The links that may still be created this month; nil when no limit
    /// applies.
    var remaining: Int?

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        code = try c.zero("code")
        clipId = try c.zero("clipId")
        url = try c.zero("url")
        accessLimit = try c.zero("accessLimit")
        remaining = try c.optional("remaining")
    }
}

/// One sharing link in the list of the account.
struct SharingLinkEntry: Sendable, Hashable, Decodable {
    /// The code that identifies the link.
    var code = ""
    /// The clip the link shows.
    var clipId = ""
    /// How often the link was used.
    var accessed = 0
    /// Whether the link has no limit of views.
    var unlimited = false
    /// The views that are left; nil when the link is unlimited.
    var remaining: Int?
    /// The creation in Unix seconds.
    var created: Int64 = 0

    /// The creation as a date; nil when the API does not say.
    var createdDate: Date? {
        created > 0 ? Date(timeIntervalSince1970: TimeInterval(created)) : nil
    }

    /// Whether the link may still be revoked: a link that was used once
    /// cannot.
    var isRevocable: Bool { accessed == 0 }

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        code = try c.zero("code")
        clipId = try c.zero("clipId")
        accessed = try c.zero("accessed")
        unlimited = try c.zero("unlimited")
        remaining = try c.optional("remaining")
        created = try c.zero("created")
    }
}

// MARK: - Validation

/// Why a sharing code is not usable.
enum SharingCodeProblem: String, Sendable, Hashable {
    /// The code does not exist.
    case notFound
    /// The code was used up.
    case exhausted

    /// The German text of the problem.
    var text: String {
        switch self {
        case .notFound: "Der Link ist unbekannt."
        case .exhausted: "Der Link ist aufgebraucht."
        }
    }
}

/// The answer of the public check of a sharing code.
struct SharingValidation: Sendable, Hashable, Decodable {
    var ok = false
    /// Whether the code may still be used.
    var valid = false
    /// The views that are left; nil when the API does not say.
    var remaining: Int?
    /// Why the code is not usable.
    var problem: SharingCodeProblem?

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        valid = try c.zero("valid")
        remaining = try c.optional("remaining")
        let reason: String = try c.zero("reason")
        problem = SharingCodeProblem(rawValue: reason)
    }
}

/// The clip a sharing code shows.
struct SharingResolution: Sendable, Hashable, Decodable {
    var ok = false
    /// The clip of the code.
    var clipId = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        ok = try c.zero("ok")
        clipId = try c.zero("clipId")
    }
}
