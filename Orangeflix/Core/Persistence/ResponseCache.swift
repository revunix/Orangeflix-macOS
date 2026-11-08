import CryptoKit
import Foundation
import os

/// How long an answer may be served from `ResponseCache`.
enum CacheTTL {
    /// The catalog of the formats.
    static let catalog: TimeInterval = 900
    /// One page of the feed and the list of episodes of a format.
    static let episodes: TimeInterval = 1_800
    /// Guest details and archive pages used by the guest directory.
    static let guestDirectory: TimeInterval = 7 * 24 * 60 * 60
    /// The list of the most recently watched clips.
    static let recents: TimeInterval = 300
    /// The bookmarks of the account.
    static let bookmarks: TimeInterval = 300
    /// The calendar entries.
    static let calendar: TimeInterval = 1_800
    /// The alerts and campaigns.
    static let announcements: TimeInterval = 1_800
    /// The state of the livestream; short, the live dot must not lag behind.
    static let live: TimeInterval = 45
    /// The clip page, which carries chapters and the picture track.
    static let clipPage: TimeInterval = 43_200
}

/// The persisted answers of the API, so a start and a change of the section
/// show content without a request.
///
/// The file is owned by the app (`Application Support/Orangeflix/cache.db`);
/// keys start with the scope of the account so two accounts never read each
/// other's answers.
actor ResponseCache {
    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "cache")

    /// Bodies larger than this are not stored; the biggest feed page stays
    /// below it.
    static let maxBodyBytes = 4 << 20
    /// Entries older than this are dropped on open.
    static let maxAge: TimeInterval = 30 * 86_400

    /// The schema of the cache, verbatim.
    static let schema = """
    CREATE TABLE IF NOT EXISTS responses (
        key       TEXT PRIMARY KEY,
        body      BLOB NOT NULL,
        stored_at REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS responses_age ON responses(stored_at);
    """

    /// The database file.
    let url: URL
    private let db: SQLiteDatabase

    /// Application Support/Orangeflix/cache.db (inside the sandbox container
    /// when sandboxed).
    static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("Orangeflix", isDirectory: true)
            .appendingPathComponent("cache.db", isDirectory: false)
    }

    /// The prefix of the keys of one account: 16 hex characters of the hash
    /// of the lowercased name, `anon` for an empty one.
    static func scope(_ account: String) -> String {
        let name = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return "anon" }
        let digest = SHA256.hash(data: Data(name.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// Opens (and creates) the cache at `url`; nil opens `defaultURL()`.
    /// Creates the parent folder (0700), the schema, and makes the file 0600.
    init(url: URL? = nil) throws {
        let target = try url ?? Self.defaultURL()
        guard target.isFileURL, !target.path.isEmpty else { throw PersistenceError.noDatabasePath }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: target.path)
        try db.setBusyTimeout(5000)
        do {
            try db.executeScript("PRAGMA journal_mode = WAL")
            try db.executeScript("PRAGMA synchronous = NORMAL")
            try db.executeScript(Self.schema)
        } catch {
            db.close()
            throw error
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        self.url = target
        self.db = db
        // `init` of an actor is nonisolated, so the pruning runs inline.
        do {
            try db.execute("DELETE FROM responses WHERE stored_at < ?",
                           [.double(Date().addingTimeInterval(-Self.maxAge).timeIntervalSince1970)])
        } catch {
            Self.logger.error("Cache nicht bereinigt: \(error.localizedDescription, privacy: .public)")
        }
        Self.logger.debug("Antwort-Cache geöffnet: \(target.path, privacy: .private)")
    }

    /// The stored answer and the time it was written.
    func value(for key: String) -> (body: Data, storedAt: Date)? {
        do {
            let rows = try db.query("SELECT body, stored_at FROM responses WHERE key = ?", [.text(key)]) {
                (body: $0.blob(0), storedAt: $0.double(1))
            }
            guard let row = rows.first else { return nil }
            return (row.body, Date(timeIntervalSince1970: row.storedAt))
        } catch {
            Self.logger.error("Cache nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes one answer; a body above `maxBodyBytes` is not stored, and an
    /// empty one removes the entry.
    func store(_ body: Data, for key: String, at date: Date = Date()) {
        guard body.count <= Self.maxBodyBytes else {
            Self.logger.notice("Antwort zu groß für den Cache (\(body.count) Bytes): \(key, privacy: .public)")
            return
        }
        guard !body.isEmpty else {
            remove(key)
            return
        }
        do {
            try db.execute("""
                INSERT INTO responses(key, body, stored_at) VALUES(?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET body = excluded.body, stored_at = excluded.stored_at
                """, [.text(key), .blob(body), .double(date.timeIntervalSince1970)])
        } catch {
            Self.logger.error("Antwort nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops one answer.
    func remove(_ key: String) {
        do {
            try db.execute("DELETE FROM responses WHERE key = ?", [.text(key)])
        } catch {
            Self.logger.error("Antwort nicht gelöscht: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops every answer whose key starts with `prefix` (the lists of one
    /// path after a change).
    func remove(prefix: String) {
        guard !prefix.isEmpty else { return }
        do {
            try db.execute("DELETE FROM responses WHERE substr(key, 1, ?) = ?",
                           [.int(prefix.utf16.count), .text(prefix)])
        } catch {
            Self.logger.error("Antworten nicht gelöscht: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops every answer (an account change).
    func removeAll() {
        do {
            try db.execute("DELETE FROM responses")
        } catch {
            Self.logger.error("Cache nicht geleert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the answers older than `age`.
    func prune(olderThan age: TimeInterval) {
        do {
            try db.execute("DELETE FROM responses WHERE stored_at < ?",
                           [.double(Date().addingTimeInterval(-age).timeIntervalSince1970)])
        } catch {
            Self.logger.error("Cache nicht bereinigt: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Closes the database; further calls fail.
    func close() { db.close() }
}
