import Foundation

/// Failures of the download module. `isRetryable` mirrors the Go
/// `retryableError` marker: a new try (continuing the partial file) could
/// finish the download.
///
/// Cancellation is not part of this enum: a cancelled download throws
/// `CancellationError`, and the partial file stays for the next run.
enum DownloadError: LocalizedError, Sendable, Hashable {
    /// No target file was given.
    case noTarget
    /// The transfer delivered no data for the stall timeout.
    case stalled
    /// The connection broke or could not be established.
    case transport(String)
    /// The server rejected the credentials (HTTP 401).
    case unauthorized
    /// The server answered a resume with a range that does not fit the
    /// partial file; the partial file was removed.
    case resumeRejected
    /// The partial file is longer than the file on the server (HTTP 416);
    /// the partial file was removed.
    case partialFileMismatch
    /// The server answered with an unexpected status code.
    case httpStatus(Int)
    /// The transfer ended before the announced size was reached.
    case incomplete(written: Int64, total: Int64)
    /// The checksum of the file does not match the announced one; the
    /// partial file was removed.
    case checksumMismatch
    /// The server redirected more often than allowed.
    case tooManyRedirects
    /// The URL cannot be loaded over HTTP(S).
    case invalidURL(String)
    /// A file system operation failed.
    case fileSystem(String)
    /// The directory of the target file cannot be created.
    case directoryNotWritable(String)
    /// The naming of an episode is invalid (title, year or number).
    case invalidNaming(String)
    /// The layout name is unknown.
    case unknownLayout(String)
    /// The download source of an episode could not be determined.
    case sourceUnavailable(id: String, reason: String)
    /// A download of the queue failed; wraps the reason.
    case downloadFailed(id: String, reason: String)

    /// Whether a new try could finish the download.
    var isRetryable: Bool {
        switch self {
        case .stalled, .transport, .resumeRejected, .partialFileMismatch, .incomplete:
            return true
        case .httpStatus(let code):
            return code >= 500 || code == 429
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .noTarget:
            return "Keine Zieldatei angegeben."
        case .stalled:
            return "Der Download ist fehlgeschlagen: Der Server sendet keine Daten mehr."
        case .transport(let reason):
            return "Der Download ist fehlgeschlagen: \(reason)"
        case .unauthorized:
            return "Anmeldung fehlgeschlagen (HTTP 401): ungültige Zugangsdaten."
        case .resumeRejected:
            return "Der Server hat die Fortsetzung des Downloads abgelehnt."
        case .partialFileMismatch:
            return "Die Teildatei passt nicht zur Datei auf dem Server."
        case .httpStatus(let code):
            return "HTTP \(code)"
        case .incomplete(let written, let total):
            return "Der Download ist unvollständig: \(written) von \(total) Bytes."
        case .checksumMismatch:
            return "Die Prüfsumme stimmt nicht mit der des Servers überein."
        case .tooManyRedirects:
            return "Zu viele Weiterleitungen."
        case .invalidURL(let url):
            return "Ungültige Download-URL: \(url)"
        case .fileSystem(let reason):
            return "Dateifehler: \(reason)"
        case .directoryNotWritable(let path):
            return "Das Verzeichnis ist nicht beschreibbar: \(path)"
        case .invalidNaming(let reason):
            return reason
        case .unknownLayout(let name):
            return "Unbekanntes Layout: \(name) (erlaubt: compat, flat)"
        case .sourceUnavailable(let id, let reason):
            return "Die Metadaten von \(id) konnten nicht geladen werden: \(reason)"
        case .downloadFailed(let id, let reason):
            return "Der Download von \(id) ist fehlgeschlagen: \(reason)"
        }
    }
}
