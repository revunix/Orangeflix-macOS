import Foundation
import Observation

/// The download pipeline of the app (port of `downloadEpisodes`,
/// `DownloadEpisode` and `DownloadNew` of the Go app on top of
/// `DownloadQueue`) and the state of the Downloads screen.
///
/// One queue lives per run: it is created with the settings of the moment
/// when the first download starts, takes every download requested while it
/// runs and is shut down when it runs empty. The download folder stays open
/// (security scope) for the whole run.
@MainActor @Observable final class DownloadCenter: DownloadStarting {
    @ObservationIgnored let app: AppModel

    /// The downloads of this session, oldest first.
    private(set) var jobs: [DownloadJob] = []
    /// The counts of the current or last run; nil before the first run and
    /// after "Liste leeren".
    private(set) var summary: DownloadSummary?
    /// Whether a run is going on.
    private(set) var isRunning = false
    /// Formats whose new episodes are being looked up (`downloadNew`).
    private(set) var discovering: [String] = []

    /// The jobs the queue still works on (sidebar badge).
    var activeCount: Int { jobs.reduce(0) { $0 + ($1.state.isActive ? 1 : 0) } }

    /// Where the files come from; the Orangeflix APIs unless replaced.
    @ObservationIgnored var sources: DownloadSources

    @ObservationIgnored private var run: DownloadRun?
    @ObservationIgnored private var runNumber = 0
    @ObservationIgnored private let notifier = DownloadNotifier()

    /// The queue of a run and the folder access it holds.
    private struct DownloadRun {
        let number: Int
        let queue: DownloadQueue
        let access: ScopedFolderAccess?
    }

    init(app: AppModel) {
        self.app = app
        self.sources = DownloadSources.api(app)
    }

    // MARK: DownloadStarting

    /// Downloads the episodes. Without a format each episode gets the format
    /// of its own pid (Go `DownloadEpisode`); with a format the episodes are
    /// written into the library history first, so the download can be
    /// recorded there (Go `runFormat`).
    func download(_ episodes: [Episode], format: Format?) {
        guard !episodes.isEmpty else { return }
        let requests = episodes.map { request(for: $0, format: format ?? Self.format(of: $0)) }
        guard let format else {
            // Go `DownloadEpisode`: the format of the episode is invented,
            // the library is not touched.
            start(requests)
            return
        }
        Task {
            // Go `runFormat`: the format joins the library and the history
            // is written, so a later check only reports the new episodes.
            do {
                try await app.remember(format)
            } catch {
                app.record("Das Format konnte nicht gemerkt werden: \(error.localizedDescription)", error: true)
            }
            do {
                _ = try await app.recordEpisodes(pid: format.pid, episodes)
            } catch {
                app.record("Die Episodenliste konnte nicht gespeichert werden: \(error.localizedDescription)", error: true)
            }
            start(requests)
        }
    }

    /// Looks up the new episodes of a library format, records them and
    /// downloads them (Go `DownloadNew`).
    func downloadNew(of entry: LibraryFormat) {
        let format = (try? FormatCatalog.lookup(entry.slug))
            ?? Format(pid: entry.pid, slug: entry.slug, title: entry.title, status: FormatStatus(rawValue: entry.status))
        let name = format.title.isEmpty ? entry.description : format.title
        discovering.append(name)
        Task {
            defer {
                if let index = discovering.firstIndex(of: name) { discovering.remove(at: index) }
            }
            let fresh: [Episode]
            do {
                fresh = try await app.discoverNewEpisodes(pid: entry.pid)
            } catch is CancellationError {
                return
            } catch {
                app.show("Die Episoden konnten nicht geladen werden: \(error.localizedDescription)", error: true)
                return
            }
            if fresh.isEmpty {
                app.record("\(format.title): keine neuen Folgen.")
                app.show("\(format.title): keine neuen Folgen.")
                return
            }
            app.record("\(format.title): \(fresh.count) neue Folge(n).")
            start(fresh.map { request(for: $0, format: format) })
        }
    }

    // MARK: Control

