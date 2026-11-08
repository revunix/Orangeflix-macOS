import Foundation

/// Episode loading with the Go fallbacks (`app/flows.go`, `app/v3.go`,
/// `app/library.go`), shared by the formats list, the library check and the
/// downloads.
extension AppModel {
    /// All episodes of a format, ascending by number: API v3 (50 per page),
    /// else the RSS feed, else the legacy JSON feed (Go `episodes`). A list
    /// loaded within `CacheTTL.episodes` comes from the `ResponseCache`.
    /// - Parameter force: skips the stored list and asks the API.
    func allEpisodes(pid: Int, force: Bool = false) async throws -> [Episode] {
        if !force, let cached = await cachedEpisodeList(pid: pid) {
            record("Episoden aus dem Zwischenspeicher geladen.")
            return cached
        }
        do {
            let episodes = try await episodesV3(pid: pid, force: force)
            if !episodes.isEmpty {
                record("Episoden via API v3 geladen.")
                await storeEpisodeList(episodes, pid: pid)
                return episodes
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AuthError {
            throw error
        } catch {
            record("Die API v3 ist nicht erreichbar (\(error.localizedDescription)), nutze den RSS-Feed.")
        }

        let submodule = max(1, settings.submodule)
        do {
            let episodes = try await legacy.episodesViaRSS(pid: pid, submodule: submodule, quality: "hd")
            if !episodes.isEmpty {
                record("Episoden via RSS-Feed geladen.")
                await storeEpisodeList(episodes, pid: pid)
                return episodes
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            record("RSS-Feed nicht verfügbar (\(error.localizedDescription)), nutze die JSON-API.")
        }
        return try await legacy.episodes(pid: pid)
    }

    /// The cache key of the episode list of a format.
    private func episodeListKey(pid: Int) -> String {
        "\(cacheScope)|episodes/\(pid)"
    }

    /// The stored episode list of a format; nil when there is none or when
    /// it is older than `CacheTTL.episodes`.
    private func cachedEpisodeList(pid: Int) async -> [Episode]? {
        let key = episodeListKey(pid: pid)
        guard let entry = await services.cache.value(for: key) else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) <= CacheTTL.episodes else { return nil }
        do {
            return try JSONDecoder().decode([Episode].self, from: entry.body)
        } catch {
            // Unreadable entries are dropped instead of served forever.
            await services.cache.remove(key)
            return nil
        }
    }

    /// Stores the episode list of a format.
    private func storeEpisodeList(_ episodes: [Episode], pid: Int) async {
        do {
            await services.cache.store(try JSONEncoder().encode(episodes), for: episodeListKey(pid: pid))
        } catch {
            record("Die Episodenliste wurde nicht gespeichert: \(error.localizedDescription)", error: true)
        }
    }

    /// The v3 feed in pages of 50 up to offset 5000, sorted ascending by
    /// number (Go `EpisodesV3`).
    /// - Parameter force: skips the stored feed pages.
    func episodesV3(pid: Int, force: Bool = false) async throws -> [Episode] {
        try await ensureSession()
        let pageSize = 50
        var all: [Episode] = []
        var offset = 0
        while offset < 5000 {
            let clips = try await services.api.feed(FeedQuery(
                offset: offset, count: pageSize, includePremium: true, includeEarlyAccess: true, magazineId: pid),
                refresh: force)
            if clips.isEmpty { break }
            all.append(contentsOf: clips.map(\.episode))
            if clips.count < pageSize { break }
            offset += pageSize
        }
        return LegacyAPIClient.sortedByNumber(all)
    }

    /// One page of a format's episodes, newest first: v3 (50 per page), else
    /// one RSS page, else one legacy feed page (Go `episodesPage`).
    func episodesPage(pid: Int, page: Int) async throws -> [Episode] {
        if (try? await ensureSession()) != nil {
            do {
                let clips = try await services.api.feed(FeedQuery(
                    offset: (page - 1) * 50, count: 50, includePremium: true, includeEarlyAccess: true, magazineId: pid))
                return clips.map(\.episode)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // fall through to the legacy sources
            }
        }
        let submodule = max(1, settings.submodule)
        do {
            return try await legacy.rssPage(pid: pid, submodule: submodule, page: page, quality: "hd")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await legacy.feed(pid: pid, page: page)
        }
    }

    /// The episodes not known to the library yet: up to five pages, stopping
    /// at the first known identifier (Go `newEpisodes`).
    func unknownEpisodes(pid: Int) async throws -> [Episode] {
        let known = try await services.store.knownIdentifiers(pid: pid)
        var episodes: [Episode] = []
        for page in 1...5 {
            let listed: [Episode]
            do {
                listed = try await episodesPage(pid: pid, page: page)
            } catch {
                if episodes.isEmpty || error is CancellationError { throw error }
                break
            }
            if listed.isEmpty { break }
            var stop = false
            for episode in listed {
                if known.contains(episode.identifier) {
                    stop = true
                    break
                }
                episodes.append(episode)
            }
            if stop { break }
        }
        return episodes
    }

    /// Finds the new episodes of a library format and records them in the
    /// history; returns the fresh ones in feed order (Go `CheckEntry` /
    /// `DownloadNew` discovery). Does not call `recordCheck`.
    func discoverNewEpisodes(pid: Int) async throws -> [Episode] {
        let episodes = try await unknownEpisodes(pid: pid)
        let fresh = try await recordEpisodes(pid: pid, episodes)
        let freshIDs = Set(fresh.map(\.identifier))
        return episodes.filter { freshIDs.contains($0.identifier) }
    }

    /// Writes episodes into the library history; returns the refs that were
    /// new (Go `recordEpisodes` / `store.SyncEpisodes`).
    @discardableResult
    func recordEpisodes(pid: Int, _ episodes: [Episode]) async throws -> [LibraryEpisodeRef] {
        let refs = episodes.map {
            LibraryEpisodeRef(identifier: $0.identifier, number: $0.number, title: $0.title, date: $0.date)
        }
        return try await services.store.syncEpisodes(pid: pid, refs)
    }

    /// Adds a format to the library (Go `Remember`).
    func remember(_ format: Format) async throws {
        try await services.store.upsertFormat(
            pid: format.pid, slug: format.slug, title: format.title, status: format.status.rawValue)
    }

    /// Deletes a downloaded file and forgets that it was loaded, so the
    /// episode is offered again (TUI `x`).
    func deleteDownload(pid: Int, identifier: String, file: URL) async throws {
        let folder = try accessDownloadFolder()
        defer { folder.access?.stop() }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            throw PersistenceError.notWritable(path: file.path, reason: error.localizedDescription)
        }
        try await services.store.clearDownloaded(pid: pid, identifier: identifier)
        episodes.clearDownloaded(identifier)
        show("Die Datei wurde gelöscht, die Folge wird wieder angeboten.")
    }
}
