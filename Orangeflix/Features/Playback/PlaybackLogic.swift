import Foundation

/// The rules of the playback without a player, ported from the Go app
/// (`internal/app/play.go`, `internal/app/live.go`). They are kept apart from
/// mpv so that they can be read and checked on their own.
enum PlaybackLogic {
    /// The shortest time between two reports of the watch position (Go
    /// `playbackReportInterval`): the website shows it within half a minute.
    static let reportInterval: TimeInterval = 30

    /// The time between two looks at the position of the player (Go
    /// `playbackPollInterval`).
    static let pollInterval: TimeInterval = 1

    /// A position at the very beginning or the very end of a file does not
    /// help; the beginning is always the safe case (Go `preparePlayback`).
    static let resumeThreshold = 5

    /// The MIME type of an HLS stream.
    static let hlsMIME = "application/x-mpegURL"
    /// The MIME type of a DASH stream.
    static let dashMIME = "application/dash+xml"

    // MARK: Starting position

    /// The position a playback starts at: the stored one, unless it is at
    /// the very beginning or within the last five seconds of the episode.
    static func resumePosition(lastPosition: Int, durationSeconds: Int) -> Int {
        let resume = lastPosition
        if resume <= resumeThreshold { return 0 }
        if durationSeconds > 0 && resume >= durationSeconds - resumeThreshold { return 0 }
        return resume
    }

    /// The share of the episode that was watched (Go
    /// `updateEpisodeProgress`).
    static func progressPercent(position: Double, duration: Double) -> Int {
        guard duration > 0, position > 0 else { return 0 }
        var percent = Int(position / duration * 100 + 0.5)
        if percent > 100 { percent = 100 }
        if percent < 0 { percent = 0 }
        return percent
    }

    // MARK: Live streams

    /// The address of the stream mpv plays: HLS first, also for the replay.
    /// The libmpv of the app comes with an ffmpeg without a DASH demuxer, so
    /// a DASH address fails with "unrecognized file format". The start time
    /// of the replay is read from the DASH manifest on its own
    /// (`dashManifestURL`). Any other address is the last resort.
    static func liveStreamURL(streams: [String: String]) -> String? {
        for mime in [hlsMIME, dashMIME] {
            if let value = streams[mime]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return streams.keys.sorted()
            .compactMap { streams[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The address of the DASH manifest of a stream. Its
    /// `availabilityStartTime` gives the start of a replay.
    static func dashManifestURL(streams: [String: String]) -> String? {
        guard let value = streams[dashMIME]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// The start of a replay from the DASH manifest, or nil when the
    /// manifest does not carry one (Go `mpdStartTime`).
    static func availabilityStartTime(in data: Data) -> Date? {
        let parser = XMLParser(data: data)
        let reader = AvailabilityStartTimeReader()
        parser.delegate = reader
        guard parser.parse() else { return nil }
        return reader.start
    }

    /// Places one message of the chat of a replay on the timeline of the
    /// video, in seconds (Go `replayChatOffset`).
    static func replayChatOffset(videoTime: Double, time: Int64, begin: Int64, duration: Int) -> Double {
        var limit = Double(duration) + 120
        if limit < 120 { limit = 24 * 3600 }
        var video = videoTime
        if video > 1_000_000_000_000 { video /= 1000 }
        if video >= 0 && video <= limit && (video > 0 || time == 0) { return video }
        var moment = time
        if moment > 1_000_000_000_000 { moment /= 1000 }
        if video > 1_000_000_000 { moment = Int64(video) }
        if begin > 0 && moment > 0 { return Double(moment - begin) }
        if video > 0 { return video }
        return 0
    }
}

/// Reads the `availabilityStartTime` of a DASH manifest.
private final class AvailabilityStartTimeReader: NSObject, XMLParserDelegate {
    /// The start of the stream, when the manifest names one.
    var start: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard start == nil, let value = attributeDict["availabilityStartTime"], !value.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        start = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
