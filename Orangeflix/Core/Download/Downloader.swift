import CryptoKit
import Foundation
import os

/// Settings of the downloader (port of the fields of Go's `Downloader`).
struct DownloaderOptions: Sendable {
    /// The browser identification of the requests; empty sends none.
    var userAgent: String = ""
    /// Longest time without data before a try counts as broken. A total
    /// limit would abort every large file on a slow line.
    var stallTimeout: Duration = .seconds(120)
    /// Number of tries; every try continues the partial file of the one
    /// before.
    var attempts: Int = 3
    /// Shared speed cap in bytes per second; 0 means no cap. Parallel
    /// downloads of the same downloader share it.
    var limitBytesPerSecond: Int64 = 0
    /// Injectable pause (tests); must return early on cancellation.
    var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    /// Session configuration; nil uses an ephemeral configuration without
    /// cache and cookies.
    var configuration: URLSessionConfiguration?
}

/// Downloads a file over HTTP into "<target>.part", continues an existing
/// partial file with a Range request, retries broken transfers with
/// exponential backoff (1 s, 2 s, ... capped at 30 s), verifies the MD5 the
/// server announces and renames the partial file atomically when complete.
///
/// The downloader only touches the paths it is given; inside the App
/// Sandbox the caller must hold security-scoped access to the destination
/// folder for the whole call.
final class Downloader: Sendable {
    /// The ending of the file of an unfinished download.
    static let partSuffix = ".part"
    /// Shortest time between two progress reports.
    static let progressInterval: Duration = .milliseconds(500)
    /// Cap of the pause between two tries.
    static let maxRetryDelay: Duration = .seconds(30)

