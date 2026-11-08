import Foundation

/// The download state an episode row shows (TUI `episodeState`).
enum BrowseEpisodeBadge: Hashable, Sendable {
    case downloaded
    case watched
    case progress(Int)
    case new
    case open

    var label: String {
        switch self {
        case .downloaded: "heruntergeladen"
        case .watched: "gesehen"
        case .progress(let percent): "▶ \(percent) %"
        case .new: "neu"
        case .open: "offen"
        }
    }
}

/// One year of the episode list (TUI `episodeGroup`).
struct BrowseYearGroup: Identifiable, Hashable, Sendable {
    /// "2026", or "unbekannt" without a date.
    var year: String
    var episodes: [Episode]
    var loaded: Int

    var id: String { year }
    /// "2026 · 12 Folgen · 3 geladen"
    var header: String { "\(year) · \(episodes.count) Folgen · \(loaded) geladen" }
}

/// One status group of the formats list.
struct BrowseFormatGroup: Identifiable, Hashable, Sendable {
    var status: FormatStatus
    var formats: [Format]

    var id: String { status.rawValue }
    /// "AKTIV", "SAISONAL", "ARCHIVIERT" (TUI `statusLabel`).
    var label: String {
        switch status {
        case .active: "AKTIV"
        case .seasonal: "SAISONAL"
        case .archived: "ARCHIVIERT"
        default: status.rawValue
        }
    }
}

/// The pure rules of the formats and episode lists, ported from Go
/// `internal/app/v3.go` and `internal/tui` (panels.go, model.go, quality.go).
enum BrowseLogic {
    /// Days in which an episode counts as new (Go `NewEpisodeDays`).
    static let newEpisodeDays = 7
    /// The share from which an episode counts as watched (TUI `watchedPercent`).
    static let watchedPercent = 90

    // MARK: Catalog (Go app.Formats)

    /// The static catalog marked with the opened state and the age of the
    /// last episode (Go `markStaticCatalog`).
    static func staticCatalog(opened: Set<Int>, now: Date = Date()) -> [Format] {
        markFormats(FormatCatalog.all, opened: opened, now: now)
    }

    /// Merges the live catalog into the program's catalog: the API brings the
    /// dates and clip counts, the program keeps slug, status and description;
    /// unknown magazines are appended (Go `Formats`).
    static func mergeCatalog(_ magazines: [Magazine], opened: Set<Int>, now: Date = Date()) -> [Format] {
        var formats = FormatCatalog.all
        guard !magazines.isEmpty else { return markFormats(formats, opened: opened, now: now) }
        var place: [Int: Int] = [:]
        for (index, format) in formats.enumerated() { place[format.pid] = index }
        for magazine in magazines {
            var format = magazineFormat(magazine, now: now)
            if let index = place[magazine.pid] {
                let known = formats[index]
                if !known.slug.isEmpty { format.slug = known.slug }
                if !known.status.rawValue.isEmpty { format.status = known.status }
                format.description = known.description
                if format.lastEpisodeTime == nil {
                    format.lastEpisode = known.lastEpisode
                    format.lastEpisodeTime = known.lastEpisodeTime
                }
                formats[index] = format
                continue
            }
            formats.append(format)
        }
        return markFormats(formats, opened: opened, now: now)
    }

    /// Sets `opened` and `newEpisode` (Go `markFormats`).
    static func markFormats(_ formats: [Format], opened: Set<Int>, now: Date = Date()) -> [Format] {
        formats.map { format in
            var format = format
            format.opened = opened.contains(format.pid)
            format.newEpisode = isNewEpisode(format.lastEpisodeTime, now: now)
            return format
        }
    }

