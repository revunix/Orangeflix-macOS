import Foundation
import Observation

/// The preferences of the account, the optional personal data and the legal
/// confirmations.
@MainActor @Observable final class ProfileModel {
    @ObservationIgnored let app: AppModel

    /// The preferences of the account.
    private(set) var preferences: UserPreferences?
    /// The state of the personal data, as the account answer names it. It is
    /// the account answer and not the preferences that know what the account
    /// stored.
    private(set) var optionalInfo = OptionalInfoStatus()
    /// The marker that says until when the account has seen the feed.
    private(set) var marker: FeedSeenMarker?
    /// Whether the data is being loaded.
    private(set) var isLoading = false
    /// Whether a change is being sent.
    private(set) var isSaving = false
    /// The error of the last attempt.
    private(set) var error: String?
    /// The message of the last successful change.
    private(set) var message: String?
    /// The name the account showed the last time it was set; the server
    /// does not give the name back.
    private(set) var savedName = ""
    /// The name in the chat the last time it was set.
    private(set) var savedChatname = ""
    /// The confirmations the server still wants. It names them itself, so
    /// they are truer than the flags in the profile.
    private(set) var pendingActions: [UiAction] = []
    /// Whether the server named the confirmations at least once.
    private(set) var knowsActions = false
    /// The account the state belongs to; a new account clears it.
    @ObservationIgnored private var loadedGeneration: Int?

    init(app: AppModel) {
        self.app = app
    }

    /// The German name of a style of the main feed.
    static func feedStyleName(_ style: Int) -> String {
        switch style {
        case 1: "Kompakt"
        case 2: "Mittel"
        case 3: "Groß"
        default: "Unbekannt"
        }
    }

    /// The state of the legal confirmations, as the profile names them.
    var privacy: PrivacyStatus { preferences?.privacy ?? PrivacyStatus() }

    /// Whether the terms of use are confirmed. The server names the open
    /// confirmations itself; those win over the flags in the profile.
    var agbConfirmed: Bool {
        if knowsActions { return !pendingActions.contains { $0.type == "accept_agb" } }
        return privacy.acceptedAgb2
    }

    /// Whether the privacy terms are confirmed.
    var privacyConfirmed: Bool {
        if knowsActions { return !pendingActions.contains { $0.type == "accept_privacy" } }
        return privacy.acceptedPrivacy1 && privacy.acceptedPrivacy2
    }

    /// Whether the server still wants a confirmation.
    var needsLegalConfirmation: Bool { !agbConfirmed || !privacyConfirmed }

    /// The confirmations that are still open, with their German names.
    var openActionTitles: [String] {
        let actions = knowsActions ? pendingActions : []
        return actions.filter(\.required).map { action in
            switch action.type {
            case "accept_agb": "AGB"
            case "accept_privacy": "Datenschutz"
            default: action.type
            }
        }
    }

