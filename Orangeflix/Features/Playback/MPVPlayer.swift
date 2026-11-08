import CoreGraphics
import Foundation
import Libmpv
import Observation
import os

/// One audio or subtitle track of the running file.
struct MPVTrack: Identifiable, Hashable, Sendable, Decodable {
    let id: Int
    let type: String
    var title: String?
    var lang: String?
    var selected: Bool?
    var external: Bool?

    /// The name the menus show: the title, else the language, else the number.
    var label: String {
        if let title, !title.isEmpty { return title }
        if let lang, !lang.isEmpty {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang
        }
        return "Spur \(id)"
    }

    var isSelected: Bool { selected ?? false }
}

/// libmpv inside the app. The player keeps one mpv core for the whole run
/// of the app; the video window attaches its render context to it. The
/// state the interface shows is published on the main actor.
@MainActor @Observable
final class MPVPlayer {
    /// Why a file ended.
    enum EndReason: Equatable, Sendable {
        /// The file was played to its end.
        case finished
        /// The app stopped it or replaced it with the next file.
        case stopped
        /// mpv could not play the file.
        case failed(String)
    }

    /// The position in seconds; it moves in steps of a quarter second.
    private(set) var position: Double = 0
    /// The length of the file in seconds; 0 while it is not known.
    private(set) var duration: Double = 0
    /// Whether the playback holds.
    private(set) var isPaused = false
    /// Whether mpv opens the file or waits for the network.
    private(set) var isBuffering = false
    /// Seconds of the file that are read ahead of the position.
    private(set) var bufferedAhead: Double = 0
    /// The volume, 0 to 100.
    private(set) var volume: Double = 100
    private(set) var isMuted = false
    /// The playback speed.
    private(set) var speed: Double = 1
    /// Whether a file shows its subtitles when it opens.
    @ObservationIgnored var subtitlesOn = true
    /// The audio tracks and the subtitles of the file.
    private(set) var audioTracks: [MPVTrack] = []
    private(set) var subtitleTracks: [MPVTrack] = []
    /// The size of the picture after the aspect ratio; nil without video.
    private(set) var videoSize: CGSize?

    /// The file reached its end, was stopped or failed.
    @ObservationIgnored var onEnd: ((EndReason) -> Void)?
    /// The position moved.
    @ObservationIgnored var onPosition: ((Double) -> Void)?
    /// The requested file has opened and can report its position.
    @ObservationIgnored var onFileLoaded: (() -> Void)?

    /// The mpv core. It lives as long as the app.
    @ObservationIgnored nonisolated(unsafe) let handle: OpaquePointer

