import Foundation

/// The errors of the Orangeflix API module.
enum APIError: LocalizedError, Sendable, Equatable {
    /// The v3 API rejected the access token (HTTP 401).
    case unauthorized
    /// The legacy API rejected the user name or the password (HTTP 401).
    case invalidCredentials
    /// The account asks for a second factor. `token` is the short-lived TOTP
    /// token that `completeTotpLogin` needs together with the code.
    case totpRequired(token: String)
    /// The login answered without an access token.
    case loginFailed(String?)
    /// The account has too many sessions, so the login was refused.
    /// `recovery` is the short-lived credential that may list and end the
    /// sessions of the account; it is nil when the server sent none.
    case sessionLimitReached(recovery: SessionRecovery?)
    /// The refresh answered without an access token.
    case refreshFailed(String?)
    /// There is no refresh token to renew the access token with.
    case noRefreshToken
    /// The API answered with an error status; `message` is its reason.
    case http(status: Int, message: String)
    /// The API throttles the requests and the attempts are used up.
    case rateLimited(String)
    /// The request did not reach the API.
    case transport(String)
    /// The answer could not be decoded.
    case decoding(String)
    /// The RSS feed could not be parsed.
    case feedParsing(String)
    /// A URL could not be built or is not allowed.
    case invalidURL(String)
    /// A parameter of the call is invalid.
    case invalidRequest(String)
    /// A clip offers no download file.
    case noFiles(String)
    /// The file list has no video file.
    case noVideoFile
    /// The file list has no file of the quality.
    case noFileForQuality(String)
    /// No format was given.
    case noFormat
    /// The format is unknown.
    case unknownFormat(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Der Zugangstoken wurde abgelehnt (HTTP 401)."
        case .invalidCredentials:
            return "Die Anmeldung ist fehlgeschlagen (HTTP 401): ungültige Zugangsdaten."
        case .totpRequired:
            return "Das Konto verlangt einen zweiten Faktor (TOTP)."
        case .loginFailed(let reason):
            if let reason, !reason.isEmpty { return "Die Anmeldung ist fehlgeschlagen: \(reason)" }
            return "Die Anmeldung ist fehlgeschlagen: die Antwort enthält keinen Zugangstoken."
        case .sessionLimitReached:
            return "Das Konto hat zu viele offene Sitzungen. Eine Sitzung muss beendet werden, bevor die Anmeldung klappt."
        case .refreshFailed(let reason):
            if let reason, !reason.isEmpty { return "Der Token konnte nicht erneuert werden: \(reason)" }
            return "Der Token konnte nicht erneuert werden: die Antwort enthält keinen Zugangstoken."
        case .noRefreshToken:
            return "Es gibt keinen Refresh-Token."
        case .http(let status, let message):
            return message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
        case .rateLimited(let message):
            return message.isEmpty ? "Die API drosselt die Anfragen." : "Die API drosselt die Anfragen: \(message)"
        case .transport(let message):
            return "Die Anfrage ist fehlgeschlagen: \(message)"
        case .decoding(let message):
            return "Die JSON-Antwort konnte nicht gelesen werden: \(message)"
        case .invalidURL(let message):
            return "Ungültige Adresse: \(message)"
        case .feedParsing(let message):
            return "Der RSS-Feed konnte nicht gelesen werden: \(message)"
        case .invalidRequest(let message):
            return message
        case .noFiles(let identifier):
            return "Für \(identifier) gibt es keine Download-Dateien."
        case .noVideoFile:
            return "Es gibt keine Videodatei."
        case .noFileForQuality(let quality):
            return "Für die Qualität „\(quality)“ gibt es keine Datei."
        case .noFormat:
            return "Kein Format angegeben."
        case .unknownFormat(let value):
            return "Unbekanntes Format: \(value)"
        }
    }
}
