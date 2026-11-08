import Foundation

/// The data for the Authorization header. The delivery network works
/// without credentials, so they only travel to the legacy API.
struct DownloadCredentials: Sendable, Hashable {
    /// Basic authentication of the legacy API.
    var username: String = ""
    var password: String = ""
    /// Access token of the version 3 API; preferred over basic auth.
    var bearer: String = ""
}

/// A finished download.
struct DownloadResult: Sendable, Hashable {
    /// The file that was written.
    var file: URL
    /// The size of the file in bytes (including a continued partial file).
    var size: Int64
    /// The MD5 checksum of the whole file, lowercase hex.
    var md5: String
}

/// The progress of a running download. Speed and ETA are computed from the
/// bytes of the current try only, so a continued partial file does not
/// inflate the speed.
struct DownloadProgress: Sendable, Hashable {
    /// Bytes of the file that are on disk.
    var done: Int64
    /// Size of the whole file; 0 when the server does not announce it.
    var total: Int64
    /// Bytes transferred by the current try.
    var transferred: Int64
    /// Seconds since the current try received its answer.
    var elapsed: Double

    /// Average speed of the current try in bytes per second.
    var bytesPerSecond: Double {
        elapsed > 0 ? Double(transferred) / elapsed : 0
    }

    /// Estimated seconds until the file is complete, nil when unknown.
    var estimatedRemaining: Double? {
        let speed = bytesPerSecond
        guard total > 0, speed > 0, done <= total else { return nil }
        return Double(total - done) / speed
    }

    /// Fraction 0...1, nil when the total is unknown.
    var fraction: Double? {
        total > 0 ? min(1, Double(done) / Double(total)) : nil
    }
}

/// Which extra files are stored next to a downloaded video.
struct SidecarOptions: Sendable, Hashable, Codable {
    /// Store the thumbnail as "<video>.jpg".
    var thumbnail: Bool = false
    /// Store the metadata as "<video>.json".
    var metadata: Bool = false
}

/// The metadata of an episode for the JSON sidecar (port of the fields that
/// `saveMeta` of the Go app reads from the episode).
struct EpisodeMetadata: Sendable, Hashable, Codable {
    var identifier: String
    var pid: Int
    var number: Int
    var title: String
    /// The name of the format.
    var formatName: String
    var description: String = ""
    /// Publication date; written as UTC "yyyy-MM-dd".
    var published: Date?
    /// Human readable duration as delivered by the API.
    var duration: String = ""
    var durationSeconds: Int = 0
    /// Thumbnail URL as delivered by the API (also used to fetch the
    /// thumbnail sidecar).
    var thumbnailURL: String = ""
    /// Names of the participants.
    var participants: [String] = []
}

/// One episode to download. Pure value: the short-lived file URL is resolved
/// right before the download through the queue's `resolveSource` closure,
/// after the skip check, exactly like the Go pipeline.
struct DownloadRequest: Sendable, Hashable, Identifiable {
    /// Identifier of the episode; also the id of the queue item.
    var id: String
    /// PID of the format the episode belongs to.
    var pid: Int
    /// Naming without resolution; the resolution comes from the source.
    var naming: MediaNaming
    /// Data of the JSON sidecar and the thumbnail URL.
    var metadata: EpisodeMetadata
    /// Which sidecars to store.
    var sidecars: SidecarOptions = SidecarOptions()
}

/// The resolved file of an episode in the requested quality.
struct DownloadSource: Sendable, Hashable {
    /// The (token-carrying) file URL; never logged.
    var url: URL
    /// Resolution label of the chosen file ("1080p"); empty means "1080p".
    var resolution: String
    /// File extension with or without dot; empty means ".mp4".
    var fileExtension: String
    /// Credentials for the legacy API, nil for the delivery network.
    var credentials: DownloadCredentials?
    /// Size of the file when the API knows it; used when the server does
    /// not announce a length.
    var expectedSize: Int64?
    /// Subtitle URLs; stored as "<video>.de.vtt", "<video>.1.de.vtt", ...
    var subtitles: [URL] = []
}

/// Settings of the queue (Go: --parallel, --delay, --force).
struct DownloadQueueConfiguration: Sendable, Hashable {
    /// Downloads that run at the same time, clamped to 1...8.
    var parallel: Int = 1 {
        didSet { parallel = min(max(parallel, 1), 8) }
    }
    /// Pause between two downloads in seconds, clamped to 0...3600.
    var delay: Double = 0 {
        didSet { delay = min(max(delay, 0), 3600) }
    }
    /// Remove existing files and partial files instead of skipping.
    var force: Bool = false

    init(parallel: Int = 1, delay: Double = 0, force: Bool = false) {
        self.parallel = min(max(parallel, 1), 8)
        self.delay = min(max(delay, 0), 3600)
        self.force = force
    }
}

/// User visible state changes of the queue, mirroring the download related
/// Go event kinds (log, queued, progress, skipped, done, failed) plus the
/// GUI-specific `cancelled` and `idle`.
enum DownloadEvent: Sendable, Hashable {
    /// A log line (German); `isError` marks failures.
    case log(message: String, isError: Bool)
    /// The download of an item starts; the target is known.
    case queued(id: String, pid: Int, label: String, file: URL)
    /// Bytes arrived (at most every 500 ms, plus once at the end).
    case progress(id: String, pid: Int, label: String, progress: DownloadProgress)
    /// The episode was already there (in any quality or layout).
    case skipped(id: String, pid: Int, label: String, file: URL)
    /// The download finished; the file has its final name.
    case done(id: String, pid: Int, label: String, file: URL, size: Int64)
    /// The download failed; the partial file stays unless it was broken.
    case failed(id: String, pid: Int, label: String, message: String)
    /// The item was cancelled; the partial file stays for the next run.
    case cancelled(id: String, pid: Int, label: String)
    /// The queue ran empty. `failures` counts the failed items since the
    /// last idle event, `firstFailure` is the message of the first one.
    case idle(failures: Int, firstFailure: String?)
}
