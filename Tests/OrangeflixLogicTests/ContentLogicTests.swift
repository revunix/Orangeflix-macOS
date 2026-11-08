import CoreGraphics
import Foundation
import Testing

@testable import OrangeflixLogic

/// The chat text of the Live page. The messages arrive as HTML and have to
/// become plain text without losing what a user typed.
@Suite("LiveHTML")
struct LiveHTMLTests {

    /// Tags are removed.
    @Test("markup is removed")
    func markupRemoved() {
        #expect(LiveHTML.cleanText("<b>fett</b>") == "fett")
        #expect(LiveHTML.cleanText("<a href=\"x\">link</a>") == "link")
        #expect(LiveHTML.cleanText("<span class='a'>text</span>") == "text")
    }

    /// A line break becomes a space, not nothing, so words do not merge.
    @Test("a line break becomes a space")
    func lineBreak() {
        #expect(LiveHTML.cleanText("a<br>b") == "a b")
        #expect(LiveHTML.cleanText("a<br/>b") == "a b")
        #expect(LiveHTML.cleanText("a<br />b") == "a b")
        #expect(LiveHTML.cleanText("a<BR>b") == "a b")
    }

    /// Runs of white space collapse into one blank.
    @Test("white space collapses")
    func whiteSpace() {
        #expect(LiveHTML.cleanText("a   b") == "a b")
        #expect(LiveHTML.cleanText("  a  b  ") == "a b")
        #expect(LiveHTML.cleanText("a\n\n\tb") == "a b")
    }

    /// An escaped less-than sign is what the user typed and must survive.
    @Test("an escaped less-than sign survives")
    func escapedMarkup() {
        #expect(LiveHTML.cleanText("&lt;3") == "<3")
        #expect(LiveHTML.cleanText("a &lt; b") == "a < b")
        #expect(LiveHTML.cleanText("&amp;") == "&")
    }

    /// A break that was escaped twice is caught after decoding.
    @Test("a double escaped break becomes a space")
    func doubleEscapedBreak() {
        #expect(LiveHTML.cleanText("a&lt;br&gt;b") == "a b")
        #expect(LiveHTML.cleanText("a&lt;br/&gt;b") == "a b")
    }

    /// A break that was escaped three times is not resolved: the text is
    /// decoded once, so what remains is the escaped markup of the second
    /// level. Recorded here so a change of that behaviour is noticed.
    @Test("a triple escaped break stays as text")
    func tripleEscapedBreak() {
        #expect(LiveHTML.cleanText("a&amp;lt;br&amp;gt;b") == "a&lt;br&gt;b")
    }

    /// The common named entities are decoded.
    @Test("named entities are decoded")
    func namedEntities() {
        #expect(LiveHTML.unescape("&quot;") == "\"")
        #expect(LiveHTML.unescape("&apos;") == "'")
        #expect(LiveHTML.unescape("&nbsp;") == "\u{00A0}")
        #expect(LiveHTML.unescape("&euro;") == "€")
        #expect(LiveHTML.unescape("&uuml;") == "ü")
    }

    /// Numeric references are decoded, in decimal and in hex.
    @Test("numeric references are decoded")
    func numericEntities() {
        #expect(LiveHTML.unescape("&#65;") == "A")
        #expect(LiveHTML.unescape("&#x41;") == "A")
        #expect(LiveHTML.unescape("&#x1F600;") == "\u{1F600}")
        #expect(LiveHTML.unescape("&#228;") == "ä")
    }

    /// An unknown entity stays as it is instead of disappearing.
    @Test("an unknown entity is left alone")
    func unknownEntity() {
        #expect(LiveHTML.unescape("&nixda;") == "&nixda;")
        #expect(LiveHTML.unescape("&") == "&")
        #expect(LiveHTML.unescape("a & b") == "a & b")
    }

    /// An entity without a semicolon is still decoded, the way HTML5 reads
    /// the legacy names.
    @Test("an entity without a semicolon is decoded")
    func entityWithoutSemicolon() {
        #expect(LiveHTML.unescape("&amp") == "&")
        #expect(LiveHTML.unescape("&ampx") == "&x")
    }

