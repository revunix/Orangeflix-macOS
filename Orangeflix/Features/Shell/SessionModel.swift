import Foundation
import Observation

/// The sessions of the account. The server only lets them be read and ended
/// with the short-lived recovery token, which comes with a login that was
/// refused because the account has too many sessions.
@MainActor @Observable final class SessionModel {
    @ObservationIgnored let app: AppModel

    /// The sessions of the account.
    private(set) var sessions: [AccountSession] = []
    /// Whether the list is being read.
    private(set) var isLoading = false
    /// The error of the last attempt.
    private(set) var error: String?

    init(app: AppModel) {
        self.app = app
    }

    /// Reads the sessions of the account.
    func load(recovery: SessionRecovery) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            sessions = try await app.services.api.sessions(recoveryToken: recovery.token)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.record("Die Sitzungen konnten nicht gelesen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Ends one session of the account.
    func revoke(_ sessionID: String, recovery: SessionRecovery) async {
        do {
            try await app.services.api.revokeSession(sessionID, recoveryToken: recovery.token)
            error = nil
            sessions.removeAll { $0.id == sessionID }
            app.show("Die Sitzung ist beendet.")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            app.show(error.localizedDescription, error: true)
        }
    }
}