    /// Cancels one job: a waiting one is dropped, a running one stops and
    /// keeps its partial file.
    func cancel(_ id: String) {
        guard let queue = run?.queue else { return }
        Task { await queue.cancel(id: id) }
    }

    /// Cancels every waiting and running job.
    func cancelAll() {
        guard let queue = run?.queue else { return }
        Task { await queue.cancelAll() }
    }

    /// Removes the finished jobs from the list.
    func clearFinished() {
        jobs.removeAll { !$0.state.isActive }
        if !isRunning { summary = nil }
    }

    /// Shows the file of a job in the Finder.
    func reveal(_ job: DownloadJob) {
        guard let file = job.file else {
            app.show("Die Datei wurde noch nicht geladen.", error: true)
            return
        }
        AppFormat.reveal(file)
    }

    /// Copies the path of the file of a job into the clipboard.
    func copyPath(_ job: DownloadJob) {
        guard let file = job.file else {
            app.show("Die Datei wurde noch nicht geladen.", error: true)
            return
        }
        AppFormat.copy(file.path(percentEncoded: false))
        app.show("Der Pfad wurde kopiert.")
    }

    /// Deletes the file of a finished job and forgets that it was loaded.
    func deleteFile(of job: DownloadJob) async {
        guard let file = job.file else { return }
        do {
            try await app.deleteDownload(pid: job.pid, identifier: job.id, file: file)
        } catch {
            app.show(error)
            return
        }
        jobs.removeAll { $0.id == job.id && !$0.state.isActive }
    }

    // MARK: Requests

    /// The format of an episode from a mixed list (Go `DownloadEpisode`):
    /// pid and slug from the catalog or "format-<pid>", the episode's format
    /// name as title.
    nonisolated static func format(of episode: Episode) -> Format {
        let known = FormatCatalog.format(pid: episode.pid)
        return Format(
            pid: episode.pid,
            slug: known?.slug ?? "format-\(episode.pid)",
            title: episode.formatName)
    }

    /// The queue request of an episode (Go `namingFor` + sidecar data).
    func request(for episode: Episode, format: Format) -> DownloadRequest {
        let settings = app.settings
        let naming = MediaNaming(
            formatTitle: format.title,
            episodeFormatName: episode.formatName,
            formatSlug: format.slug,
            published: episode.date,
            number: episode.number,
            layout: MediaLayout(rawValue: settings.layout.rawValue) ?? .compat)
        let metadata = EpisodeMetadata(
            identifier: episode.identifier,
            pid: episode.pid,
            number: episode.number,
            title: episode.title,
            formatName: episode.formatName,
            description: episode.description,
            published: episode.date,
            duration: episode.duration,
            durationSeconds: episode.durationSeconds,
            thumbnailURL: episode.thumb,
            participants: episode.participants.map(\.name))
        return DownloadRequest(
            id: episode.identifier,
            pid: format.pid,
            naming: naming,
            metadata: metadata,
            sidecars: SidecarOptions(thumbnail: settings.thumb, metadata: settings.meta))
    }

    // MARK: Run

    /// Adds the requests to the running queue or starts a new run.
    func start(_ requests: [DownloadRequest]) {
        let wanted = requests.filter { request in
            !jobs.contains { $0.id == request.id && $0.state.isActive }
        }
        guard !wanted.isEmpty else {
            app.selection = .downloads
            return
        }
        if run == nil {
            guard openRun() else { return }
        }
        guard let queue = run?.queue else { return }
        for request in wanted {
            let job = DownloadJob(id: request.id, pid: request.pid, label: request.naming.episodePrefix)
            if let index = jobs.firstIndex(where: { $0.id == request.id }) {
                jobs.remove(at: index)
            }
            jobs.append(job)
        }
        app.selection = .downloads
        Task { await queue.enqueue(wanted) }
    }

