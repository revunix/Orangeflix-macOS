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
    /// The name the account shows, as the server stored it.
    private(set) var savedName = ""
    /// The name in the chat, as the server stored it.
    private(set) var savedChatname = ""
    /// The confirmations the server still wants. It names them itself, so
    /// they are truer than the flags in the profile.
    private(set) var pendingActions: [UiAction] = []
    /// Whether the server named the confirmations at least once.
    private(set) var knowsActions = false
    /// The account the state belongs to; a new account clears it.
    @ObservationIgnored private var loadedGeneration: Int?
    /// The feed filter the user asked for while it is on its way to the
    /// server; nil when the server has the last word.
    private(set) var wantedExclusionFilter: FeedExclusionFilter?
    /// Whether the feed filter is being sent.
    @ObservationIgnored private var isSendingFilter = false
    /// The last change in the line; the next one waits for it.
    @ObservationIgnored private var lastChange: Task<Bool, Never>?

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

    /// Whether the state is missing or belongs to another account.
    var needsLoad: Bool {
        preferences == nil || loadedGeneration != app.accountGeneration
    }

    /// The categories the main feed leaves out: what the user just chose,
    /// else what the server stored.
    var exclusionFilter: FeedExclusionFilter {
        wantedExclusionFilter ?? preferences?.exclusionFilter ?? [:]
    }

    /// Loads the preferences of the account.
    func load() async {
        guard !isLoading else { return }
        // A new account clears the old state first.
        if loadedGeneration != app.accountGeneration {
            loadedGeneration = app.accountGeneration
            preferences = nil
            optionalInfo = OptionalInfoStatus()
            marker = nil
            pendingActions = []
            knowsActions = false
            savedName = ""
            savedChatname = ""
            wantedExclusionFilter = nil
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
        if !profile.chatname.isEmpty { savedChatname = profile.chatname }
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

    /// Leaves one category of a format out of the main feed, or takes it
    /// back in. The switch shows the choice at once; several quick choices
    /// reach the server as one filter, none is lost.
    func setCategory(_ subpid: Int, of pid: Int, excluded: Bool) async {
        var filter = exclusionFilter
        var categories = filter[pid] ?? []
        if excluded {
            if !categories.contains(subpid) { categories.append(subpid) }
        } else {
            categories.removeAll { $0 == subpid }
        }
        filter[pid] = categories.isEmpty ? nil : categories
        wantedExclusionFilter = filter
        await sendExclusionFilter()
    }

    /// Empties the categories the main feed leaves out.
    func clearExclusionFilter() async {
        wantedExclusionFilter = [:]
        await sendExclusionFilter()
    }

    /// Sends the wanted feed filter until the server has the newest one. A
    /// choice made while one is on its way is sent right after it. The
    /// switches themselves say that it worked, so no message follows.
    private func sendExclusionFilter() async {
        guard !isSendingFilter else { return }
        isSendingFilter = true
        defer { isSendingFilter = false }
        while let wanted = wantedExclusionFilter {
            let update = FeedPreferencesUpdate(exclusionFilter: wanted.isEmpty ? .clear : .set(wanted))
            let stored = await change(nil) {
                _ = try await self.app.services.api.updateFeedPreferences(update)
            }
            // A refused filter goes back to what the server has.
            if !stored || wantedExclusionFilter == wanted { wantedExclusionFilter = nil }
        }
    }

    /// Sends a change of the preferences of the feed. The answer of the
    /// server names the changed fields, not the new preferences, so they are
    /// read again.
    private func applyFeedChange(_ update: FeedPreferencesUpdate) async {
        await change("Die Einstellungen sind gespeichert.") {
            _ = try await self.app.services.api.updateFeedPreferences(update)
        }
    }

    /// Changes the name the account shows. Only a name the server took
    /// counts as saved; a refused one can be sent again.
    func setName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stored = await change("Der Name ist gespeichert.") {
            _ = try await self.app.services.api.updateUserPreferences(UserPreferencesUpdate(name: trimmed))
        }
        if stored { savedName = trimmed }
    }

    /// Changes the name in the chat. The server holds a cooldown of a day and
    /// refuses names that are taken; a refused name is not kept as saved.
    func setChatname(_ chatname: String) async {
        let trimmed = chatname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stored = await change("Der Chatname ist gespeichert.") {
            _ = try await self.app.services.api.updateUserPreferences(UserPreferencesUpdate(chatname: trimmed))
        }
        if stored { savedChatname = trimmed }
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

    /// Sends a change to the server and reads the new state; true when the
    /// server took it. The changes go one after another: one that comes
    /// while another is on its way waits for it instead of being dropped.
    /// `text` is the message of the success; nil shows none.
    @discardableResult
    private func change(_ text: String?, _ body: @escaping () async throws -> Void) async -> Bool {
        let previous = lastChange
        let task = Task { [weak self] () -> Bool in
            _ = await previous?.value
            return await self?.perform(text, body) ?? false
        }
        lastChange = task
        let stored = await task.value
        if lastChange == task { lastChange = nil }
        return stored
    }

    /// One change: the server alone knows what it stored, so the account
    /// and the preferences are read again.
    private func perform(_ text: String?, _ body: () async throws -> Void) async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await body()
            try await readPreferences()
            if let text {
                message = text
                app.show(text)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
            return false
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
