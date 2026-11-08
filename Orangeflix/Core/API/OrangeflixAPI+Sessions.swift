import Foundation

/// The session endpoints. They read and end the sessions of the account; the
/// server only allows them with the short-lived recovery token that comes
/// with a login that was refused because the account has too many sessions.
extension OrangeflixAPI {
    /// The sessions of the account.
    func sessions(recoveryToken: String) async throws -> [AccountSession] {
        let data = try await send(token: recoveryToken, method: "GET",
                                  path: "auth/session-recovery/sessions")
        return try APIJSON.decode(SessionList.self, from: data).sessions
    }

    /// Ends one session of the account. The recovery token may only end the
    /// sessions it belongs to.
    func revokeSession(_ sessionID: String, recoveryToken: String) async throws {
        _ = try await send(token: recoveryToken, method: "DELETE",
                           path: "auth/session-recovery/sessions/" + APIHTTP.pathEscape(sessionID))
    }
}