    /// An unterminated numeric reference does not hang or crash.
    @Test("an unterminated numeric reference is harmless")
    func unterminatedEntity() {
        #expect(LiveHTML.unescape("&#") == "&#")
        #expect(LiveHTML.unescape("&#x") == "&#x")
        #expect(LiveHTML.unescape("&") == "&")
    }

    /// Splitting into fields follows Go's `strings.Fields`.
    @Test("fields split around white space")
    func fields() {
        #expect(LiveHTML.fields("a b  c") == ["a", "b", "c"])
        #expect(LiveHTML.fields("") == [])
        #expect(LiveHTML.fields("   ") == [])
        #expect(LiveHTML.fields(" a ") == ["a"])
    }

    /// An empty message stays empty.
    @Test("an empty message stays empty")
    func empty() {
        #expect(LiveHTML.cleanText("") == "")
        #expect(LiveHTML.cleanText("   ") == "")
        #expect(LiveHTML.cleanText("<b></b>") == "")
    }
}

/// The file selection for a download quality.
@Suite("Quality")
struct QualityTests {

    private func file(_ desc: String, _ dimensions: String, kind: String = "film",
                      url: String = "https://example.invalid/f") -> ClipFile {
        ClipFile(url: url, desc: desc, size: 1, dimensions: dimensions, kind: kind, file: "")
    }

    /// The resolution is read from the pixel size.
    @Test("the rank is the pixel height")
    func rankFromDimensions() {
        #expect(file("HD 1080p", "1920x1080").rank == 1080)
        #expect(file("SD 432p", "768x432").rank == 432)
    }

    /// Without a pixel size the description is used.
    @Test("the rank falls back to the description")
    func rankFromDescription() {
        #expect(ClipFile.resolutionRank("HD 720p") == 720)
        #expect(ClipFile.resolutionRank("SD 432p") == 432)
        #expect(ClipFile.resolutionRank("Audio m4a") == 0)
        #expect(ClipFile.resolutionRank("ohne Zahl") == 0)
    }

    /// An audio track is recognised by its kind or its description.
    @Test("an audio track is recognised")
    func audioDetection() {
        #expect(file("Audio m4a", "", kind: "music").isAudio)
        #expect(file("Audio mp3", "").isAudio)
        #expect(!file("HD 1080p", "1920x1080").isAudio)
    }

    /// The resolution label is normalised to the next known step.
    @Test("the resolution label is normalised")
    func resolutionLabel() {
        #expect(file("HD 1080p", "1920x1080").resolutionLabel == "1080p")
        #expect(file("HD 720p", "1280x720").resolutionLabel == "720p")
        #expect(file("UHD", "3840x2160").resolutionLabel == "2160p")
        #expect(file("Audio m4a", "", kind: "music").resolutionLabel == "Audio")
    }

    /// "best" picks the highest video file and reports an exact hit.
    @Test("best picks the highest video")
    func selectBest() throws {
        let files = [file("SD 432p", "768x432"), file("HD 1080p", "1920x1080"), file("HD 720p", "1280x720")]
        let selection = try files.select(quality: "best")
        #expect(selection.file.desc == "HD 1080p")
        #expect(selection.exact)
    }

    /// An empty quality means best.
    @Test("an empty quality means best")
    func selectEmpty() throws {
        let files = [file("SD 432p", "768x432"), file("HD 1080p", "1920x1080")]
        #expect(try files.select(quality: "").file.desc == "HD 1080p")
    }

    /// Audio files never win the "best" pick.
    @Test("best never picks audio")
    func selectBestSkipsAudio() throws {
        let files = [file("HD 1080p", "1920x1080"), file("Audio m4a", "", kind: "music")]
        #expect(try files.select(quality: "best").file.desc == "HD 1080p")
    }

