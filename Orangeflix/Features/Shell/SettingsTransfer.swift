import Foundation

/// Import and export of the settings page: the backup of the app settings,
/// the settings file of the command line tool (`~/.config/orangeflix-dl/config`)
/// and the library database (`library.db`).
@MainActor
enum SettingsTransfer {
    /// The errors of import and export (German).
    enum TransferError: LocalizedError {
        case noSettings
        case notABackup
        case notADatabase(String)

        var errorDescription: String? {
            switch self {
            case .noSettings: "Die Datei enthält keine bekannten Einstellungen."
            case .notABackup: "Die Datei ist keine Einstellungssicherung von Orangeflix."
            case .notADatabase(let reason): "Die Datei ist keine Bibliothek (library.db): \(reason)"
            }
        }
    }

    /// What an import changed.
    struct Result {
        /// The names of the changed settings.
        var applied: [String] = []
        /// The names of the settings the file asked for but that were not
        /// taken over.
        var rejected: [String] = []
        /// Notes for the user, for example about the download folder.
        var notes: [String] = []

        /// The text of the import summary.
        var summary: String {
            var parts: [String] = []
            if !applied.isEmpty { parts.append("Übernommen: " + applied.joined(separator: ", ")) }
            if !rejected.isEmpty { parts.append("Nicht übernommen: " + rejected.joined(separator: ", ")) }
            parts.append(contentsOf: notes)
            return parts.isEmpty ? "Es wurde nichts geändert." : parts.joined(separator: "\n")
        }
    }

    /// The German names of the settings the CLI file carries.
    private static let configNames = [
        "quality": "Qualität", "layout": "Ablage", "submodule": "Feed-Variante", "parallel": "Gleichzeitig",
        "delay": "Pause", "limit": "Tempolimit", "thumb": "Vorschaubild", "meta": "Metadaten",
    ]

    // MARK: Backup of the app

    /// The file of a backup: the settings with a marker, so a foreign JSON
    /// file is not taken for one.
    private struct Backup: Codable {
        static let kind = "orangeflix-settings"
        var format = Backup.kind
        var version = 1
        var exportedAt = Date()
        var settings: AppSettings
    }

    /// The suggested name of a backup file.
    static var backupFileName: String {
        let day = Date().formatted(.iso8601.year().month().day())
        return "Orangeflix-Einstellungen-\(day).json"
    }

    /// Writes all settings, the themes and the choice of formats. The login
    /// stays out: it never leaves the Mac.
    static func exportBackup(_ settings: AppSettings, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var exported = settings
        // Which episodes were already announced is the state of this Mac.
        exported.announcedEpisodes = [:]
        try encoder.encode(Backup(settings: exported)).write(to: url, options: .atomic)
    }

    /// Replaces the settings with the ones of a backup. The record of the
    /// announced episodes stays the one of this Mac.
    static func importBackup(from url: URL, into app: AppModel) throws -> Result {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let backup = try? decoder.decode(Backup.self, from: data),
              backup.format == Backup.kind else {
            throw TransferError.notABackup
        }
        var next = backup.settings
        next.announcedEpisodes = app.settings.announcedEpisodes
        try app.updateSettings { $0 = next }
        var result = Result()
        result.applied = ["alle Einstellungen"]
        if !next.importedThemes.isEmpty {
            result.applied.append(next.importedThemes.count == 1 ? "1 Theme" : "\(next.importedThemes.count) Themes")
        }
        result.notes.append("Speicherort und Anmeldung bleiben, wie sie sind.")
        return result
    }

    // MARK: Settings file of the CLI