    let options: DownloaderOptions
    private let session: URLSession
    private let paceNext = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)
    private let logSink: (@Sendable (String) -> Void)?
    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "download")

    /// - Parameter log: receives the German log lines (Go `Logf`).
    init(options: DownloaderOptions = DownloaderOptions(), log: (@Sendable (String) -> Void)? = nil) {
        self.options = options
        self.logSink = log
        let configuration: URLSessionConfiguration
        if let custom = options.configuration {
            configuration = custom
        } else {
            configuration = .ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
        }
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // The own stall watchdog decides about a silent transfer; the session
        // still needs a limit, otherwise a dead server holds the queue for
        // days. Two minutes without an answer, six hours for one file.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    private func log(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
        logSink?(message)
    }

    /// Loads `url` into `target`. An interrupted download is continued from
    /// "<target>.part"; the partial file stays when all tries fail (or the
    /// task is cancelled), so the next run continues it.
    ///
    /// - Parameters:
    ///   - expectedSize: total used for the progress when the server does
    ///     not announce a length.
    ///   - progress: called at most every 500 ms and once at the end.
    /// - Throws: `DownloadError` or `CancellationError`.
    @concurrent
    func download(from url: URL, to target: URL, credentials: DownloadCredentials? = nil,
                  expectedSize: Int64? = nil,
                  progress: (@Sendable (DownloadProgress) -> Void)? = nil) async throws -> DownloadResult {
        guard target.isFileURL, !target.path(percentEncoded: false).isEmpty else { throw DownloadError.noTarget }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw DownloadError.invalidURL(url.absoluteString)
        }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw DownloadError.fileSystem(error.localizedDescription)
        }
        let attempts = max(options.attempts, 1)
        var attempt = 1
        while true {
            do {
                return try await self.attempt(url: url, target: target, credentials: credentials,
                                              expectedSize: expectedSize, progress: progress)
            } catch let error as DownloadError where error.isRetryable && attempt < attempts && !Task.isCancelled {
                let delay = min(Duration.seconds(1 << (attempt - 1)), Self.maxRetryDelay)
                log("Download unterbrochen (\(error.localizedDescription)), neuer Versuch \(attempt + 1)/\(attempts) in \(Int(delay.components.seconds))s")
                await options.sleep(delay)
                try Task.checkCancellation()
                attempt += 1
            }
        }
    }

    // MARK: One try

    private func attempt(url: URL, target: URL, credentials: DownloadCredentials?, expectedSize: Int64?,
                         progress: (@Sendable (DownloadProgress) -> Void)?) async throws -> DownloadResult {
        try Task.checkCancellation()
        let fm = FileManager.default
        let part = URL(fileURLWithPath: target.path(percentEncoded: false) + Self.partSuffix)

        var resumeFrom: Int64 = 0
        if let attributes = try? fm.attributesOfItem(atPath: part.path(percentEncoded: false)),
           attributes[.type] as? FileAttributeType == .typeRegular,
           let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 {
            resumeFrom = size
            log("Fortsetzung ab \(size) Bytes")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Transparent decompression would break the byte counts of a resume.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !options.userAgent.isEmpty {
            request.setValue(options.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let credentials {
            if !credentials.bearer.isEmpty {
                request.setValue("Bearer " + credentials.bearer, forHTTPHeaderField: "Authorization")
            } else if !credentials.username.isEmpty || !credentials.password.isEmpty {
                let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
                request.setValue("Basic " + token, forHTTPHeaderField: "Authorization")
            }
        }
        if resumeFrom > 0 {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
        }

        let transfer = DownloadTransfer(request: request, session: session)
        let watchdog = DownloadWatchdog(timeout: options.stallTimeout) { [weak transfer] in
            transfer?.stop(.stalled)
        }
        defer {
            watchdog.cancel()
            transfer.cancel()
        }

        // Turns a failure of the connection into the matching error.
        func failure(_ error: any Error) -> any Error {
            if let reason = transfer.stopReason { return reason }
            if Task.isCancelled { return CancellationError() }
            if let error = error as? DownloadError { return error }
            return DownloadError.transport(error.localizedDescription)
        }

        var iterator = transfer.chunks.makeAsyncIterator()
        let response: HTTPURLResponse
        do {
            guard case .response(let first)? = try await iterator.next() else {
                throw DownloadError.transport("keine Antwort des Servers")
            }
            response = first
        } catch {
            throw failure(error)
        }
        watchdog.reset()

        switch response.statusCode {
        case 401:
            throw DownloadError.unauthorized
        case 200:
            if resumeFrom > 0 {
                log("Server unterstützt keine Fortsetzung, Download beginnt von vorn")
                resumeFrom = 0
            }
        case 206:
            if resumeFrom > 0 {
                let start = response.value(forHTTPHeaderField: "Content-Range").flatMap(DownloadHeaders.rangeStart)
                if start != resumeFrom {
                    // The partial file does not fit the answer; the next try
                    // starts from the beginning.
                    try? fm.removeItem(at: part)
                    throw DownloadError.resumeRejected
                }
            }
        case 416 where resumeFrom > 0:
            try? fm.removeItem(at: part)
            throw DownloadError.partialFileMismatch
        default:
            throw DownloadError.httpStatus(response.statusCode)
        }

        // The checksum covers the whole file, so the partial file is hashed
        // first; rangeHash covers the new data only, for servers that
        // announce the checksum of the transferred range.
        var fullHash = Insecure.MD5()
        var rangeHash = Insecure.MD5()
        if resumeFrom > 0 {
            try Self.hashFile(part, into: &fullHash)
        }

        let handle: FileHandle
        do {
            if resumeFrom > 0 {
                handle = try FileHandle(forWritingTo: part)
                try handle.seekToEnd()
            } else {
                guard fm.createFile(atPath: part.path(percentEncoded: false), contents: nil) else {
                    throw DownloadError.fileSystem("Die Teildatei kann nicht angelegt werden: \(part.path(percentEncoded: false))")
                }
                handle = try FileHandle(forWritingTo: part)
            }
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.fileSystem(error.localizedDescription)
        }

        var written = resumeFrom
        var transferred: Int64 = 0
        let announced = DownloadHeaders.contentLength(response)
        let total = announced > 0 ? announced : max(expectedSize ?? 0, 0)
        let clock = ContinuousClock()
        let started = clock.now
        var lastReport = started
        func report() {
            let elapsed = clock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            progress?(DownloadProgress(done: written, total: total, transferred: transferred, elapsed: seconds))
        }

        do {
            while let chunk = try await iterator.next() {
                guard case .data(let data) = chunk else { continue }
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    throw DownloadError.fileSystem(error.localizedDescription)
                }
                fullHash.update(data: data)
                rangeHash.update(data: data)
                written += Int64(data.count)
                transferred += Int64(data.count)
                transfer.consumed(data.count)
                // The wait of the speed cap is not a stall.
                watchdog.pause()
                await pace(Int64(data.count))
                watchdog.reset()
                if progress != nil, clock.now - lastReport >= Self.progressInterval {
                    lastReport = clock.now
                    report()
                }
            }
        } catch {
            // The partial file stays: the next try continues it.
            try? handle.close()
            throw failure(error)
        }
        report()
        do {
            try handle.close()
        } catch {
            throw DownloadError.fileSystem(error.localizedDescription)
        }
        try Task.checkCancellation()

        if announced > 0 && written != announced {
            // The partial file stays: the next try continues it.
            throw DownloadError.incomplete(written: written, total: announced)
        }

        let checksum = DownloadHeaders.hex(fullHash.finalize())
        let expected = DownloadHeaders.expectedChecksum(response)
        if !expected.isEmpty && expected != checksum {
            let rangeMatches = resumeFrom > 0 && expected == DownloadHeaders.hex(rangeHash.finalize())
            if !rangeMatches {
                // The partial file is broken: the next run starts over.
                try? fm.removeItem(at: part)
                throw DownloadError.checksumMismatch
            }
        }

        try Self.atomicRename(part, to: target)
        return DownloadResult(file: target, size: written, md5: checksum)
    }

    // MARK: Helpers

    /// Waits so the shared speed cap is kept across every download of this
    /// downloader.
    private func pace(_ count: Int64) async {
        let limit = options.limitBytesPerSecond
        guard limit > 0, count > 0 else { return }
        let now = ContinuousClock.now
        let wait = paceNext.withLock { next -> Duration in
            let slot = max(next ?? now, now).advanced(by: .nanoseconds(count * 1_000_000_000 / limit))
            next = slot
            return slot - now
        }
        if wait > .zero {
            await options.sleep(wait)
        }
    }

    private static func hashFile(_ file: URL, into hash: inout Insecure.MD5) throws {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
                hash.update(data: data)
            }
        } catch {
            throw DownloadError.fileSystem(error.localizedDescription)
        }
    }

    /// rename(2): atomic on the same volume and replaces an existing target,
    /// like Go's os.Rename.
    static func atomicRename(_ source: URL, to target: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { src in
            target.withUnsafeFileSystemRepresentation { dst -> Int32 in
                guard let src, let dst else { return -1 }
                return rename(src, dst)
            }
        }
        if result != 0 {
            let reason = String(cString: strerror(errno))
            throw DownloadError.fileSystem("Die Datei konnte nicht umbenannt werden: \(reason)")
        }
    }
}

/// Fires once when no activity was reported for the timeout. `pause()`
/// stops the clock (speed cap waits), `reset()` restarts it.
final class DownloadWatchdog: Sendable {
    private let timeout: Duration
    private let deadline: OSAllocatedUnfairLock<ContinuousClock.Instant?>
    private let watcher: Task<Void, Never>

    init(timeout: Duration, fire: @escaping @Sendable () -> Void) {
        let deadline = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: ContinuousClock.now.advanced(by: timeout))
        self.timeout = timeout
        self.deadline = deadline
        watcher = Task.detached {
            while !Task.isCancelled {
                guard let due = deadline.withLock({ $0 }) else {
                    try? await Task.sleep(for: timeout)
                    continue
                }
                if ContinuousClock.now >= due {
                    fire()
                    return
                }
                try? await Task.sleep(until: due, clock: .continuous)
            }
        }
    }

    /// Restarts the timeout.
    func reset() {
        let due = ContinuousClock.now.advanced(by: timeout)
        deadline.withLock { $0 = due }
    }

    /// Stops the clock until the next `reset()`.
    func pause() {
        deadline.withLock { $0 = nil }
    }

    func cancel() {
        watcher.cancel()
    }
}