    /// A file without a URL is not a candidate: its link is stale.
    @Test("a file without a URL is skipped")
    func selectSkipsEmptyURL() throws {
        let files = [file("HD 1080p", "1920x1080", url: ""), file("HD 720p", "1280x720")]
        #expect(try files.select(quality: "best").file.desc == "HD 720p")
    }

    /// An empty list is an error, not a crash.
    @Test("an empty list is an error")
    func selectEmptyList() {
        let files: [ClipFile] = []
        #expect(throws: APIError.self) { try files.select(quality: "best") }
    }

    /// A list without a video file cannot serve "best".
    @Test("a list without video cannot serve best")
    func selectNoVideo() {
        let files = [file("Audio m4a", "", kind: "music")]
        #expect(throws: APIError.self) { try files.select(quality: "best") }
    }

    /// The exact qualities are found by their description.
    @Test("the exact qualities are found")
    func selectExact() throws {
        let files = [
            file("HD 1080p", "1920x1080"),
            file("HD 720p", "1280x720"),
            file("SD 432p", "768x432"),
            file("Audio m4a", "", kind: "music"),
        ]
        #expect(try files.select(quality: "hd").file.desc == "HD 1080p")
        #expect(try files.select(quality: "mobile").file.desc == "HD 720p")
        #expect(try files.select(quality: "sd").file.desc == "SD 432p")
        #expect(try files.select(quality: "audio").file.desc == "Audio m4a")
        #expect(try files.select(quality: "hd").exact)
    }

    /// A missing exact quality falls back and says so.
    @Test("a missing quality falls back and reports it")
    func selectFallback() throws {
        let files = [file("HD 1080p", "1920x1080"), file("HD 720p", "1280x720")]
        let selection = try files.select(quality: "sd")
        #expect(!selection.exact)
        // The lowest available video is the fallback.
        #expect(selection.file.desc == "HD 720p")
    }

    /// An unknown quality name falls back instead of throwing.
    @Test("an unknown quality falls back")
    func selectUnknown() throws {
        let files = [file("HD 1080p", "1920x1080")]
        let selection = try files.select(quality: "4k-hdr")
        #expect(selection.file.desc == "HD 1080p")
        #expect(!selection.exact)
    }

    /// The quality names are validated against the known set.
    @Test("quality names are validated")
    func qualityValidation() {
        #expect(ClipQuality.isValid("best"))
        #expect(ClipQuality.isValid("hd"))
        #expect(!ClipQuality.isValid("HD"))
        #expect(!ClipQuality.isValid(""))
        #expect(!ClipQuality.isValid("4k"))
    }
}

/// Where a playback starts and how far it got.
@Suite("PlaybackLogic")
struct PlaybackLogicTests {

    /// A position at the very beginning is not a resume.
    @Test("a position at the start is not resumed")
    func resumeAtStart() {
        #expect(PlaybackLogic.resumePosition(lastPosition: 0, durationSeconds: 600) == 0)
        #expect(PlaybackLogic.resumePosition(lastPosition: 3, durationSeconds: 600) == 0)
        #expect(PlaybackLogic.resumePosition(lastPosition: 5, durationSeconds: 600) == 0)
    }

    /// A position in the middle is resumed.
    @Test("a middle position is resumed")
    func resumeMiddle() {
        #expect(PlaybackLogic.resumePosition(lastPosition: 6, durationSeconds: 600) == 6)
        #expect(PlaybackLogic.resumePosition(lastPosition: 300, durationSeconds: 600) == 300)
    }

    /// A position near the end restarts the episode instead of showing its
    /// last seconds.
    @Test("a position near the end restarts")
    func resumeNearEnd() {
        #expect(PlaybackLogic.resumePosition(lastPosition: 596, durationSeconds: 600) == 0)
        #expect(PlaybackLogic.resumePosition(lastPosition: 600, durationSeconds: 600) == 0)
        #expect(PlaybackLogic.resumePosition(lastPosition: 594, durationSeconds: 600) == 594)
    }

    /// An unknown duration does not make the resume impossible.
    @Test("an unknown duration still resumes")
    func resumeWithoutDuration() {
        #expect(PlaybackLogic.resumePosition(lastPosition: 120, durationSeconds: 0) == 120)
    }