    /// The settings of the app as a `config` of the command line tool:
    /// `key=value` lines that Go `LoadConfigFile` and `ConfigFile.parse` read.
    static func configText(_ settings: AppSettings, date: Date = Date()) -> String {
        var lines = [
            "# orangeflix-dl – exportiert aus Orangeflix für macOS am \(date.formatted(.iso8601.year().month().day()))",
            "quality=\(settings.quality.rawValue)",
            "layout=\(settings.layout.rawValue)",
            "submodule=\(settings.submodule)",
            "parallel=\(settings.parallel)",
            "delay=\(AppSettings.formatDelay(settings.delay))",
        ]
        // 0 means "no cap"; the tool knows no value for it.
        if settings.limitKiB > 0 { lines.append("limit=\(settings.limitKiB)") }
        lines.append("thumb=\(settings.thumb)")
        lines.append("meta=\(settings.meta)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func exportConfig(_ settings: AppSettings, to url: URL) throws {
        try Data(configText(settings).utf8).write(to: url, options: .atomic)
    }

    /// Applies the values of a CLI settings file to the app settings (Go
    /// `Resolve` with the range checks of `AppSettings.applying`). The
    /// settings are written through `AppModel.updateSettings`, so an invalid
    /// value is reported and nothing is stored.
    static func applyConfig(_ values: ConfigFileValues, to app: AppModel) throws -> Result {
        guard !isEmpty(values) else { throw TransferError.noSettings }
        let previous = app.settings
        let (next, rejected) = previous.applying(values)
        try app.updateSettings { $0 = next }
        var result = Result()
        result.rejected = rejected.map { configNames[$0] ?? $0 }
        let changes: [(String, Bool)] = [
            ("quality", previous.quality != next.quality), ("layout", previous.layout != next.layout),
            ("submodule", previous.submodule != next.submodule), ("parallel", previous.parallel != next.parallel),
            ("delay", previous.delay != next.delay), ("limit", previous.limitKiB != next.limitKiB),
            ("thumb", previous.thumb != next.thumb), ("meta", previous.meta != next.meta),
        ]
        result.applied = changes.filter(\.1).map { configNames[$0.0] ?? $0.0 }
        if !values.downloadsDir.isEmpty {
            result.notes.append(
                "Der Speicherort „\(values.downloadsDir)“ wurde nicht übernommen; "
                + "die App darf nur selbst gewählte Ordner benutzen. Bitte unter „Speicherort“ wählen.")
        }
        return result
    }

    /// Whether the file carries no known setting at all.
    static func isEmpty(_ values: ConfigFileValues) -> Bool {
        values.quality.isEmpty && values.layout.isEmpty && values.submodule == 0 && values.parallel == 0
            && values.delay == 0 && values.limit == 0 && !values.thumb && !values.meta
            && values.downloadsDir.isEmpty
    }

    // MARK: Library database

    /// The file the imported library waits in before it replaces the library
    /// of the app.
    static func stagingURL() throws -> URL {
        try LibraryStore.defaultURL().deletingLastPathComponent()
            .appendingPathComponent("library-import.db", isDirectory: false)
    }

    /// The library that an import replaced; it can be put back.
    static func backupURL() throws -> URL {
        try LibraryStore.defaultURL().deletingLastPathComponent()
            .appendingPathComponent("library.db.sicherung", isDirectory: false)
    }

    /// The time of the kept library, nil when there is none.
    static func previousLibraryDate() -> Date? {
        guard let url = try? backupURL(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    /// Copies a library into the staging file. The source is only read; a
    /// file that is not a SQLite database is rejected.
    static func stageLibrary(from source: URL) throws -> URL {
        let staging = try stagingURL()
        try? FileManager.default.removeItem(at: staging)
        do {
            try LibraryStore.importDatabase(from: source, to: staging)
        } catch {
            throw TransferError.notADatabase(error.localizedDescription)
        }
        return staging
    }

    /// Puts the staged library in place of the library of the app. The
    /// previous library is kept as backup, so putting the backup back swaps
    /// the two; the app has to be restarted, because the running app still
    /// reads the old file.
    static func activateLibrary(staging: URL) throws {
        let live = try LibraryStore.defaultURL()
        let backup = try backupURL()
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let target = URL(fileURLWithPath: backup.path + suffix)
            try? manager.removeItem(at: target)
            let current = URL(fileURLWithPath: live.path + suffix)
            guard manager.fileExists(atPath: current.path) else { continue }
            try manager.moveItem(at: current, to: target)
        }
        try manager.moveItem(at: staging, to: live)
    }
}