    /// Loads the preferences of the account.
    func load() async {
        guard !isLoading else { return }
        // A new account clears the old state first.
        if loadedGeneration != app.accountGeneration {
            loadedGeneration = app.accountGeneration
            preferences = nil
            optionalInfo = OptionalInfoStatus()
            pendingActions = []
            knowsActions = false
            savedName = ""
            savedChatname = ""
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            try await readPreferences()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Einstellungen des Kontos konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Reads the state of the account from the server. The account answer
    /// knows what the account stored (the personal data) and how it is
    /// called; the preferences answer knows the settings and the
    /// confirmations. Every change reads both again.
    private func readPreferences() async throws {
        async let preferences = app.services.api.userPreferences()
        async let account = app.services.api.profile()
        self.preferences = try await preferences
        let profile = try await account
        optionalInfo = profile.optionalInfo
        if !profile.name.isEmpty { savedName = profile.name }
        // The login names the open confirmations. They are only taken over
        // when nothing frescher is known; a confirmation names them again.
        if !knowsActions {
            let named = await app.services.api.pendingActions
            if !named.isEmpty {
                pendingActions = named
                knowsActions = true
            }
        }
    }

    // MARK: Preferences

    /// Changes the style of the main feed (1…3).
    func setFeedStyle(_ style: Int) async {
        await applyFeedChange(FeedPreferencesUpdate(feedStyle: style))
    }

    /// Changes the categories the main feed leaves out.
    func setExclusionFilter(_ filter: FeedExclusionFilter) async {
        await applyFeedChange(FeedPreferencesUpdate(exclusionFilter: .set(filter)))
    }

    /// Empties the categories the main feed leaves out.
    func clearExclusionFilter() async {
        await applyFeedChange(FeedPreferencesUpdate(exclusionFilter: .clear))
    }

    /// Sends a change of the preferences of the feed. The answer of the
    /// server names the changed fields, not the new preferences, so they are
    /// read again.
    private func applyFeedChange(_ update: FeedPreferencesUpdate) async {
        await change("Die Einstellungen sind gespeichert.") {
            _ = try await self.app.services.api.updateFeedPreferences(update)
        }
    }

    /// Changes the name the account shows.
    func setName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await change("Der Name ist gespeichert.") {
            _ = try await self.app.services.api.updateUserPreferences(UserPreferencesUpdate(name: trimmed))
        }
        savedName = trimmed
    }

    /// Changes the name in the chat. The server holds a cooldown of a day and
    /// refuses names that are taken.
    func setChatname(_ chatname: String) async {
        let trimmed = chatname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await change("Der Chatname ist gespeichert.") {
            _ = try await self.app.services.api.updateUserPreferences(UserPreferencesUpdate(chatname: trimmed))
        }
        savedChatname = trimmed
    }

    // MARK: Optional personal data

    /// Stores the shipping address of the account.
    func saveAddress(_ address: AddressInput) async {
        await change("Die Adresse ist gespeichert.") {
            _ = try await self.app.services.api.saveAddress(address)
        }
    }

    /// Removes the shipping address of the account.
    func deleteAddress() async {
        await change("Die Adresse ist entfernt.") {
            _ = try await self.app.services.api.deleteAddress()
        }
    }

    /// Stores the birthday of the account.
    func saveBirthday(_ birthday: BirthdayInput) async {
        await change("Das Geburtsdatum ist gespeichert.") {
            _ = try await self.app.services.api.saveBirthday(birthday)
        }
    }

    /// Removes the birthday of the account.
    func deleteBirthday() async {
        await change("Das Geburtsdatum ist entfernt.") {
            _ = try await self.app.services.api.deleteBirthday()
        }
    }

    /// Stores the mention of the account in the credits.
    func saveCredits(_ credits: CreditsInput) async {
        await change("Der Credits-Eintrag ist gespeichert.") {
            _ = try await self.app.services.api.saveCredits(credits)
        }
    }

    /// Removes the mention of the account in the credits.
    func deleteCredits() async {
        await change("Der Credits-Eintrag ist entfernt.") {
            _ = try await self.app.services.api.deleteCredits()
        }
    }

    /// Sends a change to the server and reads the new state. The server
    /// alone knows what it stored, so the account and the preferences are
    /// read again.
    private func change(_ text: String, _ body: () async throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await body()
            try await readPreferences()
            message = text
            app.show(text)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    // MARK: Legal

    /// Confirms the current version of the terms of use.
    func acceptAGB() async {
        await acceptLegal { try await self.app.services.api.acceptAGB() }
    }

    /// Confirms the current version of the privacy terms.
    func acceptPrivacy() async {
        await acceptLegal { try await self.app.services.api.acceptPrivacyPolicy() }
    }

    /// Sends a confirmation and takes over the confirmations the server
    /// names afterwards.
    private func acceptLegal(_ body: () async throws -> LegalAcceptance) async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let answer = try await body()
            // The server names the confirmations that are still open.
            pendingActions = answer.uiActions.filter(\.required)
            knowsActions = true
            try await readPreferences()
            if pendingActions.isEmpty {
                message = answer.message.isEmpty ? "Die Bestätigung ist beim Server angekommen." : answer.message
            } else {
                message = "Der Server verlangt noch: \(openActionTitles.joined(separator: ", "))."
            }
            app.show(message ?? "")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    // MARK: Feed marker

    /// Marks the account as looking at the feed.
    func markFeedSeen() async {
        do {
            marker = try await app.services.api.markFeedSeen()
            error = nil
            message = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }
}
