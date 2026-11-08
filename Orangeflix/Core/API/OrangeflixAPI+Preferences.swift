import Foundation

/// The endpoints of the account: its preferences, the optional personal data
/// and the legal confirmations.
extension OrangeflixAPI {
    // MARK: Preferences

    /// The preferences of the account: the style of the feed, the way it is
    /// notified and the state of the legal confirmations.
    func userPreferences() async throws -> UserPreferences {
        try await request(UserPreferences.self, "GET", "user/preferences")
    }

    /// Changes the preferences of the account; only the parts that are not
    /// nil are changed. The answer names the changed fields, so the new
    /// preferences have to be read again.
    func updateUserPreferences(_ update: UserPreferencesUpdate) async throws -> PreferencesUpdateResponse {
        let body = try APIJSON.encode(update)
        return try await request(PreferencesUpdateResponse.self, "PATCH", "user/preferences", body: body)
    }

    /// Changes the preferences of the feed: its style and the categories it
    /// leaves out. The answer names the changed fields, so the new
    /// preferences have to be read again.
    func updateFeedPreferences(_ update: FeedPreferencesUpdate) async throws -> PreferencesUpdateResponse {
        let body = try APIJSON.encode(update)
        return try await request(PreferencesUpdateResponse.self, "PATCH", "user/preferences/feed", body: body)
    }

    // MARK: Optional personal data

    /// Stores the shipping address of the account. The values stay on the
    /// server; the account only learns whether there is an address.
    func saveAddress(_ address: AddressInput) async throws -> OptionalInfoUpdateResponse {
        let body = try APIJSON.encode(address)
        return try await request(OptionalInfoUpdateResponse.self, "PUT", "user/address", body: body)
    }

    /// Removes the shipping address of the account.
    func deleteAddress() async throws -> OptionalInfoUpdateResponse {
        try await request(OptionalInfoUpdateResponse.self, "DELETE", "user/address")
    }

    /// Stores the birthday of the account.
    func saveBirthday(_ birthday: BirthdayInput) async throws -> OptionalInfoUpdateResponse {
        let body = try APIJSON.encode(birthday)
        return try await request(OptionalInfoUpdateResponse.self, "PUT", "user/birthday", body: body)
    }

    /// Removes the birthday of the account.
    func deleteBirthday() async throws -> OptionalInfoUpdateResponse {
        try await request(OptionalInfoUpdateResponse.self, "DELETE", "user/birthday")
    }

    /// Stores the mention of the account in the credits.
    func saveCredits(_ credits: CreditsInput) async throws -> OptionalInfoUpdateResponse {
        let body = try APIJSON.encode(credits)
        return try await request(OptionalInfoUpdateResponse.self, "PUT", "user/credits", body: body)
    }

    /// Removes the mention of the account in the credits.
    func deleteCredits() async throws -> OptionalInfoUpdateResponse {
        try await request(OptionalInfoUpdateResponse.self, "DELETE", "user/credits")
    }

    // MARK: Feed marker

    /// Marks the account as looking at the feed and returns the moment the
    /// marker stands at. The marker keeps its value for half an hour.
    func markFeedSeen() async throws -> FeedSeenMarker {
        try await request(FeedSeenMarker.self, "POST", "me/feed/seen")
    }

    // MARK: Legal

    /// Confirms the current version of the terms of use. The version is
    /// chosen by the server.
    func acceptAGB() async throws -> LegalAcceptance {
        try await request(LegalAcceptance.self, "POST", "legal/agb/accept")
    }

    /// Confirms the current version of the privacy terms. The version is
    /// chosen by the server.
    func acceptPrivacyPolicy() async throws -> LegalAcceptance {
        try await request(LegalAcceptance.self, "POST", "legal/privacy/accept")
    }
}
