import Foundation

/// Where the queue gets the files of an episode from. The app uses the
/// Orangeflix APIs (`api(_:)`); a different source (a local test server)
/// can be set on `DownloadCenter.sources`.
struct DownloadSources: Sendable {
    /// Resolves the file of the requested quality right before the download.
    var resolve: @Sendable (DownloadRequest) async throws -> DownloadSource
    /// The subtitle URLs of an episode that was downloaded without them;
    /// nil when no source of subtitles exists.
    var missingSubtitles: (@Sendable (DownloadRequest) async -> [URL])?

    /// The version 3 API with the legacy API as fallback (Go `episodeSource`).
    @MainActor static func api(_ app: AppModel) -> DownloadSources {
        DownloadSources(
            resolve: { request in try await DownloadSourceLookup.resolve(request.id, app: app) },
            missingSubtitles: { request in await DownloadSourceLookup.subtitles(request.id, app: app) })
    }
}

/// The files of an episode as the APIs report them (Go `episodeSource`).
struct DownloadEpisodeFiles: Sendable, Hashable {
    /// The available qualities.
    var files: [ClipFile]
    /// The subtitle addresses.
    var subtitles: [String] = []
    /// Basic auth of the legacy API; nil for the delivery network.
    var credentials: DownloadCredentials?
}

/// Port of `episodeSource`, `SelectFile`, `ToHTTPS`, `PlaybackDownloadURL`
/// and `loadMissingSubtitles` of `internal/app/pipeline.go`.
@MainActor enum DownloadSourceLookup {
    /// The file of the requested quality as a queue source.
    static func resolve(_ identifier: String, app: AppModel) async throws -> DownloadSource {
        let found = try await files(identifier, app: app)
        let quality = app.settings.quality.rawValue
        let selection = try found.files.select(quality: quality)
        if !selection.exact {
            app.record("Qualität \(quality) ist nicht verfügbar, nehme \(selection.file.desc).")
        }
        // The URL of the file carries a token, so it is resolved right
        // before the download and never kept.
        var address = try app.legacy.toHTTPS(selection.file.url)
        // The official endpoint records the download in the statistics and
        // resolves the short-lived delivery URL. The direct URL stays the
        // fallback, so a statistics failure never blocks a download.
        if !selection.file.file.isEmpty, await !app.services.api.session().accessToken.isEmpty {
            do {
                let resolved = try await app.services.api.playbackDownloadURL(clipID: identifier, file: selection.file.file)
                if let normalized = try? app.legacy.toHTTPS(resolved) { address = normalized }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                app.record("Der offizielle Download für \(identifier) ist nicht erreichbar (\(error.localizedDescription)), nutze die direkte Adresse.")
            }
        }
        return try source(selection.file, address: address, files: found)
    }

    /// Maps the chosen file to the queue's source: resolution label,
    /// extension, size and subtitles.
    nonisolated static func source(_ file: ClipFile, address: String, files: DownloadEpisodeFiles) throws -> DownloadSource {
        guard let url = URL(string: address) else { throw APIError.invalidURL(address) }
        return DownloadSource(
            url: url,
            resolution: file.resolutionLabel,
            fileExtension: file.fileExtension,
            credentials: files.credentials,
            expectedSize: file.size > 0 ? file.size : nil,
            subtitles: files.subtitles.compactMap { URL(string: $0) })
    }

    /// The files of an episode: version 3 playback (delivery network, no
    /// credentials), else the legacy clip with basic auth.
    static func files(_ identifier: String, app: AppModel) async throws -> DownloadEpisodeFiles {
        var sessionReady = true
        do {
            try await app.ensureSession()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            sessionReady = false
        }
        if sessionReady {
            do {
                let playback = try await app.services.api.playback(identifier)
                if !playback.files.isEmpty {
                    return DownloadEpisodeFiles(files: playback.files, subtitles: playback.subtitleURLs)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                app.record("Die Version-3-API liefert keine Datei für \(identifier) (\(error.localizedDescription)), nutze die alte API.")
            }
        }
        let clip = try await app.legacy.clip(identifier)
        let login = app.legacyCredentials
        return DownloadEpisodeFiles(
            files: clip.files,
            credentials: DownloadCredentials(username: login.username, password: login.password))
    }

    /// The subtitles of an episode that was downloaded before the program
    /// stored them; only the version 3 API knows them.
    static func subtitles(_ identifier: String, app: AppModel) async -> [URL] {
        do {
            try await app.ensureSession()
        } catch {
            return []
        }
        do {
            let playback = try await app.services.api.playback(identifier)
            return playback.subtitleURLs.compactMap { URL(string: $0) }
        } catch is CancellationError {
            return []
        } catch {
            app.record("Die Untertitel von \(identifier) konnten nicht abgefragt werden: \(error.localizedDescription)")
            return []
        }
    }
}
