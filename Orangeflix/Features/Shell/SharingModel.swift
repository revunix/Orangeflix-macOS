import Foundation
import Observation

/// The sharing links of the account: the quota of the month, the links that
/// exist and the link that was created last.
@MainActor @Observable final class SharingModel {
    @ObservationIgnored let app: AppModel

    /// The tier eligibility and the quota of the month.
    private(set) var limit: SharingLimit?
    /// The links of the account.
    private(set) var links: [SharingLinkEntry] = []
    /// The link that was created last; the interface offers it to copy.
    private(set) var freshLink: SharingLink?
    /// Whether the data is being loaded.
    private(set) var isLoading = false
    /// The error of the last attempt.
    private(set) var error: String?

    init(app: AppModel) {
        self.app = app
    }

    /// Whether the account may create sharing links at all.
    var isEligible: Bool { limit?.eligible ?? false }

    /// The links that may still be created this month; nil when no limit
    /// applies.
    var remaining: Int? { limit?.remaining }

    /// Whether the account may create another link right now.
    var canCreate: Bool {
        guard isEligible else { return false }
        guard let remaining else { return true }
        return remaining > 0
    }

    /// The quota as a text for the interface.
    var quotaText: String {
        guard let limit else { return "—" }
        guard let monthly = limit.monthlyLimit else {
            return "Stufe \(limit.tier) · ohne monatliches Limit"
        }
        let left = limit.remaining.map(String.init) ?? "0"
        return "Stufe \(limit.tier) · \(limit.used) von \(monthly) benutzt · \(left) übrig"
    }

    /// Loads the quota and the links of the account.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            async let quota = app.services.api.sharingLimit()
            async let list = app.services.api.sharingLinks()
            limit = try await quota
            links = try await list
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Sharing-Links konnten nicht geladen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Creates a sharing link for an episode; nil when the server refused it.
    @discardableResult
    func create(for clipID: String) async -> SharingLink? {
        do {
            try await app.ensureSession()
            let link = try await app.services.api.createSharingLink(clipID: clipID)
            freshLink = link
            error = nil
            // The quota and the list changed.
            await load()
            app.show("Der Link zum Teilen ist bereit.")
            return link
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
            return nil
        }
    }

    /// Ends a sharing link that was not used yet.
    func revoke(_ code: String) async {
        do {
            try await app.ensureSession()
            try await app.services.api.revokeSharingLink(code: code)
            error = nil
            await load()
            app.show("Der Link ist beendet.")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }

    /// Checks a sharing code without an account: it names the episode and
    /// says how many views are left.
    func inspect(code: String) async -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let resolution = try await app.services.api.resolveSharingCode(trimmed)
            guard !resolution.clipId.isEmpty else { return "Der Code ist unbekannt." }
            let validation = try await app.services.api.validateSharingCode(trimmed, clipID: resolution.clipId)
            guard validation.valid else {
                return validation.problem?.text ?? "Der Code ist nicht gültig."
            }
            if let remaining = validation.remaining {
                return "Der Code ist gültig, \(remaining) Aufrufe übrig (Folge \(resolution.clipId))."
            }
            return "Der Code ist gültig (Folge \(resolution.clipId))."
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Takes the link that was created last out of the way.
    func dismissFreshLink() {
        freshLink = nil
    }
}