    /// Opens the download folder and creates the queue of a new run.
    private func openRun() -> Bool {
        let folder: (url: URL, access: ScopedFolderAccess?)
        do {
            folder = try app.accessDownloadFolder()
        } catch {
            app.show(error)
            return false
        }
        let settings = app.settings
        let queue = DownloadQueue(
            root: folder.url,
            configuration: DownloadQueueConfiguration(parallel: settings.parallel, delay: settings.delay, force: false),
            downloaderOptions: DownloaderOptions(
                userAgent: APIDefaults.userAgent,
                limitBytesPerSecond: settings.limitBytesPerSecond),
            resolveSource: sources.resolve,
            missingSubtitles: sources.missingSubtitles)
        runNumber += 1
        let number = runNumber
        // The loop ends when the queue finishes its stream on shutdown; it
        // needs no handle.
        _ = Task { @MainActor [weak self] in
            for await event in queue.events {
                self?.handle(event, run: number)
            }
        }
        run = DownloadRun(number: number, queue: queue, access: folder.access)
        summary = DownloadSummary()
        isRunning = true
        notifier.prepare()
        return true
    }

    /// Ends the run: releases the folder and shuts the queue down.
    private func closeRun() {
        guard let current = run else { return }
        run = nil
        isRunning = false
        current.access?.stop()
        Task { await current.queue.shutdown() }
    }

    // MARK: Events

    private func handle(_ event: DownloadEvent, run number: Int) {
        guard run?.number == number else { return }
        switch event {
        case .log(let message, let isError):
            app.record(message, error: isError)
        case .queued(let id, _, let label, let file):
            update(id) {
                $0.label = label
                $0.file = file
                $0.state = .waiting
            }
        case .progress(let id, _, let label, let progress):
            update(id) {
                $0.label = label
                $0.state = .loading
                $0.done = progress.done
                $0.total = progress.total
                $0.bytesPerSecond = progress.bytesPerSecond
                $0.remaining = progress.estimatedRemaining
            }
        case .skipped(let id, let pid, let label, let file):
            update(id) {
                $0.label = label
                $0.file = file
                $0.state = .skipped
            }
            summary?.skipped += 1
            markDownloaded(pid: pid, identifier: id, file: file)
        case .done(let id, let pid, let label, let file, let size):
            update(id) {
                $0.label = label
                $0.file = file
                $0.state = .done
                $0.done = size
                $0.total = max($0.total, size)
                $0.remaining = nil
            }
            summary?.done += 1
            markDownloaded(pid: pid, identifier: id, file: file)
        case .failed(let id, _, let label, let message):
            update(id) {
                $0.label = label
                $0.state = .failed
                $0.message = message
                $0.remaining = nil
            }
            summary?.failed += 1
            if summary?.firstFailure == nil { summary?.firstFailure = message }
            app.banner = Banner(text: message, isError: true)
        case .cancelled(let id, _, let label):
            update(id) {
                if $0.file == nil { $0.label = label }
                $0.state = .cancelled
                $0.remaining = nil
            }
            summary?.cancelled += 1
        case .idle:
            // Requests added after the queue ran empty are still waiting:
            // their events follow, the run goes on.
            guard !jobs.contains(where: { $0.state.isActive }) else { return }
            finishRun()
        }
    }

    private func update(_ id: String, _ change: (inout DownloadJob) -> Void) {
        guard let index = jobs.lastIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    /// Records the file in the library and in the session state (Go
    /// `markDownloaded`); a library failure is only logged for the session,
    /// a row that is not there is shown as a banner.
    private func markDownloaded(pid: Int, identifier: String, file: URL) {
        app.episodes.markDownloaded(identifier, file: file)
        let store = app.services.store
        let path = file.path(percentEncoded: false)
        Task {
            do {
                let changed = try await store.markDownloaded(pid: pid, identifier: identifier, path: path)
                guard changed == 0 else { return }
                app.show("Der Download wurde nicht in der Bibliothek vermerkt.", error: true)
                app.record("\(identifier) steht nicht in der Bibliothek von Format \(pid).", error: true)
            } catch {
                app.record("Der Download konnte nicht in der Bibliothek vermerkt werden: \(error.localizedDescription)")
            }
        }
    }

    private func finishRun() {
        let result = summary ?? DownloadSummary()
        closeRun()
        if result.failed > 0 {
            app.show(result.failureText, error: true)
        } else {
            app.show(result.finishedText)
        }
        notifier.notifyFinished(result)
    }
}