    /// The percentage is rounded and clamped.
    @Test("the progress percentage is rounded and clamped")
    func progressPercent() {
        #expect(PlaybackLogic.progressPercent(position: 0, duration: 600) == 0)
        #expect(PlaybackLogic.progressPercent(position: 300, duration: 600) == 50)
        #expect(PlaybackLogic.progressPercent(position: 600, duration: 600) == 100)
        #expect(PlaybackLogic.progressPercent(position: 900, duration: 600) == 100)
        #expect(PlaybackLogic.progressPercent(position: -10, duration: 600) == 0)
        #expect(PlaybackLogic.progressPercent(position: 100, duration: 0) == 0)
    }

    @Test("preview positions cover five parts and leave room to play")
    func previewPositions() {
        var random = SystemRandomNumberGenerator()
        let positions = PlaybackLogic.previewPositions(duration: 100, using: &random)
        #expect(positions.count == 5)
        for (index, position) in positions.enumerated() {
            #expect(position >= 96 * index / 5)
            #expect(position < 96 * (index + 1) / 5)
            #expect(position + 5 <= 100)
        }
    }

    @Test("preview positions handle missing or short durations")
    func shortPreviewPositions() {
        var random = SystemRandomNumberGenerator()
        #expect(PlaybackLogic.previewPositions(duration: 0, using: &random).isEmpty)
        for duration in 1...10 {
            let positions = PlaybackLogic.previewPositions(duration: duration, using: &random)
            #expect(positions.count == 5)
            #expect(positions.allSatisfy { $0 >= 0 && $0 < duration })
        }
    }

    @Test("preview positions do not overflow for a large duration")
    func largePreviewDuration() {
        var random = SystemRandomNumberGenerator()
        let positions = PlaybackLogic.previewPositions(duration: Int.max, using: &random)
        #expect(positions.count == 5)
        #expect(positions.allSatisfy { $0 >= 0 && $0 <= Int.max - 5 })
    }

    /// HLS wins over DASH, because the bundled ffmpeg has no DASH demuxer.
    @Test("HLS wins over DASH")
    func streamPreference() {
        let streams = [
            PlaybackLogic.dashMIME: "https://example.invalid/manifest.mpd",
            PlaybackLogic.hlsMIME: "https://example.invalid/master.m3u8",
        ]
        #expect(PlaybackLogic.liveStreamURL(streams: streams) == "https://example.invalid/master.m3u8")
    }

    /// Without HLS the DASH address is used.
    @Test("DASH is used without HLS")
    func streamDashFallback() {
        let streams = [PlaybackLogic.dashMIME: "https://example.invalid/manifest.mpd"]
        #expect(PlaybackLogic.liveStreamURL(streams: streams) == "https://example.invalid/manifest.mpd")
    }

    /// An empty value does not count as an address.
    @Test("an empty address does not count")
    func streamEmpty() {
        #expect(PlaybackLogic.liveStreamURL(streams: [PlaybackLogic.hlsMIME: "   "]) == nil)
        #expect(PlaybackLogic.liveStreamURL(streams: [:]) == nil)
    }

    /// Any other address is the last resort.
    @Test("an unknown type is the last resort")
    func streamOther() {
        let streams = ["video/mp4": "https://example.invalid/f.mp4"]
        #expect(PlaybackLogic.liveStreamURL(streams: streams) == "https://example.invalid/f.mp4")
    }

    /// The DASH manifest address is only returned for DASH.
    @Test("the manifest address is only DASH")
    func manifestURL() {
        #expect(PlaybackLogic.dashManifestURL(streams: [PlaybackLogic.hlsMIME: "x"]) == nil)
        #expect(PlaybackLogic.dashManifestURL(streams: [PlaybackLogic.dashMIME: "y"]) == "y")
    }

