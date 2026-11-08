import Foundation

/// The sharing endpoints. A sharing link lets another person watch an
/// episode without an account; the account may create a few per month.
extension OrangeflixAPI {
    // MARK: Limit

    /// Whether the account may create sharing links and how many it may still
    /// create this month.
    func sharingLimit() async throws -> SharingLimit {
        try await requestField("sharing", as: SharingLimit.self, "GET", "sharing/limit")
    }

    // MARK: Links

    /// The sharing links of the account.
    func sharingLinks() async throws -> [SharingLinkEntry] {
        try await requestField("links", as: [SharingLinkEntry].self, "GET", "sharing/links")
    }

    /// Creates a sharing link for an episode the account may watch.
    func createSharingLink(clipID: String) async throws -> SharingLink {
        try await requestField("link", as: SharingLink.self, "POST",
                               "sharing/" + APIHTTP.pathEscape(clipID))
    }

    /// Ends a sharing link that was not used yet.
    func revokeSharingLink(code: String) async throws {
        _ = try await requestData("DELETE", "sharing/" + APIHTTP.pathEscape(code))
    }

    // MARK: Public checks

    /// Resolves a sharing code to the episode it shows. The endpoint is
    /// public, so it goes out without a token.
    func resolveSharingCode(_ code: String) async throws -> SharingResolution {
        let data = try await send(token: "", method: "GET",
                                  path: "sharing/resolve/" + APIHTTP.pathEscape(code))
        return try APIJSON.decode(SharingResolution.self, from: data)
    }

    /// Checks whether a sharing code may still be used and how many views are
    /// left. The endpoint is public, so it goes out without a token.
    func validateSharingCode(_ code: String, clipID: String) async throws -> SharingValidation {
        let data = try await send(token: "", method: "GET",
                                  path: "sharing/validate/" + APIHTTP.pathEscape(clipID)
                                        + "/" + APIHTTP.pathEscape(code))
        return try APIJSON.decode(SharingValidation.self, from: data)
    }
}
