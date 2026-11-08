import Foundation
import Testing

@testable import OrangeflixLogic

/// The file naming of the downloads. The names have to stay compatible with
/// the ones the JavaScript downloader wrote, otherwise an episode that is
/// already on disk is downloaded a second time.
@Suite("MediaNaming")
struct MediaNamingTests {

    private func naming(layout: MediaLayout = .compat) -> MediaNaming {
        MediaNaming(title: "Die Anstalt", year: 2026, number: 42, resolution: "1080p", layout: layout)
    }

    // MARK: Sanitizing

    /// Only letters and digits survive; everything else becomes one dot.
    @Test("a title is reduced to letters and digits")
    func sanitizeSimple() {
        #expect(MediaNaming.sanitizeTitle("Die Anstalt") == "Die.Anstalt")
        #expect(MediaNaming.sanitizeTitle("Die  Anstalt") == "Die.Anstalt")
    }

    /// Runs of separators collapse into a single dot, and the edges lose theirs.
    @Test("separator runs collapse and edges are trimmed")
    func sanitizeCollapses() {
        #expect(MediaNaming.sanitizeTitle("  --Die///Anstalt!!  ") == "Die.Anstalt")
        #expect(MediaNaming.sanitizeTitle("...Die...") == "Die")
    }

    /// A title without a usable character becomes an underscore, so no empty
    /// path component is built.
    @Test("an unusable title becomes an underscore")
    func sanitizeEmpty() {
        #expect(MediaNaming.sanitizeTitle("") == "_")
        #expect(MediaNaming.sanitizeTitle("///") == "_")
        #expect(MediaNaming.sanitizeTitle("   ") == "_")
    }

    /// Umlauts and other letters are kept, they are letters.
    @Test("letters outside ASCII are kept")
    func sanitizeUnicode() {
        #expect(MediaNaming.sanitizeTitle("Über Größe") == "Über.Größe")
        #expect(MediaNaming.sanitizeTitle("日本語") == "日本語")
    }

    /// A path separator must never reach the file name.
    @Test("path separators never reach the name")
    func sanitizePathSeparators() {
        let name = MediaNaming.sanitizeTitle("../../etc/passwd")
        #expect(!name.contains("/"))
        #expect(!name.contains(".."))
    }

    /// The result is capped at 170 UTF-8 bytes, cut on a scalar boundary.
    @Test("a long title is capped on a scalar boundary")
    func sanitizeCap() {
        let long = String(repeating: "a", count: 400)
        let capped = MediaNaming.sanitizeTitle(long)
        #expect(capped.utf8.count <= 170)
        #expect(capped.count == 170)
    }

    /// The cap counts bytes, not characters, so a multi-byte title is cut
    /// earlier.
    @Test("the cap counts bytes")
    func sanitizeCapMultiByte() {
        let long = String(repeating: "ä", count: 200)
        let capped = MediaNaming.sanitizeTitle(long)
        #expect(capped.utf8.count <= 170)
        // Every "ä" is two bytes, so at most 85 fit.
        #expect(capped.count <= 85)
    }

    // MARK: Names

