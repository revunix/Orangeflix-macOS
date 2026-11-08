import Foundation

// Port of internal/media/naming.go: the Orangeflix output naming and the path
// sanitizing that keeps the API values inside the download directory.
//
// The default layout is the one of the JavaScript downloader, so that files
// that were downloaded before are recognised and skipped:
//
//     <Series>.S2026.German.AAC.DOKU.1080p.Web-DL.x264/
//         <Series>.S2026E420.German.AAC.DOKU.1080p.Web-DL.x264/
//             <Series>.S2026E420.German.AAC.DOKU.1080p.Web-DL.x264.mp4

/// The directory layout of the downloads.
enum MediaLayout: String, Sendable, Hashable, Codable, CaseIterable {
    /// Keeps the structure of the JavaScript downloader (one folder per
    /// episode, quality tag in every name).
    case compat
    /// Stores the episodes directly in the series folder.
    case flat

    /// Converts a layout name into a layout; the empty name is `compat`.
    static func parse(_ name: String) throws(DownloadError) -> MediaLayout {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "compat": return .compat
        case "flat": return .flat
        default: throw .unknownLayout(name)
        }
    }
}

/// One episode and the names it gets on disk.
struct MediaNaming: Sendable, Hashable, Codable {
    /// The name of the format.
    var title: String
    /// The year of the episode.
    var year: Int
    /// The episode number.
    var number: Int
    /// The resolution label of the file ("1080p"); empty means "1080p".
    var resolution: String
    /// The directory layout.
    var layout: MediaLayout

    init(title: String, year: Int, number: Int, resolution: String = "", layout: MediaLayout = .compat) {
        self.title = title
        self.year = year
        self.number = number
        self.resolution = resolution
        self.layout = layout
    }

    /// Builds the naming of an episode from its metadata, like `namingFor`
    /// of the Go app: the title falls back from the format title to the
    /// format name of the episode to the slug; the year is the UTC year of
    /// the publication date (0 without a date). The resolution is not known
    /// before the clip was loaded, so it stays empty and is filled in later.
    init(formatTitle: String, episodeFormatName: String, formatSlug: String, published: Date?, number: Int, layout: MediaLayout) {
        var title = formatTitle
        if title.isEmpty { title = episodeFormatName }
        if title.isEmpty { title = formatSlug }
        var year = 0
        if let published {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
            year = calendar.component(.year, from: published)
        }
        self.init(title: title, year: year, number: number, resolution: "", layout: layout)
    }

    // MARK: Validation (rules of the JavaScript downloader)

    /// The earliest year a file name may carry.
    static let minYear = 2000
    /// The number of digits an episode number may have.
    static let maxEpisodeDigits = 6

    /// Checks the title of a format.
    static func validateTitle(_ title: String) throws(DownloadError) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .invalidNaming("ungültiger Serientitel: ein nicht leerer Text wird erwartet")
        }
    }

    /// Checks the year of an episode; it may lie at most one year in the
    /// future.
    static func validateYear(_ year: Int, now: Date = Date()) throws(DownloadError) {
        let maxYear = Calendar(identifier: .gregorian).component(.year, from: now) + 1
        if year < minYear || year > maxYear {
            throw .invalidNaming("ungültiges Jahr: \(year) (erwartet wird eine Jahreszahl zwischen \(minYear) und \(maxYear))")
        }
    }

    /// Checks the number of an episode.
    static func validateEpisodeNumber(_ number: Int) throws(DownloadError) {
        if number < 1 {
            throw .invalidNaming("ungültige Episodennummer: \(number) (erwartet wird eine Zahl ab 1)")
        }
        if String(number).count > maxEpisodeDigits {
            throw .invalidNaming("ungültige Episodennummer: \(number) (erwartet werden höchstens \(maxEpisodeDigits) Ziffern)")
        }
    }

    /// Checks title, year and number.
    func validate(now: Date = Date()) throws(DownloadError) {
        try Self.validateTitle(title)
        try Self.validateYear(year, now: now)
        try Self.validateEpisodeNumber(number)
    }

    // MARK: Names

    /// The part that follows the title in the names of the compatible layout.
    var suffix: String {
        "German.AAC.DOKU.\(resolution.isEmpty ? "1080p" : resolution).Web-DL.x264"
    }

    /// The name of the series folder without the quality.
    var seriesPrefix: String {
        "\(Self.sanitizeTitle(title)).S\(year)"
    }

    /// The name of the episode without the quality; the number is padded to
    /// three digits.
    var episodePrefix: String {
        var digits = String(number)
        while digits.count < 3 { digits = "0" + digits }
        return "\(Self.sanitizeTitle(title)).S\(year)E\(digits)"
    }

    /// The folder that holds the episodes of the format and the year.
    var seriesFolder: String {
        layout == .flat ? seriesPrefix : seriesPrefix + "." + suffix
    }

    /// The name of the episode file without the extension.
    var episodeName: String {
        layout == .flat ? episodePrefix : episodePrefix + "." + suffix
    }

    /// The folder that holds the episode file.
    var episodeFolder: String {
        layout == .flat ? seriesFolder : episodeName
    }

    /// The directory of the episode relative to the download root, with "/"
    /// separators.
    var relativeDirectory: String {
        layout == .flat ? seriesFolder : seriesFolder + "/" + episodeFolder
    }

    /// The file of the episode relative to the download root. The empty
    /// extension means ".mp4"; a missing dot is added.
    func relativeFile(extension fileExtension: String) -> String {
        var ext = fileExtension.isEmpty ? ".mp4" : fileExtension
        if !ext.hasPrefix(".") { ext = "." + ext }
        return relativeDirectory + "/" + episodeName + ext
    }

    /// The glob patterns that match an already downloaded episode. They end
    /// before the quality, so an episode counts as downloaded in any
    /// quality, and both layouts are covered.
    var globs: [String] {
        var compat = self
        compat.layout = .compat
        var flat = self
        flat.layout = .flat
        return [
            compat.seriesPrefix + ".*/" + compat.episodePrefix + ".*/" + compat.episodePrefix + ".*",
            flat.seriesPrefix + "/" + flat.episodePrefix + ".*",
        ]
    }

    // MARK: Sanitizing

    /// Keeps the letters and digits of a title (Unicode categories L* and
    /// Nd, per scalar like Go's runes) and replaces every other character
    /// with a dot; runs of dots collapse, leading and trailing dots are
    /// trimmed, the empty result becomes "_". The result is a single path
    /// component of at most 170 UTF-8 bytes.
    static func sanitizeTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        var lastWasDot = false
        for scalar in title.unicodeScalars {
            if isLetterOrDigit(scalar) {
                scalars.append(scalar)
                lastWasDot = false
            } else if !lastWasDot {
                scalars.append(".")
                lastWasDot = true
            }
        }
        while scalars.first == "." { scalars.removeFirst() }
        while scalars.last == "." { scalars.removeLast() }
        return capComponentBytes(170, scalars.isEmpty ? "_" : String(scalars))
    }

    /// Truncates `s` so its UTF-8 length stays within `max` bytes, always on
    /// a scalar boundary.
    static func capComponentBytes(_ max: Int, _ s: String) -> String {
        if s.utf8.count <= max { return s }
        var scalars = String.UnicodeScalarView()
        var length = 0
        for scalar in s.unicodeScalars {
            let size = scalar.utf8.count
            if length + size > max { break }
            scalars.append(scalar)
            length += size
        }
        return String(scalars)
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }
}
