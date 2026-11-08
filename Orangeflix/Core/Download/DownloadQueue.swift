import Foundation

/// The download queue (port of `downloadEpisodes`/`downloadEpisode` of the
/// Go app plus its sidecar handling). Items run in order with at most
/// `parallel` (1...8) at the same time:
///
/// - `parallel == 1`: the `delay` is waited between two downloads (not
///   before the first one of a busy period), like the sequential Go loop.
/// - `parallel > 1`: every item waits the `delay` in its slot before it
///   starts, like the Go worker pool.
///
/// Per item: skip check (`DownloadManager.prepare`, honoring `force`) →
/// `resolveSource` (the short-lived file URL is resolved only now) →
/// download into "<target>.part" with resume/retries/checksum → final name →
/// subtitles, thumbnail and metadata sidecars. A skipped episode still gets
/// its missing subtitles (via `missingSubtitles`), thumbnail and metadata.
///
/// Sandbox: the queue only writes below `root`. The App layer must call
/// `startAccessingSecurityScopedResource()` on the folder before enqueueing
/// and stop it after the `.idle` event (or after `shutdown()`).
actor DownloadQueue {
    /// All events of the queue. There is one consumer; the stream ends with
    /// `shutdown()`.
    nonisolated let events: AsyncStream<DownloadEvent>
    private nonisolated let continuation: AsyncStream<DownloadEvent>.Continuation

    /// The root of the downloads.
    nonisolated let root: URL
    nonisolated let downloader: Downloader
    private(set) var configuration: DownloadQueueConfiguration
    private nonisolated let resolveSource: @Sendable (DownloadRequest) async throws -> DownloadSource
    private nonisolated let missingSubtitles: (@Sendable (DownloadRequest) async -> [URL])?

    private var pending: [DownloadRequest] = []
    private var running: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private var busy = false
    private var failures = 0
    private var firstFailure: String?

    /// - Parameters:
    ///   - root: the download folder.
    ///   - resolveSource: resolves the file of the requested quality right
    ///     before the download (API layer; throw `CancellationError` on
    ///     cancellation).
    ///   - missingSubtitles: subtitle URLs of an already downloaded episode
    ///     that has none next to it; nil when the source of subtitles (the
    ///     version 3 API) is not available.
    init(root: URL,
         configuration: DownloadQueueConfiguration = DownloadQueueConfiguration(),
         downloaderOptions: DownloaderOptions = DownloaderOptions(),
         resolveSource: @escaping @Sendable (DownloadRequest) async throws -> DownloadSource,
         missingSubtitles: (@Sendable (DownloadRequest) async -> [URL])? = nil) {
        let (events, continuation) = AsyncStream.makeStream(of: DownloadEvent.self)
        self.events = events
        self.continuation = continuation
        self.root = root
        self.configuration = configuration
        self.resolveSource = resolveSource
        self.missingSubtitles = missingSubtitles
        downloader = Downloader(options: downloaderOptions) { message in
            continuation.yield(.log(message: message, isError: false))
        }
    }

    // MARK: Control

    /// Appends the requests; ids that are already queued or running are
    /// ignored.
    func enqueue(_ requests: [DownloadRequest]) {
        for request in requests where running[request.id] == nil && !pending.contains(where: { $0.id == request.id }) {
            pending.append(request)
        }
        if configuration.parallel > 1 && !pending.isEmpty && running.isEmpty {
            log("Lade \(configuration.parallel) Folge(n) gleichzeitig.")
        }
        pump()
    }

    /// Cancels one item: a waiting item is removed, a running one stops and
    /// keeps its partial file.
    func cancel(id: String) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            let request = pending.remove(at: index)
            continuation.yield(.cancelled(id: request.id, pid: request.pid, label: request.naming.episodePrefix))
            pump()
        } else {
            running[id]?.task.cancel()
        }
    }

    /// Cancels every waiting and running item.
    func cancelAll() {
        let waiting = pending
        pending.removeAll()
        for request in waiting {
            continuation.yield(.cancelled(id: request.id, pid: request.pid, label: request.naming.episodePrefix))
        }
        for entry in running.values { entry.task.cancel() }
        pump()
    }

    /// Cancels everything, waits for the running items and ends the event
    /// stream.
    func shutdown() async {
        cancelAll()
        let tasks = running.values.map(\.task)
        for task in tasks { await task.value }
        continuation.finish()
    }

    // MARK: Scheduling

    private func pump() {
        while running.count < configuration.parallel, !pending.isEmpty {
            let request = pending.removeFirst()
            let delay = configuration.parallel <= 1 ? (busy ? configuration.delay : 0) : configuration.delay
            let force = configuration.force
            busy = true
            let token = UUID()
            let task = Task {
                await self.process(request, delay: delay, force: force)
                self.finished(id: request.id, token: token)
            }
            running[request.id] = (token, task)
        }
        if busy && running.isEmpty && pending.isEmpty {
            busy = false
            continuation.yield(.idle(failures: failures, firstFailure: firstFailure))
            failures = 0
            firstFailure = nil
        }
    }

    private func finished(id: String, token: UUID) {
        if running[id]?.token == token {
            running[id] = nil
        }
        pump()
    }

    private func recordFailure(_ request: DownloadRequest, label: String, message: String) {
        failures += 1
        if firstFailure == nil { firstFailure = message }
        continuation.yield(.log(message: "FEHLER: \(message)", isError: true))
        continuation.yield(.failed(id: request.id, pid: request.pid, label: label, message: message))
    }

    // MARK: One item

    private nonisolated func log(_ message: String) {
        continuation.yield(.log(message: message, isError: false))
    }

    private nonisolated func cancelled(_ request: DownloadRequest, label: String) {
        log("Abgebrochen, die Teildatei bleibt für den nächsten Lauf erhalten.")
        continuation.yield(.cancelled(id: request.id, pid: request.pid, label: label))
    }

    @concurrent
    private nonisolated func process(_ request: DownloadRequest, delay: Double, force: Bool) async {
        let prefix = request.naming.episodePrefix
        if delay > 0 {
            await downloader.options.sleep(.milliseconds(Int64(delay * 1000)))
        }
        if Task.isCancelled {
            continuation.yield(.cancelled(id: request.id, pid: request.pid, label: prefix))
            return
        }

        let manager = DownloadManager(root: root, force: force) { [continuation] message in
            continuation.yield(.log(message: message, isError: false))
        }
        if let existing = manager.prepare(request.naming) {
            // The resolution is not known before the clip was loaded, so the
            // label is the episode without the media tag.
            log("Übersprungen (bereits vorhanden): \(prefix)")
            continuation.yield(.skipped(id: request.id, pid: request.pid, label: prefix, file: existing))
            if let missingSubtitles, !DownloadSidecars.subtitlePresent(for: existing) {
                await saveSubtitles(await missingSubtitles(request), video: existing)
            }
            await saveSidecars(request, video: existing)
            return
        }

        let source: DownloadSource
        do {
            source = try await resolveSource(request)
        } catch is CancellationError {
            cancelled(request, label: prefix)
            return
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await recordFailure(request, label: prefix,
                                message: DownloadError.sourceUnavailable(id: request.id, reason: reason).localizedDescription)
            return
        }

        var naming = request.naming
        naming.resolution = source.resolution
        let label = naming.episodeName
        do {
            try manager.ensureDirectory(naming)
        } catch {
            await recordFailure(request, label: label, message: error.localizedDescription)
            return
        }
        let target = manager.target(naming, extension: source.fileExtension)
        continuation.yield(.queued(id: request.id, pid: request.pid, label: label, file: target))
        log("Lade \(label) ...")

        let result: DownloadResult
        do {
            result = try await downloader.download(
                from: source.url, to: target, credentials: source.credentials,
                expectedSize: source.expectedSize
            ) { [continuation] progress in
                continuation.yield(.progress(id: request.id, pid: request.pid, label: label, progress: progress))
            }
        } catch is CancellationError {
            cancelled(request, label: label)
            return
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await recordFailure(request, label: label,
                                message: DownloadError.downloadFailed(id: request.id, reason: reason).localizedDescription)
            return
        }
        log("Fertig: \(result.file.path(percentEncoded: false)) (\(Self.humanSize(result.size)))")
        // The sidecars belong to the finished file, so they are written
        // before the run is reported.
        await saveSubtitles(source.subtitles, video: result.file)
        await saveSidecars(request, video: result.file)
        continuation.yield(.done(id: request.id, pid: request.pid, label: label, file: result.file, size: result.size))
    }

    /// Stores the subtitles next to the video.
    private nonisolated func saveSubtitles(_ subtitles: [URL], video: URL) async {
        for (index, url) in subtitles.enumerated() {
            let target = DownloadSidecars.subtitleFile(for: video, index: index)
            do {
                _ = try await downloader.download(from: url, to: target)
                log("Untertitel: \(target.path(percentEncoded: false))")
            } catch {
                log("Die Untertitel konnten nicht gespeichert werden: \(error.localizedDescription)")
            }
        }
    }

    /// Stores the requested thumbnail and metadata sidecars.
    private nonisolated func saveSidecars(_ request: DownloadRequest, video: URL) async {
        if request.sidecars.thumbnail {
            await saveThumbnail(request.metadata.thumbnailURL, target: DownloadSidecars.thumbnailFile(for: video))
        }
        if request.sidecars.metadata {
            do {
                let file = try DownloadSidecars.writeMetadata(request.metadata, video: video)
                log("Metadaten: \(file.path(percentEncoded: false))")
            } catch {
                log("Die Metadaten konnten nicht geschrieben werden: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches the preview image when it is not there yet.
    private nonisolated func saveThumbnail(_ address: String, target: URL) async {
        guard !address.isEmpty else {
            log("Kein Vorschaubild für diese Folge verfügbar.")
            return
        }
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            log("Vorschaubild vorhanden: \(target.path(percentEncoded: false))")
            return
        }
        do {
            guard let url = URL(string: address) else { throw DownloadError.invalidURL(address) }
            _ = try await downloader.download(from: url, to: target)
            log("Vorschaubild: \(target.path(percentEncoded: false))")
        } catch {
            log("Das Vorschaubild konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    /// Formats a number of bytes like the Go tool ("1.5 MiB").
    nonisolated static func humanSize(_ size: Int64) -> String {
        let unit = 1024.0
        if size < 1024 { return "\(size) B" }
        var value = Double(size)
        for name in ["KiB", "MiB", "GiB", "TiB"] {
            value /= unit
            if value < unit { return String(format: "%.1f %@", value, name) }
        }
        return String(format: "%.1f PiB", value)
    }
}
