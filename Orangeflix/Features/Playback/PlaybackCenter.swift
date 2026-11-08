import AppKit
import Foundation
import Observation
import os

/// Plays the episodes of the account and the live stream in the player
/// window (Go `App.Play` and `App.PlayLive`). It reports the watch position
/// to the account while the playback runs and keeps the state the interface
/// shows.
@MainActor @Observable final class PlaybackCenter: PlaybackStarting, LivePlaybackStarting {
    @ObservationIgnored let app: AppModel

    /// libmpv; it plays every entry and draws into the player window.
    let engine = MPVPlayer()
    /// An independent, reusable core for short search previews. It never
    /// reports watch progress or changes the main player's queue.
    @ObservationIgnored lazy var previewEngine = MPVPlayer(preview: true)
    /// The hover preview every episode picture shares.
    @ObservationIgnored lazy var preview = EpisodePreviewModel()
    @ObservationIgnored weak var browseModel: BrowseModel?
    /// The entries that play one after another.
    private(set) var queue: [PlaybackEntry] = []
    /// The entry that plays now.
    private(set) var current: PlaybackEntry?
    /// The position in seconds.
    private(set) var position: Double = 0
    /// The duration in seconds.
    private(set) var duration: Double = 0
    /// Whether a playback runs.
    private(set) var isPlaying = false
    /// Whether the running playback waits (a pause holds the position).
    var isPaused: Bool { engine.isPaused }
    /// The name of the running playback (the header shows it).
    private(set) var nowPlayingTitle = ""
    /// Whether the picture is shown inside a page (the Live screen, the page
    /// of an episode) instead of the player window.
    private(set) var isInline = false
    /// The episode whose files are being resolved; the page of the episode
    /// shows a spinner meanwhile.
    private(set) var preparingIdentifier: String?
    /// Whether the app may start new playbacks; a closed window refuses
    /// them (Go `playbackClosed`).
    private(set) var isClosed = false
    /// Whether a live stream plays at its newest moment. Rewinding or pausing
    /// leaves the edge; the Live button comes back to it.
    private(set) var isAtLiveEdge = true
    /// How far a rewind left the live edge, in seconds. A pause adds to it.
    private(set) var behindLive: TimeInterval = 0
    /// When the live stream was paused; nil while it plays.
    private(set) var livePauseBegan: Date?

    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var lastReport = Date()
    @ObservationIgnored private var lastReportedPosition = 0
    @ObservationIgnored private var reportErrorLogged = false
    /// Increases with every start; a preparation of an older start is
    /// dropped instead of replacing the running playback.
    @ObservationIgnored private var generation = 0
    /// The folder of the replay playlists that are in use.
    @ObservationIgnored private var replayFolder: URL?
    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "playback")
    /// Whether the last position of the running entry already went out.
    @ObservationIgnored private var didReportFinal = false
    @ObservationIgnored private var replayChat: [ReplayChatLine] = []
    @ObservationIgnored private var replayChatCursor = 0
    @ObservationIgnored private var replayChatHandler: (@MainActor (ReplayChatLine) -> Void)?
    @ObservationIgnored private var quitObserver: NotificationToken?

    init(app: AppModel) {
        self.app = app
        quitObserver = NotificationToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            })
        engine.onPosition = { [weak self] seconds in self?.handlePosition(seconds) }
        engine.onEnd = { [weak self] reason in self?.handleEnd(reason) }
    }

    deinit {
        quitObserver?.remove()
    }

    // MARK: PlaybackStarting

    /// Plays the episodes one after another, resuming each at the stored
    /// position (Go `App.Play`).
    func play(_ episodes: [Episode]) {
        let previewRestore = preview.stop()
        guard !episodes.isEmpty else {
            app.show(PlaybackError.noEpisodes.localizedDescription, error: true)
            return
        }
        guard !isClosed else { return }
        generation += 1
        let token = generation
        Task {
            await previewRestore?.value
            await prepareAndPlay(episodes, generation: token)
        }
    }

    /// Plays one episode from `seconds` on instead of the stored position;
    /// the search jumps to the chapter or the passage it found.
    func play(_ episode: Episode, from seconds: Int) {
        let previewRestore = preview.stop()
        guard !isClosed else { return }
        generation += 1
        let token = generation
        Task {
            await previewRestore?.value
            await prepareAndPlay([episode], generation: token, startAt: max(seconds, 0))
        }
    }

    /// Plays one episode inside the page of the episode; the player window
    /// stays closed. `seconds` replaces the stored position.
    func playInline(_ episode: Episode, from seconds: Int? = nil) {
        let previewRestore = preview.stop()
        guard !isClosed else { return }
        generation += 1
        let token = generation
        Task {
            await previewRestore?.value
            await prepareAndPlay([episode], generation: token, startAt: seconds.map { max($0, 0) }, inline: true)
        }
    }

    // MARK: Live

    /// Plays the running stream or its replay (Go `App.PlayLive`). Inline,
    /// the picture stays in the Live screen and the player window closes.
    func playLive(_ info: LivestreamInfo, mode: LivePlaybackMode, inline: Bool) async {
        let previewRestore = preview.stop()
        await previewRestore?.value
        guard !isClosed else { return }
        generation += 1
        let token = generation
        stop()
        isInline = inline
        if inline { PlayerWindows.close() }
        do {
            let entry = try await prepareLive(info, mode: mode)
            // A newer start owns the player now.
            guard token == generation else { return }
            queue = [entry]
            current = entry
            startCurrent()
        } catch {
            guard token == generation else { return }
            isInline = false
            app.show(error)
        }
    }

    /// Moves the running playback from its page into the player window.
    func popOut() {
        guard isPlaying, isInline else { return }
        isInline = false
        NotificationCenter.default.post(name: .orangeflixPlaybackStarted, object: nil)
    }

    /// Brings the running playback back from the player window into its
    /// page; the window closes without ending it.
    func pullIn() {
        guard isPlaying, !isInline else { return }
        isInline = true
        PlayerWindows.close()
    }

    /// Takes over the messages of the chat of a replay, so that they can be
    /// shown in the chat of the Live screen while the video runs.
    func setReplayChatHandler(_ handler: (@MainActor (ReplayChatLine) -> Void)?) {
        replayChatHandler = handler
    }

    // MARK: Control

    /// Ends the running playback; a new one may be started afterwards.
    func stop() {
        // The last position goes to the account, also when the player is
        // closed (Go `reportFinal`).
        reportFinal()
        engine.stop()
        isPlaying = false
        isInline = false
        current = nil
        queue = []
        position = 0
        duration = 0
        nowPlayingTitle = ""
        isAtLiveEdge = true
        behindLive = 0
        livePauseBegan = nil
        replayChat = []
        replayChatCursor = 0
        NotificationCenter.default.post(name: .orangeflixPlaybackStopped, object: nil)
    }

    /// Starts or pauses the running playback.
    /// Switches the subtitles on or off and remembers the choice for the
    /// next file.
    func setSubtitlesOn(_ on: Bool) {
        engine.setSubtitlesOn(on)
        try? app.updateSettings { $0.subtitlesOn = on }
    }

    func togglePlayPause() {
        guard isPlaying else { return }
        let pausing = !engine.isPaused
        engine.togglePause()
        guard current?.kind == .live else { return }
        if pausing {
            if livePauseBegan == nil { livePauseBegan = Date() }
            isAtLiveEdge = false
        } else if let began = livePauseBegan {
            behindLive += Date().timeIntervalSince(began)
            livePauseBegan = nil
        }
    }

    /// Moves the playback to a place in seconds. A rough seek follows the
    /// timeline while it is dragged; the exact one lands when it is let go.
    /// Near the end of a live stream the exact seek snaps back to the edge.
    func seek(to seconds: Double, exact: Bool = true) {
        guard isPlaying else { return }
        engine.seek(to: seconds, exact: exact)
        position = max(0, seconds)
        guard current?.kind == .live, duration > 0 else { return }
        let gap = max(0, duration - seconds)
        if gap < 4 {
            if exact { goLive() } else { catchLive() }
        } else {
            isAtLiveEdge = false
            behindLive = gap
        }
    }

    /// Moves the playback forward or back by some seconds. A live stream
    /// can be rewound; skipping back to the edge returns to live.
    func skip(by seconds: Double) {
        guard isPlaying else { return }
        engine.seek(by: seconds)
        guard current?.kind == .live else { return }
        if seconds < 0 {
            behindLive += -seconds
            isAtLiveEdge = false
        } else if !isAtLiveEdge {
            behindLive = max(0, behindLive - seconds)
            if behindLive < 1, livePauseBegan == nil { catchLive() }
        }
    }

    /// Jumps a live stream back to its newest moment and plays.
    func goLive() {
        guard isPlaying, current?.kind == .live else { return }
        engine.goToLiveEdge()
        catchLive()
    }

    /// How far the live playback sits behind the edge at `date`. While it
    /// is paused the gap grows with the clock.
    func secondsBehindLive(at date: Date) -> TimeInterval {
        var total = behindLive
        if let livePauseBegan { total += date.timeIntervalSince(livePauseBegan) }
        return max(0, total)
    }

    /// Marks the playback as sitting on the live edge.
    private func catchLive() {
        isAtLiveEdge = true
        behindLive = 0
        livePauseBegan = nil
    }

    /// Ends the playback and refuses new ones; the window uses it when it
    /// closes (Go `ShutdownPlayback`).
    func shutdown() {
        isClosed = true
        reportFinal()
        stop()
    }

    /// Plays the next entry of the queue.
    func playNext() {
        guard let entry = current, let index = queue.firstIndex(where: { $0.id == entry.id }), index + 1 < queue.count else {
            return
        }
        // The place of the episode that is left goes to the account.
        reportFinal()
        current = queue[index + 1]
        startCurrent()
    }

    /// The entry after the running one, when there is one.
    var nextEntry: PlaybackEntry? {
        guard let entry = current, let index = queue.firstIndex(where: { $0.id == entry.id }), index + 1 < queue.count else {
            return nil
        }
        return queue[index + 1]
    }

    // MARK: Preparing the episodes

    /// Resolves the files of the episodes (Go `preparePlayback`). A start
    /// that was overtaken by a newer one leaves the player alone. `startAt`
    /// replaces the stored position of the first episode; `inline` keeps
    /// the picture in the page of the episode.
    private func prepareAndPlay(_ episodes: [Episode], generation token: Int, startAt: Int? = nil,
                                inline: Bool = false) async {
        guard token == generation else { return }
        stop()
        guard token == generation else { return }
        isInline = inline
        if inline { PlayerWindows.close() }
        preparingIdentifier = episodes.first?.identifier
        defer { if token == generation { preparingIdentifier = nil } }
        do {
            var entries: [PlaybackEntry] = []
            for episode in episodes {
                let resolved: PlaybackSource
                do {
                    resolved = try await source(for: episode)
                } catch {
                    throw PlaybackError.metadataFailed(episode.identifier, error.localizedDescription)
                }
                guard token == generation else { return }
                let quality = app.settings.streamQuality.rawValue
                let selection: FileSelection
                do {
                    selection = try resolved.files.select(quality: quality)
                } catch {
                    throw PlaybackError.noFile(episode.identifier, error.localizedDescription)
                }
                if !selection.exact {
                    app.record("Qualität \(quality) ist nicht verfügbar, nehme \(selection.file.desc).")
                }
                let raw = try app.legacy.toHTTPS(selection.file.url)
                guard let url = URL(string: raw) else {
                    throw PlaybackError.invalidAddress(episode.identifier)
                }
                let stored = PlaybackLogic.resumePosition(
                    lastPosition: resolved.progress.lastPosition,
                    durationSeconds: episode.durationSeconds)
                let resume = entries.isEmpty ? (startAt ?? stored) : stored
                entries.append(PlaybackEntry(
                    identifier: episode.identifier,
                    title: Self.playbackTitle(episode),
                    detail: Self.playbackDetail(episode),
                    url: url,
                    resume: resume,
                    durationSeconds: episode.durationSeconds,
                    subtitleURLs: resolved.subtitles.compactMap(URL.init(string:)),
                    headers: resolved.headers,
                    kind: .episode,
                    chapters: resolved.chapters,
                    thumbnailTrack: URL(string: resolved.thumbnailTrack)))
            }
            guard token == generation else { return }
            queue = entries
            current = entries.first
            if !entries.isEmpty {
                app.record("Starte die Wiedergabe mit \(entries.count) Folge(n).")
                startCurrent()
            }
        } catch {
            if token == generation { isInline = false }
            app.show(error)
        }
    }

    /// The name of an episode for the messages of the interface (Go
    /// `playbackTitle`).
    static func playbackTitle(_ episode: Episode) -> String {
        if !episode.title.isEmpty { return episode.title }
        if episode.number > 0 { return "Folge \(episode.number)" }
        return episode.identifier
    }

    /// The line above the title in the player: the format and the number.
    static func playbackDetail(_ episode: Episode) -> String {
        var parts: [String] = []
        if !episode.formatName.isEmpty { parts.append(episode.formatName) }
        if episode.number > 0 { parts.append("Folge \(episode.number)") }
        return parts.joined(separator: " · ")
    }

    /// What the APIs know about the files of an episode (Go
    /// `episodeSource`): the version 3 API is preferred, the legacy API is
    /// the fallback.
    private func source(for episode: Episode) async throws -> PlaybackSource {
        let hasSession = (try? await app.ensureSession()) != nil
        try Task.checkCancellation()
        if hasSession {
            do {
                let playback = try await app.services.api.playback(episode.identifier)
                if !playback.files.isEmpty {
                    return PlaybackSource(files: playback.files, subtitles: playback.subtitleURLs,
                                         progress: playback.progress, headers: [:],
                                         durationSeconds: playback.durationSeconds,
                                         chapters: playback.chapters,
                                         thumbnailTrack: playback.thumbnailTrack)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                app.record("Die Version-3-API liefert keine Datei für \(episode.identifier) (\(error.localizedDescription)), nutze die alte API.")
            }
        }
        let clip = try await app.legacy.clip(episode.identifier)
        let credentials = app.legacyCredentials
        var headers: [String: String] = [:]
        if !credentials.username.isEmpty || !credentials.password.isEmpty {
            let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
            headers["Authorization"] = "Basic \(token)"
        }
        return PlaybackSource(files: clip.files, subtitles: [], progress: WatchProgress(), headers: headers,
                              durationSeconds: max(episode.durationSeconds, BrowseLogic.clockToSeconds(episode.duration)))
    }

    /// Resolves a low-bandwidth video for a search preview without starting
    /// playback or reporting its position to the account.
    enum PreviewError: LocalizedError {
        case noAccess

        var errorDescription: String? { "Für diese Folge fehlt der Zugang." }
    }

    func previewFile(for episode: Episode) async throws -> (URL, [String: String], Bool, Int) {
        try await app.ensureSession()
        let details = try await app.services.api.episodeDetails(episode.identifier, refresh: true)
        try Task.checkCancellation()
        guard !details.clip.id.isEmpty else { throw APIError.invalidRequest("Der Zugang zur Folge konnte nicht geprüft werden.") }
        guard details.clip.canAccess else { throw PreviewError.noAccess }
        let resolved = try await source(for: episode)
        try Task.checkCancellation()
        let file = try resolved.files.select(.sd).file
        guard !file.isAudio, let url = URL(string: try app.legacy.toHTTPS(file.url)) else {
            throw PlaybackError.invalidAddress(episode.identifier)
        }
        let wasWatched = max(resolved.progress.percentage, episode.progressPercent) >= BrowseLogic.watchedPercent
        let duration = max(resolved.progress.lastPosition,
                           max(resolved.durationSeconds,
                               max(episode.durationSeconds, BrowseLogic.clockToSeconds(episode.duration))))
        return (url, resolved.headers, wasWatched, duration)
    }

    /// A preview can register as a playback on the website even though this
    /// player never reports positions. Restore the account state it had before
    /// the preview, clearing incidental progress for unwatched episodes.
    func restorePreviewProgress(_ identifier: String, wasWatched: Bool, duration: Int) async {
        let percent = wasWatched ? 100 : 0
        do {
            try await app.services.api.updateProgress(identifier, seconds: wasWatched ? duration : 0)
            app.episodes.setProgress(identifier, percent: percent)
            browseModel?.removeFromRecents(identifier)
        } catch {
            app.record("Der Wiedergabestand nach der Vorschau konnte nicht wiederhergestellt werden: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Preparing the live stream

    /// Builds the entry of the live stream or its replay (Go `PlayLive`).
    private func prepareLive(_ info: LivestreamInfo, mode: LivePlaybackMode) async throws -> PlaybackEntry {
        let streams = mode == .replay ? (info.replay?.url ?? [:]) : info.url
        guard let raw = PlaybackLogic.liveStreamURL(streams: streams),
              var url = URL(string: raw) else {
            throw PlaybackError.noPlayableStream(isReplay: mode == .replay)
        }
        switch mode {
        case .live:
            let title = info.show?.title ?? "Live"
            app.record("Starte live für \(title).")
            return PlaybackEntry(identifier: "live", title: title, detail: "Live", url: url, kind: .live)
        case .replay:
            guard let replay = info.replay else { throw PlaybackError.noReplay }
            let manifestURL = PlaybackLogic.dashManifestURL(streams: streams).flatMap { URL(string: $0) }
            let manifest: Data? = if let manifestURL { await readManifest(manifestURL) } else { nil }
            let slot = Int(replay.end - replay.begin)
            let length = manifest.flatMap(DashReplayPlaylist.presentationSeconds(manifest:)).map { Int($0.rounded(.up)) } ?? slot
            // Without an HLS address mpv gets HLS playlists built from the
            // manifest; its ffmpeg cannot read DASH.
            if let manifestURL, url == manifestURL {
                guard let manifest, let local = writeReplayPlaylists(manifest: manifest, url: manifestURL) else {
                    throw PlaybackError.noPlayableStream(isReplay: true)
                }
                url = local
            }
            var entry = PlaybackEntry(identifier: replay.clipId, title: replay.title, detail: "Replay", url: url,
                                      durationSeconds: length, kind: .replay)
            // The start of the replay stands in the DASH manifest; it gives
            // the place in the wall clock and the place to resume.
            if let start = manifest.flatMap(PlaybackLogic.availabilityStartTime(in:)) {
                entry.start = start
                if info.lastWatchedAt > 0 {
                    let offset = info.lastWatchedAt - Int64(start.timeIntervalSince1970.rounded(.down))
                    // A place in the last half minute means the show is over;
                    // starting there would end the replay at once. The same
                    // holds for a place the recording does not reach.
                    if offset > 5, offset < Int64(length) - 30 {
                        entry.resume = Int(offset)
                    }
                }
            } else {
                app.record("Die Startzeit des Replays ist nicht lesbar, der Fortschritt wird nicht gemeldet.")
            }
            app.record("Starte replay für \(entry.title).")
            return entry
        }
    }

    /// Reads a DASH manifest (Go `mpdStartTime`).
    private func readManifest(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(APIDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        return data
    }

    /// Writes the HLS playlists of a replay into an own folder of the
    /// temporary directory and returns the master. Each replay gets its own
    /// folder, so a second start never overwrites the playlists of the one
    /// that still runs.
    private func writeReplayPlaylists(manifest: Data, url: URL) -> URL? {
        guard let lists = DashReplayPlaylist.playlists(manifest: manifest, url: url) else {
            app.record("Das Manifest des Replays ist nicht lesbar.", error: true)
            return nil
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("replay", isDirectory: true)
        let folder = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try lists.video.write(to: folder.appendingPathComponent(DashReplayPlaylist.videoName),
                                  atomically: true, encoding: .utf8)
            if let audio = lists.audio {
                try audio.write(to: folder.appendingPathComponent(DashReplayPlaylist.audioName),
                                atomically: true, encoding: .utf8)
            }
            let master = folder.appendingPathComponent("master.m3u8")
            try lists.master.write(to: master, atomically: true, encoding: .utf8)
            // The playlists of the replay before are not needed any more.
            if let previous = replayFolder, previous != folder {
                try? FileManager.default.removeItem(at: previous)
            }
            replayFolder = folder
            return master
        } catch {
            app.record("Die Playlist des Replays ließ sich nicht schreiben: \(error.localizedDescription)", error: true)
            return nil
        }
    }

    // MARK: Playing

    /// Starts the entry that plays now. The window of the player opens with
    /// it; mpv starts the file once the window can show the picture.
    private func startCurrent() {
        guard let entry = current else { return }
        position = Double(entry.resume)
        duration = Double(entry.durationSeconds)
        nowPlayingTitle = entry.title
        isPlaying = true
        lastTick = .distantPast
        lastReport = Date()
        lastReportedPosition = 0
        didReportFinal = false
        reportErrorLogged = false

        engine.subtitlesOn = app.settings.subtitlesOn
        engine.load(entry.url, start: entry.resume, headers: entry.headers,
                    userAgent: APIDefaults.userAgent, subtitles: entry.subtitleURLs)
        if entry.kind == .replay { loadReplayChat(for: entry) }
        NotificationCenter.default.post(name: .orangeflixPlaybackStarted, object: nil)
    }

    /// Follows the position of mpv. The watch state, the report and the chat
    /// of a replay move once a second (Go `runItem`).
    private func handlePosition(_ seconds: Double) {
        guard isPlaying else { return }
        position = seconds
        if engine.duration > 0 { duration = engine.duration }
        guard Date().timeIntervalSince(lastTick) >= PlaybackLogic.pollInterval else { return }
        lastTick = Date()
        if let entry = current, entry.kind == .episode, !entry.identifier.isEmpty {
            let percent = PlaybackLogic.progressPercent(position: position, duration: duration)
            app.episodes.setProgress(entry.identifier, percent: percent)
        }
        reportIfDue()
        emitReplayChat()
    }

    /// A file ended: the next entry follows, a failure is shown.
    private func handleEnd(_ reason: MPVPlayer.EndReason) {
        guard isPlaying else { return }
        switch reason {
        case .finished:
            finishCurrent()
        case .failed(let message):
            app.show(PlaybackError.notPlayable(message))
            stop()
        case .stopped:
            break
        }
    }

    /// The end of the file: the next entry follows, or the playback is over.
    private func finishCurrent() {
        guard let entry = current else { return }
        // The end of the file is the safest position: the last reading can
        // be up to a second before it.
        if duration > 0 { position = duration }
        reportFinal()
        if let index = queue.firstIndex(where: { $0.id == entry.id }), index + 1 < queue.count {
            current = queue[index + 1]
            startCurrent()
            return
        }
        stop()
        PlayerWindows.close()
        app.show("Wiedergabe beendet.")
    }

    // MARK: Reporting the position

    /// Reports the position every 30 seconds (Go `playbackRunner.report`).
    private func reportIfDue() {
        guard let entry = current else { return }
        switch entry.kind {
        case .episode:
            let seconds = Int(position)
            // A rewind counts too: the position may go back.
            guard Date().timeIntervalSince(lastReport) >= PlaybackLogic.reportInterval,
                  abs(seconds - lastReportedPosition) >= 5 else { return }
            lastReport = Date()
            lastReportedPosition = seconds
            Self.logger.debug("Fortschritt gemeldet: \(entry.identifier, privacy: .public) \(seconds)s")
            reportProgress(entry, seconds: seconds)
        case .live, .replay:
            guard Date().timeIntervalSince(lastReport) >= PlaybackLogic.reportInterval else { return }
            lastReport = Date()
            reportLive(entry)
        }
    }

    /// Sends the last position, also when the player was closed (Go
    /// `reportFinal`). It goes out only once per entry.
    private func reportFinal() {
        guard !didReportFinal, let entry = current else { return }
        didReportFinal = true
        switch entry.kind {
        case .episode:
            reportProgress(entry, seconds: Int(position))
        case .live, .replay:
            reportLive(entry)
        }
    }

    /// Stores the position of an episode in the account.
    private func reportProgress(_ entry: PlaybackEntry, seconds: Int) {
        guard seconds > 0 else { return }
        let api = app.services.api
        Task {
            do {
                try await app.ensureSession()
            } catch {
                reportFailure(entry.identifier, error)
                return
            }
            do {
                try await api.updateProgress(entry.identifier, seconds: seconds)
            } catch {
                reportFailure(entry.identifier, error)
            }
        }
    }

    /// Stores the position of the live stream or its replay.
    private func reportLive(_ entry: PlaybackEntry) {
        var request = LivestreamProgressRequest()
        switch entry.kind {
        case .live:
            request.mode = .live
            // How far the viewer left the live edge, so the account knows
            // whether the show was watched live.
            request.behindSec = Int(secondsBehindLive(at: Date()).rounded())
        case .replay:
            guard let start = entry.start else { return }
            request.mode = .replay
            request.watchedAt = Int64(start.timeIntervalSince1970.rounded(.down)) + Int64(position)
        case .episode:
            return
        }
        let api = app.services.api
        Task {
            do {
                try await app.ensureSession()
            } catch {
                reportFailure("live", error)
                return
            }
            do {
                _ = try await api.recordLiveProgress(request)
            } catch {
                reportFailure("live", error)
            }
        }
    }

    /// The first failure is logged; the others are quiet (Go
    /// `sendReport`).
    private func reportFailure(_ identifier: String, _ error: any Error) {
        guard !reportErrorLogged else { return }
        reportErrorLogged = true
        if identifier == "live" {
            app.record("Der Live-Fortschritt konnte nicht gespeichert werden: \(error.localizedDescription)")
        } else {
            app.record("Der Fortschritt von \(identifier) konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    // MARK: The chat of a replay

    /// Reads the chat of a replay and places it on the timeline of the
    /// video (Go `loadReplayChat`).
    private func loadReplayChat(for entry: PlaybackEntry) {
        replayChat = []
        replayChatCursor = 0
        guard entry.kind == .replay, !entry.identifier.isEmpty else { return }
        let clipID = entry.identifier
        let end = Double(max(entry.durationSeconds, 1))
        let begin = Int64(entry.start?.timeIntervalSince1970.rounded(.down) ?? 0)
        let api = app.services.api
        Task {
            do {
                let replay = try await api.chatReplay(clipID: clipID, start: 0, end: end)
                var lines: [ReplayChatLine] = []
                for message in replay.messages {
                    let text = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { continue }
                    lines.append(ReplayChatLine(
                        at: PlaybackLogic.replayChatOffset(videoTime: message.videoTime, time: message.time,
                                                           begin: begin, duration: entry.durationSeconds),
                        from: message.username,
                        text: text,
                        unix: message.time))
                }
                lines.sort { $0.at < $1.at }
                replayChat = lines
                replayChatCursor = 0
                if lines.isEmpty {
                    app.show("Kein Chat-Mitschnitt")
                } else {
                    app.show("Chat-Mitschnitt: \(lines.count) Nachrichten")
                }
            } catch {
                app.record("Der Chat-Mitschnitt konnte nicht geladen werden: \(error.localizedDescription)")
                app.show("Chat-Mitschnitt nicht verfügbar", error: true)
            }
        }
    }

    /// Hands the messages of the chat of the replay that belong to the
    /// position on (Go `emitReplayChat`).
    private func emitReplayChat() {
        while replayChatCursor < replayChat.count, replayChat[replayChatCursor].at <= position {
            let line = replayChat[replayChatCursor]
            replayChatCursor += 1
            replayChatHandler?(line)
        }
    }
}
