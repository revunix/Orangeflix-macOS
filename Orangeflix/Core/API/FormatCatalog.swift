import Foundation

/// The formats known to the program. The numeric id is all the API needs;
/// title, status and description are for the display, so a format missing
/// here still works with its id. Generated from the Go catalog.
enum FormatCatalog {
    /// The known formats in catalog order.
    static let all: [Format] = [
        entry(1, "fktv", "Fernsehkritik-TV", .archived, "2018-09-02", "Die ursprüngliche Fernsehkritik von Holger Kreymeier"),
        entry(2, "pantoffeltv", "Pantoffelkino", .active, "2026-10-09", "Das Heimkino-Magazin mit Holger Kreymeier"),
        entry(3, "presseschlau", "Pressesch(l)au", .archived, "2024-12-31", "Satirischer Rundumschlag durch die Printmedien"),
        entry(4, "paschtv", "Pasch-TV", .archived, "2026-10-07", "Gaming, Nerd-Kultur und Let's Plays"),
        entry(5, "netzprediger", "Netzprediger", .archived, "2018-01-27", "Internet-Kultur und digitale Trends"),
        entry(6, "asynchron", "Asynchron", .archived, "2018-08-14", "Film- und Serienbesprechungen zu zweit"),
        entry(7, "tonangeber", "TonAngeber", .archived, "2018-06-30", "Musik und Audio-Kultur"),
        entry(8, "hoaxillatv", "Hoaxilla-TV", .archived, "2018-09-27", "Skeptiker-Magazin zu Verschwörungstheorien und Mythen"),
        entry(9, "sakura", "Sakura", .archived, "2020-02-18", "Anime- und Manga-Kultur"),
        entry(10, "migropolis", "Migropolis", .archived, "2015-12-29", "Reportagen zu Migration und Gesellschaft"),
        entry(11, "serienkiller", "Serienkiller", .archived, "2018-06-26", "TV-Serien-Kritik und Analyse"),
        entry(12, "vorzelt", "Das Vorzelt zur Hölle", .archived, "2016-07-20", "Festival- und Event-Kultur mit Lars"),
        entry(13, "jung", "Jung & Anders", .archived, "2016-11-08", "Jugendkultur und gesellschaftliche Themen"),
        entry(14, "interaktiv", "Interaktiv", .archived, "2018-09-17", "Community-Formate und Mitmach-Sendungen"),
        entry(15, "sprechplanet", "Sprechplanet", .archived, "2023-04-04", "Sprache, Kommunikation und Podcast-Kultur"),
        entry(16, "geisterjaeger", "Die Geisterjäger", .archived, "2016-12-02", "Paranormale Phänomene und Mysterien"),
        entry(17, "comictalk", "Der ComicTalk", .archived, "2025-07-03", "Comics und Graphic Novels"),
        entry(18, "moritz", "Moritz und die Anderen", .archived, "2017-07-20", "Gespräche und Porträts"),
        entry(19, "veto", "Veto", .active, "2026-10-05", "Politische Diskussionen und Meinungen"),
        entry(20, "achtungspoiler", "Achtung Spoiler!", .archived, "2018-04-19", "Film- und Serienbesprechungen mit Spoilern"),
        entry(21, "offensio", "Offensio", .archived, "2018-03-09", "Kontroverse Meinungen und Streitgespräche"),
        entry(22, "schatzkammer", "Schatzkammer", .active, "2026-09-11", "Kurioses und Fundstücke aus dem Netz"),
        entry(23, "mediatheke", "Die Mediatheke", .archived, "2026-10-10", "Das wöchentliche Medienmagazin (2026 nach Folge 420 beendet)"),
        entry(24, "trip", "Trip", .archived, "2020-07-28", "Reisen und Abenteuer"),
        entry(25, "sonntagsfruehstueck", "Sonntagsfrühstück", .archived, "2024-01-21", "Entspannte Sonntagsrunden"),
        entry(26, "studio", "Das Studio", .active, "2026-10-04", "Studio-Produktionen und Live-Sendungen"),
        entry(27, "paddysretrokosmos", "Paddys Retrokosmos", .archived, "2025-11-24", "Retro-Kultur und Nostalgie"),
        entry(28, "studioplus", "Das Studio (Plus)", .archived, "2024-12-26", "Erweiterte Studio-Inhalte"),
        entry(29, "massengeschnack", "Massengeschnack", .active, "2026-10-05", "Kulinarische Themen und Essen"),
        entry(30, "livekommentar", "Livekommentar", .active, "2026-09-21", "Live-Kommentare zu aktuellen Ereignissen"),
        entry(31, "adventskalender", "Adventskalender", .seasonal, "2025-12-24", "Weihnachtliches Spezial-Format (jedes Jahr im Dezember)"),
        entry(32, "kayraydarfalles", "Kay Ray darf alles", .archived, "2024-02-19", "Kay Ray kommentiert das Weltgeschehen"),
        entry(33, "wortezummontag", "Wort(e) zum Montag", .archived, "2024-06-03", "Der Wochenrückblick zum Start in die Woche"),
        entry(34, "xstream", "XStream", .archived, "2022-05-04", "Streaming und Online-Medien"),
        entry(35, "sommerkalender", "Sommerkalender", .seasonal, "2026-07-08", "Sommerliches Spezial-Format"),
        entry(36, "zeitgeist", "ZeitGeist", .archived, "2026-09-29", "Aktuelle gesellschaftliche Trends"),
        entry(37, "gelbesessel", "Der Gelbe Sessel", .archived, "2024-03-06", "Gemütliche Gesprächsrunden"),
        entry(38, "imgespraech", "iMGespräch", .archived, "2026-09-01", "Tiefgehende Interviews und Diskussionen"),
        entry(39, "youtubetwitch", "Youtube & Twitch", .active, "2026-10-05", "Social Media und Streaming-Plattformen"),
        entry(40, "wissenistolli", "Wissen ist Olli", .active, "2026-09-21", "Bildung und Wissensvermittlung"),
        entry(41, "roadtoglory", "Road to Glory", .active, "2026-10-12", "Sport und Wettkampf"),
        entry(42, "monatsblutung", "Monatsblutung", .archived, "2023-12-04", "Monatliche Zusammenfassungen"),
        entry(43, "aufnahmestudio", "MG Aufnahmestudio", .active, "2026-10-01", "Produktions-Einblicke und Making-Of"),
        entry(44, "karton", "Jetzt kommt ein Karton", .active, "2026-09-27", "Unboxing und Produkt-Reviews"),
        entry(45, "top10", "TOP 10", .active, "2026-09-14", "Listen und Rankings"),
        entry(46, "maximalmusik", "MAXimal Musik", .active, "2026-10-12", "Musikvideos und Musik-Kultur"),
        entry(47, "schnittshow", "Kay Ray's Schnittshow", .archived, "2024-07-11", "Schnitt- und Medienanalyse"),
        entry(48, "techload", "TechLoad", .active, "2026-10-12", "Technologie und Innovation"),
        entry(49, "zurueckgespult", "Zurückgespult", .active, "2026-10-05", "Retro-Gaming und Nostalgie"),
        entry(50, "ollivsjames", "Olli vs James", .active, "2026-09-20", "Olli und James treten gegeneinander an"),
        entry(51, "kalterschauer", "Kalter Schauer", .archived, "2025-10-31", "Horror und Thriller"),
        entry(52, "frischgepresst", "Frisch gepresst", .active, "2026-10-12", "Neues Live-Format, hat die Mediatheke abgelöst"),
    ]