    /// The compatible layout puts the quality into every name.
    @Test("the compatible layout keeps the quality in every name")
    func compatLayout() {
        let name = naming()
        #expect(name.seriesFolder == "Die.Anstalt.S2026.German.AAC.DOKU.1080p.Web-DL.x264")
        #expect(name.episodeName == "Die.Anstalt.S2026E042.German.AAC.DOKU.1080p.Web-DL.x264")
        #expect(name.relativeDirectory
            == "Die.Anstalt.S2026.German.AAC.DOKU.1080p.Web-DL.x264/"
             + "Die.Anstalt.S2026E042.German.AAC.DOKU.1080p.Web-DL.x264")
    }

    /// The flat layout keeps the episodes directly in the series folder.
    @Test("the flat layout has no per-episode folder")
    func flatLayout() {
        let name = naming(layout: .flat)
        #expect(name.seriesFolder == "Die.Anstalt.S2026")
        #expect(name.episodeName == "Die.Anstalt.S2026E042")
        #expect(name.relativeDirectory == "Die.Anstalt.S2026")
    }

    /// The episode number is padded to three digits.
    @Test("the episode number is padded to three digits")
    func episodePadding() {
        #expect(MediaNaming(title: "T", year: 2026, number: 7).episodePrefix == "T.S2026E007")
        #expect(MediaNaming(title: "T", year: 2026, number: 42).episodePrefix == "T.S2026E042")
        #expect(MediaNaming(title: "T", year: 2026, number: 1234).episodePrefix == "T.S2026E1234")
    }

    /// An empty resolution is written as 1080p, so an old name still matches.
    @Test("a missing resolution falls back to 1080p")
    func defaultResolution() {
        let name = MediaNaming(title: "T", year: 2026, number: 1, resolution: "")
        #expect(name.suffix.contains("1080p"))
    }

    /// The extension gets its dot, and an empty one means mp4.
    @Test("the extension is normalised")
    func fileExtension() {
        let name = naming()
        #expect(name.relativeFile(extension: "").hasSuffix(".mp4"))
        #expect(name.relativeFile(extension: "mp4").hasSuffix(".mp4"))
        #expect(name.relativeFile(extension: ".mp4").hasSuffix(".mp4"))
        #expect(name.relativeFile(extension: "m4a").hasSuffix(".m4a"))
    }

    /// The file sits in the episode folder of the compatible layout.
    @Test("the file sits in the episode folder")
    func relativeFile() {
        let name = naming()
        let expected = "Die.Anstalt.S2026.German.AAC.DOKU.1080p.Web-DL.x264/"
            + "Die.Anstalt.S2026E042.German.AAC.DOKU.1080p.Web-DL.x264/"
            + "Die.Anstalt.S2026E042.German.AAC.DOKU.1080p.Web-DL.x264.mp4"
        #expect(name.relativeFile(extension: "") == expected)
    }

    /// The globs stop before the quality, so an episode counts as downloaded
    /// in any quality, and both layouts are covered.
    @Test("the globs match any quality and both layouts")
    func globs() {
        let globs = naming().globs
        #expect(globs.count == 2)
        #expect(globs[0].hasPrefix("Die.Anstalt.S2026.*/Die.Anstalt.S2026E042.*/"))
        #expect(globs[1].hasPrefix("Die.Anstalt.S2026/Die.Anstalt.S2026E042.*"))
        for glob in globs {
            #expect(!glob.contains("1080p"))
        }
    }

    // MARK: Validation

    /// A title of only white space is refused.
    @Test("an empty title is refused")
    func validateTitle() {
        #expect(throws: DownloadError.self) { try MediaNaming.validateTitle("   ") }
        #expect(throws: DownloadError.self) { try MediaNaming.validateTitle("") }
    }

    /// A real title passes.
    @Test("a real title passes")
    func validateTitleAccepts() throws {
        try MediaNaming.validateTitle("Die Anstalt")
    }

    /// The year has to lie between 2000 and next year.
    @Test("the year is bounded")
    func validateYear() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15
        #expect(throws: DownloadError.self) { try MediaNaming.validateYear(1999, now: now) }
        #expect(throws: DownloadError.self) { try MediaNaming.validateYear(0, now: now) }
        #expect(throws: DownloadError.self) { try MediaNaming.validateYear(2029, now: now) }
    }

    /// The bounds themselves are allowed, including one year ahead.
    @Test("the year bounds are inclusive")
    func validateYearAccepts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15
        try MediaNaming.validateYear(2000, now: now)
        try MediaNaming.validateYear(2028, now: now)
    }

    /// The episode number starts at one and has at most six digits.
    @Test("the episode number is bounded")
    func validateEpisodeNumber() {
        #expect(throws: DownloadError.self) { try MediaNaming.validateEpisodeNumber(0) }
        #expect(throws: DownloadError.self) { try MediaNaming.validateEpisodeNumber(-3) }
        #expect(throws: DownloadError.self) { try MediaNaming.validateEpisodeNumber(1_000_000) }
    }

    /// The smallest and the largest allowed number pass.
    @Test("the episode number bounds are inclusive")
    func validateEpisodeNumberAccepts() throws {
        try MediaNaming.validateEpisodeNumber(1)
        try MediaNaming.validateEpisodeNumber(999_999)
    }

    // MARK: Layout parsing

    /// The empty name is the compatible layout.
    @Test("the layout name is parsed leniently")
    func layoutParsing() throws {
        #expect(try MediaLayout.parse("") == .compat)
        #expect(try MediaLayout.parse("compat") == .compat)
        #expect(try MediaLayout.parse("  COMPAT ") == .compat)
        #expect(try MediaLayout.parse("flat") == .flat)
        #expect(try MediaLayout.parse("FLAT") == .flat)
    }

    /// An unknown layout name is refused instead of silently guessed.
    @Test("an unknown layout name is refused")
    func layoutParsingRefuses() {
        #expect(throws: DownloadError.self) { try MediaLayout.parse("irgendwas") }
    }

    // MARK: Building from metadata

    /// The title falls back from the format title to the episode's format
    /// name to the slug, so a name is never empty.
    @Test("the title falls back through the metadata")
    func titleFallback() {
        let published = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01 UTC
        let fromSlug = MediaNaming(formatTitle: "", episodeFormatName: "", formatSlug: "die-anstalt",
                                   published: published, number: 5, layout: .compat)
        #expect(fromSlug.title == "die-anstalt")
        #expect(fromSlug.year == 2026)

        let fromEpisode = MediaNaming(formatTitle: "", episodeFormatName: "Anstalt Spezial",
                                      formatSlug: "die-anstalt", published: published,
                                      number: 5, layout: .compat)
        #expect(fromEpisode.title == "Anstalt Spezial")

        let fromFormat = MediaNaming(formatTitle: "Die Anstalt", episodeFormatName: "Anstalt Spezial",
                                     formatSlug: "die-anstalt", published: published,
                                     number: 5, layout: .compat)
        #expect(fromFormat.title == "Die Anstalt")
    }

    /// Without a publication date the year stays zero and validation refuses
    /// the name, instead of guessing a year.
    @Test("a missing date leaves the year at zero")
    func missingDate() {
        let name = MediaNaming(formatTitle: "T", episodeFormatName: "", formatSlug: "t",
                               published: nil, number: 1, layout: .compat)
        #expect(name.year == 0)
        #expect(throws: DownloadError.self) { try name.validate() }
    }
}
