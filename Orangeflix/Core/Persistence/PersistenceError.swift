import Foundation
import Security

/// Errors of the persistence module (library database, keychain, settings,
/// download folder bookmark).
enum PersistenceError: LocalizedError, Sendable, Equatable {
    /// No database location was given.
    case noDatabasePath
    /// A format id ≤ 0 was passed to `upsertFormat`.
    case noFormatID
    /// SQLite reported an error; `code` is the extended result code.
    case sqlite(code: Int32, message: String)
    /// The keychain reported an error.
    case keychain(status: OSStatus, message: String)
    /// A keychain item holds data that is not UTF-8 text.
    case keychainData
    /// A setting value is out of range; the payload is the German message.
    case invalidSetting(String)
    /// No download folder bookmark is stored.
    case noBookmark
    /// The stored bookmark could not be resolved or created.
    case bookmark(String)
    /// The sandbox refused access to the bookmarked folder.
    case accessDenied(String)
    /// The path exists but is not a directory.
    case notDirectory(String)
    /// The folder cannot be written.
    case notWritable(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noDatabasePath:
            return "Kein Pfad für die Datenbank angegeben."
        case .noFormatID:
            return "Keine Format-ID angegeben."
        case let .sqlite(code, message):
            return "Datenbankfehler \(code): \(message)"
        case let .keychain(status, message):
            if status == errSecDuplicateItem {
                return "Der Eintrag im Schlüsselbund existiert schon (\(status)): \(message)"
            }
            return "Schlüsselbund-Fehler \(status): \(message)"
        case .keychainData:
            return "Der Eintrag im Schlüsselbund ist kein lesbarer Text."
        case let .invalidSetting(message):
            return message
        case .noBookmark:
            return "Es ist kein Download-Ordner gespeichert."
        case let .bookmark(message):
            return "Das Lesezeichen des Download-Ordners ist ungültig: \(message)"
        case let .accessDenied(path):
            return "Kein Zugriff auf den Ordner \(path). Bitte den Ordner erneut auswählen."
        case let .notDirectory(path):
            return "\(path) ist kein Ordner."
        case let .notWritable(path, reason):
            return "Der Ordner \(path) ist nicht beschreibbar: \(reason)"
        }
    }
}