    private static func entry(_ pid: Int, _ slug: String, _ title: String, _ status: FormatStatus, _ lastEpisode: String, _ description: String) -> Format {
        Format(pid: pid, slug: slug, title: title, status: status, lastEpisode: lastEpisode,
               lastEpisodeTime: parseDay(lastEpisode), description: description)
    }

    /// Parses "2006-01-02" as midnight UTC, like Go's `time.Parse`.
    static func parseDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    /// The catalog entry of a format id.
    static func format(pid: Int) -> Format? {
        all.first { $0.pid == pid }
    }

    /// The catalog entry of a slug, compared case-insensitively.
    static func format(slug: String) -> Format? {
        let lowered = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.slug.lowercased() == lowered }
    }

    /// Resolves a format by its slug, its numeric id or its title. An id that
    /// is not in the catalog is accepted as an active format.
    static func lookup(_ value: String) throws -> Format {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw APIError.noFormat }
        if let format = format(slug: trimmed) { return format }
        if let pid = Int(trimmed) {
            if let format = format(pid: pid) { return format }
            return Format(pid: pid, slug: "format-\(pid)", title: "Format \(pid)", status: .active)
        }
        if let format = all.first(where: { $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return format
        }
        throw APIError.unknownFormat(value)
    }

    /// Groups formats by status. The groups follow the order active,
    /// seasonal, archived; unknown statuses are appended in the order they
    /// appear. Every known group exists, even when it is empty.
    static func groupByStatus(_ formats: [Format]) -> (order: [FormatStatus], groups: [FormatStatus: [Format]]) {
        var order: [FormatStatus] = [.active, .seasonal, .archived]
        var groups: [FormatStatus: [Format]] = [.active: [], .seasonal: [], .archived: []]
        for format in formats {
            if groups[format.status] == nil {
                groups[format.status] = []
                order.append(format.status)
            }
            groups[format.status, default: []].append(format)
        }
        return (order, groups)
    }
}