    /// The start time is read from a DASH manifest.
    @Test("the start time is read from the manifest")
    func availabilityStartTime() {
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" availabilityStartTime="2026-03-01T20:00:00Z">
        </MPD>
        """
        let date = PlaybackLogic.availabilityStartTime(in: Data(manifest.utf8))
        #expect(date != nil)
        if let date {
            let formatter = ISO8601DateFormatter()
            #expect(formatter.string(from: date) == "2026-03-01T20:00:00Z")
        }
    }

    /// A manifest without the attribute yields nothing.
    @Test("a manifest without a start time yields nothing")
    func availabilityStartTimeMissing() {
        let manifest = #"<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"></MPD>"#
        #expect(PlaybackLogic.availabilityStartTime(in: Data(manifest.utf8)) == nil)
    }

    /// Broken XML yields nothing instead of crashing.
    @Test("broken XML yields nothing")
    func availabilityStartTimeBroken() {
        #expect(PlaybackLogic.availabilityStartTime(in: Data("nicht xml".utf8)) == nil)
        #expect(PlaybackLogic.availabilityStartTime(in: Data()) == nil)
    }
}

@Suite("Search pointer")
struct SearchPointerLogicTests {
    @Test("mouse coordinates account for the event view's offset")
    func sourceOffset() {
        let source = CGRect(x: 12, y: 24, width: 400, height: 300)
        #expect(SearchPointerLogic.position(CGPoint(x: 30, y: 40), in: source) == CGPoint(x: 42, y: 64))
    }

    @Test("a timestamp is hit at its visible position in the list")
    func timestampPosition() {
        let id = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 500, height: 400)
        let source = CGRect(x: 0, y: 0, width: 500, height: 400)
        let timestamp = SearchPointerRegion(id: id, frame: CGRect(x: 210, y: 130, width: 65, height: 24))
        let point = SearchPointerLogic.position(CGPoint(x: 240, y: 142), in: source)
        #expect(SearchPointerLogic.target(at: point, viewport: viewport, regions: [timestamp]) == id)
        let below = SearchPointerLogic.position(CGPoint(x: 240, y: 190), in: source)
        #expect(SearchPointerLogic.target(at: below, viewport: viewport, regions: [timestamp]) == nil)
    }

    @Test("only the target under the pointer is selected")
    func distinctTargets() {
        let first = UUID(), second = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)
        let regions = [SearchPointerRegion(id: first, frame: CGRect(x: 10, y: 10, width: 100, height: 60)),
                       SearchPointerRegion(id: second, frame: CGRect(x: 10, y: 90, width: 100, height: 60))]
        #expect(SearchPointerLogic.target(at: CGPoint(x: 30, y: 30), viewport: viewport, regions: regions) == first)
        #expect(SearchPointerLogic.target(at: CGPoint(x: 30, y: 100), viewport: viewport, regions: regions) == second)
        #expect(SearchPointerLogic.target(at: CGPoint(x: 200, y: 30), viewport: viewport, regions: regions) == nil)
        #expect(SearchPointerLogic.target(at: nil, viewport: viewport, regions: regions) == nil)
    }

    @Test("clipped or offscreen targets cannot activate")
    func clippedTargets() {
        let id = UUID()
        let viewport = CGRect(x: 0, y: 50, width: 200, height: 50)
        let regions = [SearchPointerRegion(id: id, frame: CGRect(x: 0, y: 20, width: 100, height: 50))]
        #expect(SearchPointerLogic.target(at: CGPoint(x: 10, y: 30), viewport: viewport, regions: regions) == nil)
        #expect(SearchPointerLogic.target(at: CGPoint(x: 10, y: 60), viewport: viewport, regions: regions) == id)
    }

    @Test("overlapping targets select only the smaller one")
    func overlappingTargets() {
        let large = UUID(), small = UUID()
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let regions = [SearchPointerRegion(id: large, frame: viewport),
                       SearchPointerRegion(id: small, frame: CGRect(x: 10, y: 10, width: 20, height: 20))]
        #expect(SearchPointerLogic.target(at: CGPoint(x: 15, y: 15), viewport: viewport, regions: regions) == small)
    }
}