    /// A format of the live catalog (Go `magazineFormat`).
    static func magazineFormat(_ magazine: Magazine, now: Date = Date()) -> Format {
        var format = Format(
            pid: magazine.pid, slug: formatSlug(magazine), title: magazine.title,
            status: magazine.active ? .active : .archived, clipCount: magazine.clipCount,
            logo: magazine.artwork.logo,
            cover: magazine.artwork.logoSquare,
            coverDark: magazine.artwork.logoSquareDark,
            banner: magazine.artwork.banner.twoX.isEmpty ? magazine.artwork.banner.oneX : magazine.artwork.banner.twoX,
            original: magazine.original, handle: magazine.handle)
        if let moment = magazineLastEpisode(magazine, now: now) {
            format.lastEpisodeTime = moment
            format.lastEpisode = localDayFormatter.string(from: moment)
        }
        return format
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The date of the newest episode from `timeRange.max` (seconds, or
    /// milliseconds); values before 2000 or more than a year ahead are
    /// ignored (Go `magazineLastEpisode`).
    static func magazineLastEpisode(_ magazine: Magazine, now: Date = Date()) -> Date? {
        var value = magazine.timeRange.max
        guard value > 0 else { return nil }
        if value > 1_000_000_000_000 { value /= 1000 }
        let moment = Date(timeIntervalSince1970: TimeInterval(value))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard calendar.component(.year, from: moment) >= 2000,
              let limit = calendar.date(byAdding: .year, value: 1, to: now),
              moment <= limit else { return nil }
        return moment
    }

    /// Whether an episode of that date counts as new: at most seven days old,
    /// or in the future (Go `isNewEpisode`).
    static func isNewEpisode(_ moment: Date?, now: Date = Date()) -> Bool {
        guard let moment else { return false }
        let age = now.timeIntervalSince(moment)
        if age < 0 { return true }
        return age <= TimeInterval(newEpisodeDays * 24 * 3600)
    }

    /// The slug of a magazine: the catalog's, else derived from the title
    /// (Go `formatSlug`).
    static func formatSlug(_ magazine: Magazine) -> String {
        if let format = FormatCatalog.format(pid: magazine.pid) { return format.slug }
        var slug = ""
        for character in magazine.title.lowercased().unicodeScalars {
            switch character {
            case "a"..."z", "0"..."9": slug.unicodeScalars.append(character)
            case "ä", "ö", "ü": slug.append("a")
            case "ß": slug.append("s")
            case " ", "-", "_": slug.append("-")
            default: break
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "format-\(magazine.pid)" : trimmed
    }

    // MARK: Formats list (TUI formatGroups)

    /// The formats grouped by status in the catalog order, filtered by title
    /// or slug (case-insensitive) and optionally by the library, each group
    /// sorted by the last episode.
    static func formatGroups(_ formats: [Format], filter: String, libraryPIDs: Set<Int>?) -> [BrowseFormatGroup] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let (order, grouped) = FormatCatalog.groupByStatus(formats)
        var groups: [BrowseFormatGroup] = []
        for status in order {
            let matching = (grouped[status] ?? []).filter { format in
                if !needle.isEmpty, !format.title.lowercased().contains(needle), !format.slug.lowercased().contains(needle) {
                    return false
                }
                if let libraryPIDs, !libraryPIDs.contains(format.pid) { return false }
                return true
            }
            if matching.isEmpty { continue }
            groups.append(BrowseFormatGroup(status: status, formats: sortedByLastEpisode(matching)))
        }
        return groups
    }

    /// Newest last episode first; undated formats last, by title (TUI
    /// `sortFormatsByLastEpisode`, stable).
    static func sortedByLastEpisode(_ formats: [Format]) -> [Format] {
        formats.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            switch (a.lastEpisodeTime, b.lastEpisodeTime) {
            case (nil, nil):
                if a.title != b.title { return a.title < b.title }
            case (nil, _): return false
            case (_, nil): return true
            case let (aTime?, bTime?):
                if aTime != bTime { return aTime > bTime }
                if a.title != b.title { return a.title < b.title }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: Episodes

    /// Newest episode: latest date, on the same date the higher number
    /// (Go `NewestEpisode`). A missing date counts as the zero time.
    static func newestEpisode(_ episodes: [Episode]) -> Episode? {
        guard var newest = episodes.first else { return nil }
        for episode in episodes.dropFirst() {
            let date = episode.date ?? .distantPast
            let newestDate = newest.date ?? .distantPast
            if date > newestDate || (date == newestDate && episode.number > newest.number) {
                newest = episode
            }
        }
        return newest
    }

    /// Reads "00:31:52" or "31:52" as seconds; 0 when unreadable (Go
    /// `clockToSeconds`).
    static func clockToSeconds(_ value: String) -> Int {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return 0 }
        var total = 0
        for part in parts {
            guard let number = Int(part), number >= 0 else { return 0 }
            total = total * 60 + number
        }
        return total
    }

    /// The year of an episode for the groups and the filter, "unbekannt"
    /// without a date.
    static func year(of episode: Episode) -> String {
        guard let date = episode.date else { return "unbekannt" }
        return String(Calendar.current.component(.year, from: date))
    }

    /// The list order: newest date first, undated last, the higher number
    /// breaks ties; the source is walked from the end like the TUI
    /// (`filteredEpisodes` + `sortEpisodesByDate`). `year` filters by the
    /// four-digit year.
    static func filteredEpisodes(_ episodes: [Episode], year: String?) -> [Episode] {
        let reversed = episodes.reversed().filter { episode in
            guard let year, !year.isEmpty else { return true }
            return episode.date != nil && Self.year(of: episode) == year
        }
        return reversed.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            switch (a.date, b.date) {
            case (nil, nil): break
            case (nil, _): return false
            case (_, nil): return true
            case let (aDate?, bDate?):
                if aDate != bDate { return aDate > bDate }
            }
            if a.number != b.number { return a.number > b.number }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Groups the ordered episodes by year in order of appearance (TUI
    /// `episodeGroups`).
    static func yearGroups(_ ordered: [Episode], isLoaded: (Episode) -> Bool) -> [BrowseYearGroup] {
        var groups: [BrowseYearGroup] = []
        var index: [String: Int] = [:]
        for episode in ordered {
            let year = year(of: episode)
            let position: Int
            if let existing = index[year] {
                position = existing
            } else {
                position = groups.count
                index[year] = position
                groups.append(BrowseYearGroup(year: year, episodes: [], loaded: 0))
            }
            groups[position].episodes.append(episode)
            if isLoaded(episode) { groups[position].loaded += 1 }
        }
        return groups
    }

    /// The years present in the list, newest first (for the year filter).
    static func years(_ episodes: [Episode]) -> [String] {
        Array(Set(episodes.compactMap { $0.date == nil ? nil : year(of: $0) })).sorted(by: >)
    }

    /// The badge in priority order: downloaded, watched (≥ 90 %), progress,
    /// new (first seen < 7 days ago and not downloaded), open (TUI
    /// `episodeState`).
    static func badge(downloaded: Bool, progress: Int, firstSeen: Date?, now: Date = Date()) -> BrowseEpisodeBadge {
        if downloaded { return .downloaded }
        if progress > 0 {
            return progress >= watchedPercent ? .watched : .progress(progress)
        }
        if let firstSeen, now.timeIntervalSince(firstSeen) < TimeInterval(newEpisodeDays * 24 * 3600) {
            return .new
        }
        return .open
    }

    /// The program's quality name of a file description (TUI `qualityName`):
    /// "HD 1080…" → hd, "HD 720…" → mobile, "SD…" → sd, "Audio…" → audio,
    /// anything else unchanged.
    static func qualityName(_ desc: String) -> String {
        if desc.hasPrefix("HD 1080") { return AppSettings.Quality.hd.rawValue }
        if desc.hasPrefix("HD 720") { return AppSettings.Quality.mobile.rawValue }
        if desc.hasPrefix("SD") { return AppSettings.Quality.sd.rawValue }
        if desc.hasPrefix("Audio") { return AppSettings.Quality.audio.rawValue }
        return desc
    }

    /// The menu title of an episode (TUI `episodeTitle`): the title, else
    /// the format name.
    static func title(of episode: Episode) -> String {
        episode.title.isEmpty ? episode.formatName : episode.title
    }
}