    /// A file that waits for the video window: mpv cannot open its video
    /// output before the render context exists.
    @ObservationIgnored private var pendingLoad: Load?
    @ObservationIgnored private var subtitlesToAdd: [URL] = []
    @ObservationIgnored private var isLoading = false
    /// Whether a file is open; its video is switched on again after the
    /// render context moved to another view.
    @ObservationIgnored private var fileActive = false
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var waitsForCache = false
    @ObservationIgnored private(set) var hasRenderContext = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "mpv")

    private struct Load {
        var url: URL
        var start: Int
        var headers: [String: String]
        var userAgent: String
        var subtitles: [URL]
    }

    init(preview: Bool = false) {
        guard let handle = mpv_create() else {
            fatalError("mpv_create failed")
        }
        self.handle = handle
        for (name, value) in Self.options {
            mpv_set_option_string(handle, name, value)
        }
        if preview { mpv_set_option_string(handle, "demuxer-max-bytes", "16MiB") }
        let status = mpv_initialize(handle)
        if status < 0 {
            logger.error("mpv_initialize: \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
        mpv_request_log_messages(handle, "warn")
        for property in Observed.allCases {
            mpv_observe_property(handle, property.rawValue, property.name, property.format)
        }
        mpv_set_wakeup_callback(handle, mpvWakeup, Unmanaged.passUnretained(self).toOpaque())
    }

    /// The options of the core: the video goes to the render API, mpv reads
    /// no user configuration, shows no controls of its own and takes no
    /// keys; the app draws all of that.
    private static let options: [(String, String)] = [
        ("vo", "libmpv"),
        ("hwdec", "auto-safe"),
        ("config", "no"),
        ("load-scripts", "no"),
        ("osc", "no"),
        ("osd-level", "0"),
        ("input-default-bindings", "no"),
        ("input-vo-keyboard", "no"),
        ("terminal", "no"),
        ("idle", "yes"),
        ("keep-open", "no"),
        ("ytdl", "no"),
        ("sub-auto", "no"),
        ("audio-file-auto", "no"),
        ("volume-max", "100"),
        ("cache", "yes"),
        ("demuxer-max-bytes", "256MiB"),
        ("sub-font-size", "40"),
        ("sub-border-size", "2"),
        ("sub-shadow-offset", "1"),
        ("sub-margin-y", "48"),
    ]

    // MARK: Files

    /// Opens a file and plays it from `start` seconds. The headers go with
    /// every request of the file; the subtitles are added once it is open.
    func load(_ url: URL, start: Int, headers: [String: String], userAgent: String, subtitles: [URL]) {
        let load = Load(url: url, start: start, headers: headers, userAgent: userAgent, subtitles: subtitles)
        isLoading = true
        updateBuffering()
        position = Double(max(start, 0))
        duration = 0
        audioTracks = []
        subtitleTracks = []
        if hasRenderContext {
            perform(load)
        } else {
            pendingLoad = load
        }
    }

    private func perform(_ load: Load) {
        pendingLoad = nil
        subtitlesToAdd = load.subtitles
        setString("user-agent", load.userAgent)
        // A list option: the entries are separated by commas; the values
        // the app sends (basic auth) carry none.
        setString("http-header-fields", load.headers.map { "\($0.key): \($0.value)" }.joined(separator: ","))
        setString("start", load.start > 0 ? "\(load.start)" : "none")
        // A local playlist (the HLS of a replay) loads its segments over
        // https; ffmpeg allows that only with an explicit list.
        setString("demuxer-lavf-o", load.url.isFileURL ? "protocol_whitelist=[file,http,https,tcp,tls,crypto,data]" : "")
        setString("pause", "no")
        command("loadfile", load.url.absoluteString, "replace")
    }

    /// Ends the running file; mpv waits idle for the next one.
    func stop() {
        pendingLoad = nil
        subtitlesToAdd = []
        isLoading = false
        updateBuffering()
        command("stop")
    }

    // MARK: Control

    func setPaused(_ paused: Bool) { setString("pause", paused ? "yes" : "no") }

    func togglePause() { setPaused(!isPaused) }

    /// Jumps to a place. A rough seek lands on the next key frame; it keeps
    /// up while the timeline is dragged.
    func seek(to seconds: Double, exact: Bool = true) {
        position = max(0, seconds)
        command("seek", String(format: "%.3f", max(0, seconds)), exact ? "absolute+exact" : "absolute+keyframes")
    }

    func seek(by seconds: Double) {
        command("seek", String(format: "%.3f", seconds), "relative+exact")
    }

    /// Jumps to the newest moment of a live stream and plays. Percent seeks
    /// land on the end of what the server still offers.
    func goToLiveEdge() {
        setPaused(false)
        command("seek", "100", "absolute-percent")
    }

    func setVolume(_ value: Double) {
        setString("volume", String(format: "%.0f", min(max(value, 0), 100)))
        if isMuted && value > 0 { setString("mute", "no") }
    }

    func toggleMute() { setString("mute", isMuted ? "no" : "yes") }

    func setMuted(_ muted: Bool) { setString("mute", muted ? "yes" : "no") }

    func setSpeed(_ value: Double) { setString("speed", String(format: "%.2f", value)) }

    /// Shows a subtitle track; nil hides the subtitles.
    func selectSubtitle(_ id: Int?) { setString("sid", id.map(String.init) ?? "no") }

    /// Switches the subtitles on or off; the choice also holds for the next
    /// file. On picks the first track, which is the only one in practice.
    func setSubtitlesOn(_ on: Bool) {
        subtitlesOn = on
        guard on else {
            setString("sid", "no")
            return
        }
        guard let first = subtitleTracks.first?.id else { return }
        setString("sid", String(first))
    }

    /// Whether the subtitles are showing.
    var showsSubtitles: Bool { subtitleTracks.contains(where: \.isSelected) }

    func selectAudio(_ id: Int) { setString("aid", String(id)) }

    /// The distance of the subtitles from the bottom edge, in the 720-line
    /// scale of mpv; it grows while the control panel covers the picture.
    func setSubtitleMargin(_ value: Int) { setString("sub-margin-y", String(value)) }

    // MARK: Render context

    /// A video view created its render context; a waiting file opens now.
    /// mpv switches the video off when a render context goes away, so a
    /// file that already plays gets its video track back.
    func renderContextAttached() {
        hasRenderContext = true
        if let pendingLoad {
            perform(pendingLoad)
        } else if fileActive {
            setString("vid", "no")
            setString("vid", "auto")
        }
    }

    /// The video window went away together with its render context.
    func renderContextDetached() {
        hasRenderContext = false
    }

    // MARK: Events

    /// Reads every event mpv has queued. Runs on the main actor after mpv
    /// woke the app.
    fileprivate func drainEvents() {
        while let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            switch event.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { break }
                let change = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                if let property = Observed(rawValue: event.reply_userdata) {
                    apply(property, change)
                }
            case MPV_EVENT_FILE_LOADED:
                isLoading = false
                fileActive = true
                updateBuffering()
                for (index, url) in subtitlesToAdd.enumerated() {
                    // Only the first track is chosen, and only when the
                    // subtitles are wanted; the rest wait in the menu.
                    command("sub-add", url.absoluteString, index == 0 && subtitlesOn ? "select" : "auto")
                }
                subtitlesToAdd = []
                if !subtitlesOn { setString("sid", "no") }
                let callback = onFileLoaded
                callback?()
            case MPV_EVENT_END_FILE:
                guard let data = event.data else { break }
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                isLoading = false
                fileActive = false
                updateBuffering()
                let callback = onEnd
                switch end.reason {
                case MPV_END_FILE_REASON_EOF:
                    callback?(.finished)
                case MPV_END_FILE_REASON_ERROR:
                    callback?(.failed(String(cString: mpv_error_string(end.error))))
                default:
                    callback?(.stopped)
                }
            case MPV_EVENT_LOG_MESSAGE:
                guard let data = event.data else { break }
                let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                let text = "[\(String(cString: message.prefix))] \(String(cString: message.text))"
                logger.warning("\(text.trimmingCharacters(in: .newlines), privacy: .public)")
            default:
                break
            }
        }
    }

    private func apply(_ property: Observed, _ change: mpv_event_property) {
        switch property {
        case .timePos:
            guard let value = change.double else { return }
            if abs(value - position) >= 0.25 || value < position {
                position = value
            }
            let callback = onPosition
            callback?(value)
        case .duration:
            duration = change.double ?? 0
        case .pause:
            isPaused = change.flag ?? false
        case .pausedForCache:
            waitsForCache = change.flag ?? false
            updateBuffering()
        case .seeking:
            isSeeking = change.flag ?? false
            updateBuffering()
        case .volume:
            volume = change.double ?? volume
        case .mute:
            isMuted = change.flag ?? false
        case .speed:
            speed = change.double ?? 1
        case .cacheDuration:
            bufferedAhead = change.double ?? 0
        case .trackList:
            readTracks()
        case .width, .height:
            let width = getInt("dwidth"), height = getInt("dheight")
            videoSize = width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
        }
    }

    private func updateBuffering() {
        isBuffering = isLoading || waitsForCache || isSeeking
    }

    /// The track list as mpv writes it in JSON.
    private func readTracks() {
        guard let raw = mpv_get_property_string(handle, "track-list") else {
            audioTracks = []
            subtitleTracks = []
            return
        }
        defer { mpv_free(raw) }
        let tracks = (try? JSONDecoder().decode([MPVTrack].self, from: Data(String(cString: raw).utf8))) ?? []
        audioTracks = tracks.filter { $0.type == "audio" }
        subtitleTracks = tracks.filter { $0.type == "sub" }
    }

    // MARK: Plumbing

    private func command(_ arguments: String...) {
        var strings = arguments.map { strdup($0) }
        strings.append(nil)
        defer { strings.forEach { free($0) } }
        let status = strings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                mpv_command(handle, $0)
            }
        }
        if status < 0 {
            logger.error("\(arguments.joined(separator: " "), privacy: .public): \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
    }

    private func setString(_ name: String, _ value: String) {
        let status = mpv_set_property_string(handle, name, value)
        if status < 0 {
            logger.error("set \(name, privacy: .public)=\(value, privacy: .public): \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
    }

    private func getInt(_ name: String) -> Int {
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? Int(value) : 0
    }

    /// The properties the player watches; the raw value is the reply id.
    private enum Observed: UInt64, CaseIterable {
        case timePos = 1, duration, pause, pausedForCache, seeking, volume, mute, speed, cacheDuration, trackList, width, height

        var name: String {
            switch self {
            case .timePos: "time-pos"
            case .duration: "duration"
            case .pause: "pause"
            case .pausedForCache: "paused-for-cache"
            case .seeking: "seeking"
            case .volume: "volume"
            case .mute: "mute"
            case .speed: "speed"
            case .cacheDuration: "demuxer-cache-duration"
            case .trackList: "track-list"
            case .width: "dwidth"
            case .height: "dheight"
            }
        }

        var format: mpv_format {
            switch self {
            case .timePos, .duration, .volume, .speed, .cacheDuration: MPV_FORMAT_DOUBLE
            case .pause, .pausedForCache, .seeking, .mute: MPV_FORMAT_FLAG
            case .trackList, .width, .height: MPV_FORMAT_NONE
            }
        }
    }
}

private extension mpv_event_property {
    var double: Double? {
        guard format == MPV_FORMAT_DOUBLE, let data else { return nil }
        return data.load(as: Double.self)
    }

    var flag: Bool? {
        guard format == MPV_FORMAT_FLAG, let data else { return nil }
        return data.load(as: Int32.self) != 0
    }
}

/// mpv calls this from any thread when events wait; they are read on the
/// main actor. The player lives as long as the app.
private func mpvWakeup(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let player = Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { player.drainEvents() }
    }
}
