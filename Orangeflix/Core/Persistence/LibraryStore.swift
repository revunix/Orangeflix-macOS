import Foundation
import SQLite3
import os

/// The SQLite backed application state: settings, the library of formats,
/// the episode history used to detect new episodes, and the formats the user
/// has opened. Port of the Go `internal/store`; the schema is identical, so a
/// library.db written by the CLI opens unchanged and vice versa.
actor LibraryStore {
    /// The schema of the Go store, verbatim.
    static let schema = """
    CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS formats (
        pid        INTEGER PRIMARY KEY,
        slug       TEXT NOT NULL DEFAULT '' UNIQUE,
        title      TEXT NOT NULL DEFAULT '',
        status     TEXT NOT NULL DEFAULT '',
        enabled    INTEGER NOT NULL DEFAULT 1,
        added_at   TEXT NOT NULL,
        checked_at TEXT,
        new_count  INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS episodes (
        pid           INTEGER NOT NULL,
        identifier    TEXT NOT NULL,
        number        INTEGER NOT NULL DEFAULT 0,
        title         TEXT NOT NULL DEFAULT '',
        date          TEXT NOT NULL DEFAULT '',
        first_seen    TEXT NOT NULL,
        downloaded_at TEXT,
        path          TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (pid, identifier)
    );
    CREATE INDEX IF NOT EXISTS episodes_open ON episodes(pid, downloaded_at);
    CREATE TABLE IF NOT EXISTS opened (
        pid       INTEGER PRIMARY KEY,
        opened_at TEXT NOT NULL
    );
    """

    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "persistence")

    /// The database file.
    let url: URL
    private let db: SQLiteDatabase

    /// Application Support/Orangeflix/library.db (inside the sandbox
    /// container when sandboxed).
    static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("Orangeflix", isDirectory: true)
            .appendingPathComponent("library.db", isDirectory: false)
    }

    /// Opens (and creates) the database at `url`; nil opens `defaultURL()`.
    /// Creates the parent folder (0700), the schema, and makes the file 0600.
    init(url: URL? = nil) throws {
        let target = try url ?? Self.defaultURL()
        guard target.isFileURL, !target.path.isEmpty else { throw PersistenceError.noDatabasePath }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: target.path)
        try db.setBusyTimeout(5000)
        try db.executeScript("PRAGMA foreign_keys = ON")
        // WAL keeps a reader from blocking a writer. The CLI and the app can
        // open the same library.db, and a plain rollback journal makes one of
        // them wait for the other. `synchronous = NORMAL` is safe with WAL and
        // avoids an fsync per write.
        try db.executeScript("PRAGMA journal_mode = WAL")
        try db.executeScript("PRAGMA synchronous = NORMAL")
        do {
            try db.executeScript(Self.schema)
        } catch {
            db.close()
            throw error
        }
        // The database holds the library and the username, so keep it private.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        self.url = target
        self.db = db
        Self.logger.debug("Bibliothek geöffnet: \(target.path, privacy: .private)")
    }

    /// Writes a consistent copy of the library to `target` (export for the
    /// CLI or as a backup). SQLite writes the copy into the container first;
    /// the file the user picked only receives the finished database.
    func exportDatabase(to target: URL) throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
            .appendingPathComponent("library-export-\(UUID().uuidString).db", isDirectory: false)
        defer { try? manager.removeItem(at: temporary) }
        try db.execute("VACUUM INTO ?", [.text(temporary.path)])
        if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
        try manager.copyItem(at: temporary, to: target)
    }

    /// Copies a library.db the user picked (for example the one of the CLI)
    /// to `destination` (default `defaultURL()`), replacing its content. The
    /// source is opened read-only and never modified; the caller must hold
    /// security-scoped access to it. Open the result with `init(url:)`.
    static func importDatabase(from source: URL, to destination: URL? = nil) throws {
        let target = try destination ?? defaultURL()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let input = try SQLiteDatabase(path: source.path, create: false, readOnly: true)
        defer { input.close() }
        // Fails early on a file that is not a SQLite database.
        _ = try input.query("SELECT count(*) FROM sqlite_master") { $0.int(0) }
        let output = try SQLiteDatabase(path: target.path)
        defer { output.close() }
        try output.setBusyTimeout(5000)
        try output.restore(from: input)
        // Missing tables of an older file are created.
        try output.executeScript(schema)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    /// Closes the database; further calls throw.
    func close() { db.close() }

    // MARK: Settings

    /// A stored setting, or "" when it is not set.
    func setting(_ key: String) throws -> String {
        try db.query("SELECT value FROM settings WHERE key = ?", [.text(key)]) { $0.text(0) }.first ?? ""
    }

    /// Stores a setting; an empty value removes it.
    func setSetting(_ key: String, _ value: String) throws {
        if value.isEmpty {
            try db.execute("DELETE FROM settings WHERE key = ?", [.text(key)])
            return
        }
        try db.execute("""
            INSERT INTO settings(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, [.text(key), .text(value)])
    }

    // MARK: Formats

    /// Adds a format to the library or updates slug, title and status (empty
    /// values keep the stored ones). The enabled flag and the check history
    /// are kept.
    func upsertFormat(pid: Int, slug: String, title: String, status: String) throws {
        guard pid > 0 else { throw PersistenceError.noFormatID }
        try db.execute("""
            INSERT INTO formats(pid, slug, title, status, added_at) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(pid) DO UPDATE SET
                slug  = CASE WHEN excluded.slug  != '' THEN excluded.slug  ELSE formats.slug  END,
                title = CASE WHEN excluded.title != '' THEN excluded.title ELSE formats.title END,
                status = CASE WHEN excluded.status != '' THEN excluded.status ELSE formats.status END
            """, [.int(pid), .text(slug), .text(title), .text(status), .text(LibraryTimestamp.now())])
    }

    /// The library, ordered by title (case-insensitive), then id.
    func formats() throws -> [LibraryFormat] {
        try db.query("""
            SELECT pid, slug, title, status, enabled, added_at, checked_at,
                new_count, last_error FROM formats ORDER BY title COLLATE NOCASE, pid
            """) { row in
            LibraryFormat(
                pid: row.int(0), slug: row.text(1), title: row.text(2), status: row.text(3),
                enabled: row.int(4) != 0, addedAt: LibraryTimestamp.parse(row.text(5)),
                checkedAt: LibraryTimestamp.parse(row.text(6)), newCount: row.int(7),
                lastError: row.text(8))
        }
    }

    /// One format of the library, nil when it is not in the library.
    func format(pid: Int) throws -> LibraryFormat? {
        try formats().first { $0.pid == pid }
    }

    /// Deletes a format of the library. Like the Go store, the episode
    /// history of the format is kept (there is no foreign key); call
    /// `clearEpisodes(pid:)` to drop it too.
    func removeFormat(pid: Int) throws {
        try db.execute("DELETE FROM formats WHERE pid = ?", [.int(pid)])
    }

    /// Toggles whether a format is checked and downloaded.
    func setFormatEnabled(pid: Int, _ enabled: Bool) throws {
        try db.execute("UPDATE formats SET enabled = ? WHERE pid = ?", [.int(enabled ? 1 : 0), .int(pid)])
    }

    /// Stores the result of the last new-episode check.
    func recordCheck(pid: Int, newCount: Int, lastError: String) throws {
        try db.execute(
            "UPDATE formats SET checked_at = ?, new_count = ?, last_error = ? WHERE pid = ?",
            [.text(LibraryTimestamp.now()), .int(newCount), .text(lastError), .int(pid)])
    }

    // MARK: Opened formats

    /// Remembers that the user has been in a format.
    func markOpened(pid: Int) throws {
        try db.execute("""
            INSERT INTO opened (pid, opened_at) VALUES (?, ?)
            ON CONFLICT(pid) DO UPDATE SET opened_at = excluded.opened_at
            """, [.int(pid), .text(LibraryTimestamp.now())])
    }

    /// The formats the user has already been in.
    func openedFormats() throws -> Set<Int> {
        Set(try db.query("SELECT pid FROM opened") { $0.int(0) })
    }

    // MARK: Episodes

    /// Stores the episodes the API currently reports (in one transaction) and
    /// returns the ones that were not known before, in input order. Episodes
    /// without identifier are skipped; known ones get number, title and date
    /// updated.
    func syncEpisodes(pid: Int, _ episodes: [LibraryEpisodeRef]) throws -> [LibraryEpisodeRef] {
        try db.transaction {
            let known = Set(try db.query("SELECT identifier FROM episodes WHERE pid = ?", [.int(pid)]) { $0.text(0) })
            var fresh: [LibraryEpisodeRef] = []
            let stamp = LibraryTimestamp.now()
            for episode in episodes where !episode.identifier.isEmpty {
                let date = episode.date.map(LibraryTimestamp.format) ?? ""
                try db.execute("""
                    INSERT INTO episodes(pid, identifier, number, title, date, first_seen)
                    VALUES(?, ?, ?, ?, ?, ?)
                    ON CONFLICT(pid, identifier) DO UPDATE SET
                        number = excluded.number, title = excluded.title, date = excluded.date
                    """, [.int(pid), .text(episode.identifier), .int(episode.number),
                          .text(episode.title), .text(date), .text(stamp)])
                if !known.contains(episode.identifier) {
                    fresh.append(episode)
                }
            }
            return fresh
        }
    }

    private static let episodeColumns =
        "SELECT identifier, number, title, date, first_seen, downloaded_at, path FROM episodes"

    private static func knownEpisode(_ row: SQLiteDatabase.Row) -> LibraryEpisode {
        LibraryEpisode(
            episode: LibraryEpisodeRef(
                identifier: row.text(0), number: row.int(1), title: row.text(2),
                date: LibraryTimestamp.parse(row.text(3))),
            firstSeen: LibraryTimestamp.parse(row.text(4)),
            downloadedAt: LibraryTimestamp.parse(row.text(5)),
            path: row.text(6))
    }

    /// The stored episodes that were not downloaded yet, highest number first.
    func pending(pid: Int) throws -> [LibraryEpisode] {
        try db.query(
            Self.episodeColumns + " WHERE pid = ? AND downloaded_at IS NULL ORDER BY number DESC",
            [.int(pid)], row: Self.knownEpisode)
    }

    /// Every stored episode of one format, highest number first.
    func episodes(pid: Int) throws -> [LibraryEpisode] {
        try db.query(Self.episodeColumns + " WHERE pid = ? ORDER BY number DESC", [.int(pid)], row: Self.knownEpisode)
    }

    /// The identifiers of the known episodes of one format.
    func knownIdentifiers(pid: Int) throws -> Set<String> {
        Set(try db.query("SELECT identifier FROM episodes WHERE pid = ?", [.int(pid)]) { $0.text(0) })
    }

    /// Counts the episodes that are known but not downloaded.
    func countPending(pid: Int) throws -> Int {
        try db.query("SELECT COUNT(*) FROM episodes WHERE pid = ? AND downloaded_at IS NULL", [.int(pid)]) {
            $0.int(0)
        }.first ?? 0
    }

    /// Records that one episode was downloaded and where the file ended up;
    /// returns how many rows changed (0 when the library does not know the
    /// episode).
    @discardableResult
    func markDownloaded(pid: Int, identifier: String, path: String) throws -> Int {
        try db.execute(
            "UPDATE episodes SET downloaded_at = ?, path = ? WHERE pid = ? AND identifier = ?",
            [.text(LibraryTimestamp.now()), .text(path), .int(pid), .text(identifier)])
        return db.changes
    }

    /// Forgets that one episode was downloaded, so it is offered again. The
    /// stored path is kept, like in Go.
    func clearDownloaded(pid: Int, identifier: String) throws {
        try db.execute(
            "UPDATE episodes SET downloaded_at = NULL WHERE pid = ? AND identifier = ?",
            [.int(pid), .text(identifier)])
    }

    /// Forgets the history of one format, so every episode is offered again.
    func clearEpisodes(pid: Int) throws {
        try db.execute("DELETE FROM episodes WHERE pid = ?", [.int(pid)])
    }
}
