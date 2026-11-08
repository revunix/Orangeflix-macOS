import Foundation
import Observation

/// Where the Browse navigation stacks can go.
enum BrowseRoute: Hashable {
    /// The episodes of `BrowseModel.currentFormat`.
    case episodes(pid: Int)
    /// The clips similar to an episode.
    case similar(Episode)
    /// The page of a guest.
    case host(Participant)
    /// The directory of guests collected from episodes seen in this session.
    case guests
    /// The page of one episode; `autoplay` starts it in the page at once.
    case episode(Episode, autoplay: Bool)
    /// The page of an episode, starting at a search result's time.
    case episodeAt(Episode, seconds: Int)
    /// The whole premium and early-access shelf of the Mediathek.
    case premium
    /// Every series with a new episode.
    case newFormats
}

/// The known and downloaded episode counts of a format (TUI `knownCounts`).
struct BrowseKnownCount: Hashable, Sendable {
    var total: Int
    var loaded: Int
}

/// A loaded clip list (Weiterschauen, Merkliste).
struct BrowseClipListState {
    var episodes: [Episode] = []
    var isLoading = false
    var error: String?
    var hasLoaded = false
}

/// Errors of the Browse feature (German, like the TUI messages).
enum BrowseError: LocalizedError {
    case noEpisode(title: String)
    case unknownLength(String)
    case noClip
    case notInLibrary
    case noDownloads
    case noPlayer

    var errorDescription: String? {
        switch self {
        case .noEpisode(let title): "\(title) hat noch keine Folge."
        case .unknownLength(let identifier): "Die Länge von \(identifier) ist unbekannt."
        case .noClip: "Keine Folge ausgewählt."
        case .notInLibrary: "Das Format ist nicht in der Bibliothek. Erst zur Bibliothek hinzufügen."
        case .noDownloads: "Die Downloads stehen nicht zur Verfügung."
        case .noPlayer: "Die Wiedergabe steht nicht zur Verfügung."
        }
    }
}

/// Formats, library, episodes, clip lists and search (port of Go
/// `internal/app` v3.go/library.go and the matching TUI state).
@MainActor @Observable final class BrowseModel {
    @ObservationIgnored let app: AppModel

    // MARK: Formats
    /// The catalog: the program's, replaced by the merged live catalog.
    private(set) var formats: [Format] = BrowseLogic.staticCatalog(opened: [])
    /// The library formats.
    private(set) var library: [LibraryFormat] = []
    /// Known/downloaded counts of the library formats.
    private(set) var knownCounts: [Int: BrowseKnownCount] = [:]
    private(set) var formatsLoading = false
    private(set) var isChecking = false
    var libraryOnly = false
    var selectedFormatPID: Int?
    var formatsPath: [BrowseRoute] = []
    var searchPath: [BrowseRoute] = []

    /// Routes opened from a detail page stay in the navigation stack it came from.
    var navigationPath: [BrowseRoute] {
        get { app.selection == .search ? searchPath : formatsPath }
        set {
            if app.selection == .search { searchPath = newValue }
            else { formatsPath = newValue }
        }
    }

    // MARK: Episodes
    private(set) var currentFormat: Format?
    /// The episodes of the current format, ascending by number.
    private(set) var episodes: [Episode] = []
    /// The library history of the current format by identifier.
    private(set) var known: [String: LibraryEpisode] = [:]
    /// The library history of every format of the library, by identifier.
    private(set) var history: [String: LibraryEpisode] = [:]
    private(set) var episodesLoading = false
    private(set) var episodesLoadingLabel = ""
    private(set) var episodesError: String?
    /// The year filter ("2025"); nil shows every year.
    var yearFilter: String?
    @ObservationIgnored private var episodesToken = 0

    // MARK: Qualities
    private(set) var qualities: [String: [ClipFile]] = [:]
    private(set) var qualityLoading: Set<String> = []
    private(set) var qualityErrors: [String: String] = [:]

    // MARK: Clip lists and search
    private(set) var recents = BrowseClipListState()
    private(set) var bookmarks = BrowseClipListState()
    /// Latest episodes the account may not be allowed to play: premium and
    /// early access. The feed hides them unless asked.
    private(set) var premiumEpisodes: [Episode] = []
    private var premiumLoadedAt: Date?
    /// The text of the search field; the search screen searches live.
    var searchText = ""
    /// The format the search is narrowed to (filtered by the server).
    var searchFormatPID: Int?
    /// The person (a guest or a host) the search is narrowed to; nil when
    /// it covers everybody.
    var searchPersonID: String?
    /// Which hits show (filtered among the loaded ones).
    var searchKind = SearchKindFilter.all
    var searchSort = SearchSort.relevance
    /// The query the hits belong to.
    private(set) var searchQuery = ""
    /// The loaded hits in the order of relevance.
    private(set) var searchHits: [SearchResult] = []
    /// Where the next page starts; nil when everything is loaded.
    private(set) var searchNextOffset: Int?
    /// The format filter the hits were loaded with.
    private(set) var searchedFormatPID: Int?
    /// The person filter the hits were loaded with.
    private(set) var searchedPersonID: String?
    private(set) var searching = false
    private(set) var searchingMore = false
    private(set) var searchError: String?
    /// The last searches the user sent or opened a hit of, newest first.
    private(set) var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: BrowseModel.recentSearchesKey) ?? []
    /// Counts the searches; an answer of an older one is dropped.
    @ObservationIgnored private var searchToken = 0
    private static let recentSearchesKey = "recentSearches"

    // MARK: Related lists
    /// The clips that belong to an episode.
    private(set) var similarEpisodes: [Episode] = []
    private(set) var similarLoading = false
    private(set) var similarError: String?
    /// The page of a guest.
    private(set) var hostPages: [String: HostPage] = [:]
    private(set) var loadingHostIDs: Set<String> = []
    private(set) var hostErrors: [String: String] = [:]
    private(set) var knownGuests: [String: Participant] = [:]
    /// The categories of the formats, as the feed has shown them: the
    /// number of the category and its name, per format. The server uses
    /// them to leave categories out of the main feed.
    private(set) var knownCategories: [Int: [Int: String]] = [:]
    private(set) var guestDirectoryLoading = false
    private(set) var guestDirectoryError: String?
    private(set) var guestDirectoryUpdatedAt: Date?
    @ObservationIgnored private var guestDirectoryLoaded = false
    private static let guestDirectoryCacheKey = "browse.guestDirectory.v1"
    private static let guestDirectoryRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    var guestDirectory: [Participant] {
        var guests = knownGuests
        let sources = episodes + recents.episodes + bookmarks.episodes + premiumEpisodes + similarEpisodes + hostEpisodes
        for episode in sources {
            for participant in episode.participants where !participant.id.isEmpty {
                if let known = guests[participant.id] {
                    guests[participant.id] = Participant(
                        id: participant.id,
                        name: participant.name.isEmpty ? known.name : participant.name,
                        description: participant.description.isEmpty ? known.description : participant.description,
                        image: participant.image.isEmpty ? known.image : participant.image)
                } else {
                    guests[participant.id] = participant
                }
            }
        }
        return guests.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    @ObservationIgnored private var loadedGeneration: Int?

    // MARK: Freshness
    /// When the catalog, the recents and the bookmarks were last loaded;
    /// nil reloads them on the next appearance.
    private(set) var catalogLoadedAt: Date?
    private(set) var recentsLoadedAt: Date?
    private(set) var bookmarksLoadedAt: Date?

    init(app: AppModel) {
        self.app = app
        if let data = UserDefaults.standard.data(forKey: Self.guestDirectoryCacheKey),
           let cache = try? JSONDecoder().decode(GuestDirectoryCache.self, from: data) {
            knownGuests = Dictionary(cache.guests.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            guestDirectoryUpdatedAt = cache.updatedAt
            guestDirectoryLoaded = Date().timeIntervalSince(cache.updatedAt) < Self.guestDirectoryRefreshInterval
        }
    }

    private struct GuestDirectoryCache: Codable {
        var updatedAt: Date
        var guests: [Participant]
    }

    private var store: LibraryStore { app.services.store }
    private var api: OrangeflixAPI { app.services.api }

    // MARK: Account

    /// Drops account data when the account changed; call from
    /// `.task(id: app.accountGeneration)` before loading.
    func prepare(for generation: Int) {
        guard loadedGeneration != generation else { return }
        if loadedGeneration != nil {
            searchToken += 1
            searching = false
            recents = BrowseClipListState()
            bookmarks = BrowseClipListState()
            resetSearch()
            searchPath = []
            searchError = nil
        }
        // A new account must not look fresh.
        catalogLoadedAt = nil
        recentsLoadedAt = nil
        bookmarksLoadedAt = nil
        premiumLoadedAt = nil
        premiumEpisodes = []
        loadedGeneration = generation
    }

    /// Whether `date` is younger than `ttl`.
    private func isFresh(_ date: Date?, _ ttl: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= ttl
    }

    // MARK: Freshness

    /// Loads what the formats list shows, but only the parts that got stale.
    /// A section switch therefore shows the loaded content at once.
    func ensureLoaded() async {
        if !isFresh(catalogLoadedAt, CacheTTL.catalog) { await reloadFormats() }
        if !isFresh(recentsLoadedAt, CacheTTL.recents) { await loadRecents() }
        if !isFresh(premiumLoadedAt, CacheTTL.recents) { await loadPremium() }
        if !isFresh(bookmarksLoadedAt, CacheTTL.bookmarks) { await loadBookmarks() }
    }

    /// Loads one clip list, but only when it got stale.
    func ensureClipList(_ kind: ClipListKind) async {
        switch kind {
        case .recents:
            if !isFresh(recentsLoadedAt, CacheTTL.recents) { await loadRecents() }
        case .bookmarks:
            if !isFresh(bookmarksLoadedAt, CacheTTL.bookmarks) { await loadBookmarks() }
        }
    }

    // MARK: Formats and library

    /// Loads the library and the catalog.
    /// - Parameter force: skips the stored answers (the toolbar's refresh).
    func reloadFormats(force: Bool = false) async {
        await loadLibrary()
        await loadFormats(force: force)
    }

    /// The catalog merged with the live catalog (Go `Formats`).
    /// - Parameter force: asks the API instead of the stored answer.
    func loadFormats(force: Bool = false) async {
        formatsLoading = true
        defer { formatsLoading = false }
        let opened = (try? await store.openedFormats()) ?? []
        do {
            let magazines = try await api.magazines(refresh: force)
            formats = BrowseLogic.mergeCatalog(magazines, opened: opened)
            catalogLoadedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            app.record("Der Live-Katalog ist nicht erreichbar (\(error.localizedDescription)), nutze den Katalog im Programm.")
            formats = BrowseLogic.staticCatalog(opened: opened)
        }
    }

    /// Reads the library and the counts of its formats.
    func loadLibrary() async {
        do {
            library = try await store.formats()
            var counts: [Int: BrowseKnownCount] = [:]
            var history: [String: LibraryEpisode] = [:]
            var pids = Set(library.map(\.pid))
            if let pid = currentFormat?.pid { pids.insert(pid) }
            for pid in pids {
                let stored = try await store.episodes(pid: pid)
                counts[pid] = BrowseKnownCount(total: stored.count, loaded: stored.filter { $0.downloadedAt != nil }.count)
                for episode in stored { history[episode.identifier] = episode }
            }
            knownCounts = counts
            self.history = history
        } catch {
            app.show(error)
        }
    }

    func libraryEntry(_ pid: Int) -> LibraryFormat? {
        library.first { $0.pid == pid }
    }

    func format(pid: Int) -> Format? {
        formats.first { $0.pid == pid }
    }

    /// The formats the catalog shows: the ones the reader did not switch off
    /// in the settings.
    var visibleFormats: [Format] {
        let hidden = Set(app.settings.hiddenMagazines)
        return hidden.isEmpty ? formats : formats.filter { !hidden.contains($0.pid) }
    }

    /// The visible groups of the list.
    var formatGroups: [BrowseFormatGroup] {
        BrowseLogic.formatGroups(visibleFormats, filter: "",
                                 libraryPIDs: libraryOnly ? Set(library.map(\.pid)) : nil)
    }

    /// Known/downloaded counts, live for the open format.
    func count(for pid: Int) -> BrowseKnownCount? {
        if pid == currentFormat?.pid, !known.isEmpty {
            let loaded = known.keys.filter { isDownloaded($0) }.count
            return BrowseKnownCount(total: known.count, loaded: loaded)
        }
        guard let count = knownCounts[pid], count.total > 0 else { return nil }
        return count
    }

    /// The FOLGEN column: known count, else the clip count, else "-".
    func episodeCountText(_ format: Format) -> String {
        if let count = count(for: format.pid) { return "\(count.total)" }
        return format.clipCount > 0 ? "\(format.clipCount)" : "-"
    }

    /// Adds a format to the library and fills its history (Go `AddFormat`).
    func addFormat(_ format: Format) async {
        do {
            try await app.remember(format)
        } catch {
            app.show(error)
            return
        }
        app.record("\(format.title) wurde der Bibliothek hinzugefügt.")
        app.show("\(format.title) wurde der Bibliothek hinzugefügt.")
        do {
            let all = try await app.allEpisodes(pid: format.pid)
            try await app.recordEpisodes(pid: format.pid, all)
        } catch is CancellationError {
        } catch {
            app.record("Die Episodenliste konnte nicht geladen werden (\(error.localizedDescription)), der Check holt sie später nach.")
        }
        await loadLibrary()
    }

    /// Removes a format from the library; its history stays (Go store).
    func removeFormat(_ format: Format) async {
        do {
            try await store.removeFormat(pid: format.pid)
            app.show("\(format.title) wurde aus der Bibliothek entfernt.")
        } catch {
            app.show(error)
        }
        await loadLibrary()
    }

    /// Checks every enabled library format (Go `CheckLibrary`).
    func checkLibrary() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        app.show("Suche nach neuen Folgen ...")
        let entries: [LibraryFormat]
        do {
            entries = try await store.formats()
        } catch {
            app.show(error)
            return
        }
        var total = 0
        for entry in entries where entry.enabled {
            if Task.isCancelled { return }
            total += await checkEntry(entry)
        }
        app.show("\(total) neue Folge(n) gefunden.")
        await loadLibrary()
    }

    /// Checks one library format and returns the count of new episodes
    /// (Go `CheckEntry`).
    func checkFormat(_ format: Format) async {
        guard let entry = libraryEntry(format.pid) else {
            app.show(BrowseError.notInLibrary)
            return
        }
        isChecking = true
        defer { isChecking = false }
        app.show("Suche nach neuen Folgen ...")
        let count = await checkEntry(entry)
        app.show("\(count) neue Folge(n) gefunden.")
        await loadLibrary()
    }

    private func checkEntry(_ entry: LibraryFormat) async -> Int {
        do {
            let fresh = try await app.discoverNewEpisodes(pid: entry.pid)
            try? await store.recordCheck(pid: entry.pid, newCount: fresh.count, lastError: "")
            return fresh.count
        } catch is CancellationError {
            return 0
        } catch {
            app.record("\(entry.title): \(error.localizedDescription)", error: true)
            try? await store.recordCheck(pid: entry.pid, newCount: 0, lastError: trimLibraryError(error))
            return 0
        }
    }

    /// Downloads the new episodes of a library format (TUI `d`).
    func downloadNew(_ format: Format) {
        guard let entry = libraryEntry(format.pid) else {
            app.show(BrowseError.notInLibrary)
            return
        }
        guard let downloads = app.downloads else {
            app.show(BrowseError.noDownloads)
            return
        }
        app.show("Lade die neuen Folgen von \(format.title) ...")
        downloads.downloadNew(of: entry)
    }

    /// The newest episode of a format from the first feed page (Go
    /// `LatestEpisode`). When the first page is empty, the whole list is
    /// read and the newest episode is picked (TUI `latestOfCurrentFormat`).
    func latestEpisode(of format: Format) async throws -> Episode {
        let fallbackTitle = FormatCatalog.format(pid: format.pid)?.title ?? (format.title.isEmpty ? "Format \(format.pid)" : format.title)
        var episodes = try await app.episodesPage(pid: format.pid, page: 1)
        if episodes.isEmpty {
            episodes = try await app.allEpisodes(pid: format.pid)
        }
        guard var newest = BrowseLogic.newestEpisode(episodes) else {
            throw BrowseError.noEpisode(title: format.title.isEmpty ? fallbackTitle : format.title)
        }
        if newest.pid == 0 { newest.pid = format.pid }
        if newest.formatName.isEmpty { newest.formatName = fallbackTitle }
        return newest
    }

    /// Plays or downloads the newest episode of a format (TUI `w` / `D`).
    func latest(of format: Format, watch: Bool) async {
        app.show("Suche die neueste Folge von \(format.title) …")
        do {
            let episode = try await latestEpisode(of: format)
            if watch {
                app.show("Starte \(BrowseLogic.title(of: episode)) …")
                play([episode])
            } else {
                download([episode], format: nil)
            }
        } catch is CancellationError {
        } catch {
            app.show(error)
        }
    }

    // MARK: Episodes of a format

    /// Opens a format: remembers the visit, loads the history and all
    /// episodes (TUI `openFormat`, Go `Episodes`).
    /// - Parameter force: skips the stored episode list (the toolbar's
    ///   refresh).
    func openFormat(_ format: Format, force: Bool = false) async {
        episodesToken += 1
        let token = episodesToken
        currentFormat = format
        episodes = []
        known = [:]
        yearFilter = nil
        episodesError = nil
        episodesLoading = true
        episodesLoadingLabel = "Lade \(format.title) ..."
        defer { if token == episodesToken { episodesLoading = false } }

        do {
            try await store.markOpened(pid: format.pid)
        } catch {
            app.record("Der Besuch konnte nicht gemerkt werden: \(error.localizedDescription)", error: true)
        }
        await loadKnown(pid: format.pid, token: token)
        do {
            let loaded = try await app.allEpisodes(pid: format.pid, force: force)
            guard token == episodesToken else { return }
            var seen = Set<String>()
            episodes = loaded.filter { seen.insert($0.identifier).inserted }
        } catch is CancellationError {
            return
        } catch {
            guard token == episodesToken else { return }
            episodesError = error.localizedDescription
            app.show(error)
            return
        }
        // The catalog can mark the format as opened; a fresh one needs no
        // second request.
        if !isFresh(catalogLoadedAt, CacheTTL.catalog) { await loadFormats() }
    }

    private func loadKnown(pid: Int, token: Int) async {
        do {
            let stored = try await store.episodes(pid: pid)
            guard token == episodesToken else { return }
            known = Dictionary(stored.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            app.record("Die Bibliothek konnte nicht gelesen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// The filtered episodes in list order (date descending).
    var visibleEpisodes: [Episode] {
        BrowseLogic.filteredEpisodes(episodes, year: yearFilter)
    }

    /// The year groups of the visible episodes.
    var yearGroups: [BrowseYearGroup] {
        BrowseLogic.yearGroups(visibleEpisodes) { self.isDownloaded($0.identifier) }
    }

    var availableYears: [String] { BrowseLogic.years(episodes) }

    // MARK: Episode state

    /// The episode with the session's progress and bookmark.
    func current(_ episode: Episode) -> Episode {
        app.episodes.apply(episode)
    }

    /// Whether the episode was downloaded (session state, else the library).
    func isDownloaded(_ identifier: String) -> Bool {
        if let changed = app.episodes.files[identifier] { return changed != nil }
        return libraryEpisode(identifier)?.downloadedAt != nil
    }

    /// The library entry of an episode: the open format first, then the
    /// history of the library.
    func libraryEpisode(_ identifier: String) -> LibraryEpisode? {
        known[identifier] ?? history[identifier]
    }

    /// The downloaded file, if any.
    func downloadedFile(_ identifier: String) -> URL? {
        guard isDownloaded(identifier) else { return nil }
        return app.episodes.file(for: identifier, stored: libraryEpisode(identifier)?.path)
    }

    func badge(_ episode: Episode) -> BrowseEpisodeBadge {
        BrowseLogic.badge(
            downloaded: isDownloaded(episode.identifier),
            progress: current(episode).progressPercent,
            firstSeen: libraryEpisode(episode.identifier)?.firstSeen)
    }

    func isWatched(_ episode: Episode) -> Bool {
        current(episode).progressPercent >= BrowseLogic.watchedPercent
    }

    /// Removes a clip from Weiterschauen. The API keeps it in its history
    /// (there is no delete), so the app remembers the removal and hides the
    /// clip on every later load until it is watched again.
    func removeFromRecents(_ identifier: String) {
        recents.episodes.removeAll { $0.identifier == identifier }
        let now = Date().timeIntervalSince1970
        try? app.updateSettings { $0.dismissedRecents[identifier] = now }
    }

    /// "Ansehen" or "Weiterschauen" (progress 1–89 %).
    func watchLabel(_ episode: Episode) -> String {
        let percent = current(episode).progressPercent
        return percent > 0 && percent < BrowseLogic.watchedPercent ? "Weiterschauen" : "Ansehen"
    }

    // MARK: Clip lists

    /// The state of one of the clip lists.
    func clipList(_ kind: ClipListKind) -> BrowseClipListState {
        switch kind {
        case .recents: recents
        case .bookmarks: bookmarks
        }
    }

    /// Loads the clips the account watched most recently (Go `app.Recents`).
    /// - Parameter force: asks the API instead of the stored answer.
    func loadRecents(force: Bool = false) async {
        recents.isLoading = true
        defer { recents.isLoading = false }
        do {
            let clips = try await api.recents(limit: 50, refresh: force)
            // Removed clips stay hidden until they are watched again.
            let dismissed = app.settings.dismissedRecents
            let shown = clips.filter {
                !RecentsDismissal.isHidden(lastAccessed: $0.progress.lastAccessed, dismissedAt: dismissed[$0.id])
            }
            let kept = RecentsDismissal.pruned(dismissed, visibleIn: clips.map { ($0.id, $0.progress.lastAccessed) })
            if kept != dismissed { try? app.updateSettings { $0.dismissedRecents = kept } }
            // Premium and early-access episodes stay out of Weiterschauen
            // when this account cannot watch them. They remain on the Premium shelf.
            recents.episodes = shown.map(\.episode).filter { episode in
                if episode.isPremium || episode.isEarlyAccess { return episode.canAccess }
                return true
            }
            recents.hasLoaded = true
            recents.error = nil
            recentsLoadedAt = Date()
        } catch is CancellationError {
        } catch {
            recents.error = error.localizedDescription
            app.show(error)
        }
    }

    /// Loads the newest premium and early-access episodes. A non-premium
    /// account still sees them; playback stays locked by the API.
    /// - Parameter force: asks the API instead of the stored answer.
    func loadPremium(force: Bool = false) async {
        do {
            let clips = try await api.feed(
                FeedQuery(count: 50, includePremium: true, includeEarlyAccess: true), refresh: force)
            premiumEpisodes = clips.map(\.episode).filter { $0.isPremium || $0.isEarlyAccess }
            premiumLoadedAt = Date()
        } catch is CancellationError {
        } catch {
            app.show(error)
        }
    }

    /// Loads the bookmarked clips of the account (Go `app.Bookmarks`).
    /// - Parameter force: asks the API instead of the stored answer.
    func loadBookmarks(force: Bool = false) async {
        bookmarks.isLoading = true
        defer { bookmarks.isLoading = false }
        do {
            let clips = try await api.bookmarks(limit: 50, offset: 0, refresh: force)
            bookmarks.episodes = clips.map(\.episode)
            bookmarks.hasLoaded = true
            bookmarks.error = nil
            bookmarksLoadedAt = Date()
        } catch is CancellationError {
        } catch {
            bookmarks.error = error.localizedDescription
            app.show(error)
        }
    }

    // MARK: Search

    /// The hits that show: the loaded ones with the kind and order chosen.
    var visibleSearchHits: [SearchResult] {
        SearchLogic.visible(searchHits, kind: searchKind, sort: searchSort)
    }

    /// Runs the full-text search over titles, descriptions, chapters and
    /// transcripts (Go `app.Search`) and loads its first page. A newer
    /// search overtakes an older one; a query shorter than two letters
    /// clears the hits.
    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let format = searchFormatPID
        let person = searchPersonID
        searchToken += 1
        let token = searchToken
        guard query.count >= SearchLogic.minimumQueryLength else {
            resetSearch()
            searching = false
            searchError = nil
            return
        }
        searching = true
        defer { if token == searchToken { searching = false } }
        do {
            try await app.ensureSession()
            try Task.checkCancellation()
            guard token == searchToken else { return }
            let page = try await api.search(query, limit: SearchLogic.pageSize, offset: 0,
                                            magazineId: format, personId: person)
            guard token == searchToken, !Task.isCancelled,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  format == searchFormatPID, person == searchPersonID else { return }
            searchHits = Self.unique(page.hits, after: [])
            searchNextOffset = page.nextOffset
            searchQuery = query
            searchedFormatPID = format
            searchedPersonID = person
            searchError = nil
        } catch {
            guard token == searchToken, !Task.isCancelled, !(error is CancellationError) else { return }
            searchError = error.localizedDescription
        }
    }

    /// Loads the next page of the current search.
    func searchMore() async {
        guard !searching, !searchingMore, let offset = searchNextOffset, !searchQuery.isEmpty else { return }
        let token = searchToken
        let query = searchQuery
        let format = searchedFormatPID
        let person = searchedPersonID
        guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
              format == searchFormatPID, person == searchPersonID else { return }
        searchingMore = true
        defer { searchingMore = false }
        do {
            try await app.ensureSession()
            try Task.checkCancellation()
            guard token == searchToken else { return }
            let page = try await api.search(query, limit: SearchLogic.pageSize, offset: offset,
                                            magazineId: format, personId: person)
            guard token == searchToken, !Task.isCancelled,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  format == searchFormatPID, person == searchPersonID else { return }
            searchHits = Self.unique(page.hits, after: searchHits)
            searchNextOffset = page.nextOffset
        } catch {
            guard token == searchToken, !Task.isCancelled, !(error is CancellationError) else { return }
            app.show(error)
        }
    }

    /// Puts the current query at the top of the history.
    func rememberSearch() {
        let next = SearchLogic.remembering(searchText, in: recentSearches)
        guard next != recentSearches else { return }
        recentSearches = next
        UserDefaults.standard.set(next, forKey: Self.recentSearchesKey)
    }

    func forgetSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        UserDefaults.standard.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    func clearSearchHistory() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    private func resetSearch() {
        searchHits = []
        searchQuery = ""
        searchNextOffset = nil
    }

    /// `hits` without the ones `existing` already has, appended to it.
    private static func unique(_ hits: [SearchResult], after existing: [SearchResult]) -> [SearchResult] {
        var seen = Set(existing.map(\.id))
        return existing + hits.filter { seen.insert($0.id).inserted }
    }

    // MARK: Merkliste and progress

    /// Whether the episode is on the Merkliste.
    func isBookmarked(_ episode: Episode) -> Bool {
        current(episode).bookmarked
    }

    /// Puts the episode on the Merkliste or takes it off.
    func toggleBookmark(_ episode: Episode) async {
        await setBookmark(episode, on: !isBookmarked(episode))
    }

    /// Puts the episode on the Merkliste or takes it off. The state changes
    /// at once and is reverted when the account refuses it (Go `app.SetBookmark`).
    func setBookmark(_ episode: Episode, on: Bool) async {
        let identifier = episode.identifier
        guard !identifier.isEmpty else { return }
        let previous = isBookmarked(episode)
        app.episodes.setBookmarked(identifier, on)
        do {
            if on {
                try await api.addBookmark(identifier)
                app.show("Gemerkt.")
            } else {
                try await api.removeBookmark(identifier)
                app.show("Aus der Merkliste entfernt.")
                bookmarks.episodes.removeAll { $0.identifier == identifier }
            }
            // The stored and the loaded list are one entry off now.
            bookmarksLoadedAt = nil
        } catch is CancellationError {
            app.episodes.setBookmarked(identifier, previous)
        } catch {
            app.episodes.setBookmarked(identifier, previous)
            app.show("Der Stand konnte nicht gespeichert werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Marks the episode as watched or as not watched (Go `app.SetWatched`).
    func setWatched(_ episode: Episode, watched: Bool) async {
        do {
            guard try await storeWatched(episode, watched: watched) else { return }
            app.show(watched ? "Als gesehen markiert." : "Als ungesehen markiert.")
        } catch is CancellationError {
        } catch {
            app.show("Der Stand konnte nicht gespeichert werden: \(error.localizedDescription)", error: true)
        }
    }

    /// A running "mark many episodes" job; the window shows it as a popup
    /// and holds the app until it is done.
    struct WatchedBatch: Equatable {
        let watched: Bool
        let total: Int
        var done = 0
        var failed = 0
        /// The title of the episode being saved now.
        var current = ""
        var finished = false
        var cancelled = false
        var lastError: String?

        var handled: Int { done + failed }
    }

    private(set) var watchedBatch: WatchedBatch?
    @ObservationIgnored private var batchCancelRequested = false

    /// The pause between two saves, so the server can process each one.
    private static let batchPace: Duration = .milliseconds(900)
    /// The longer pause before a failed save is tried once more.
    private static let batchRetryPause: Duration = .seconds(3)

    /// Stops a running batch after the episode being saved now.
    func cancelWatchedBatch() {
        guard watchedBatch?.finished == false else { return }
        batchCancelRequested = true
    }

    /// Closes the popup of a finished batch.
    func dismissWatchedBatch() {
        guard watchedBatch?.finished == true else { return }
        watchedBatch = nil
    }

    /// Marks many episodes slowly, one after another with a pause, and
    /// retries a failed one once after a longer pause. A popup shows the
    /// progress until every episode is handled. Episodes already in that
    /// state are skipped.
    func setWatched(_ episodes: [Episode], watched: Bool) async {
        guard watchedBatch == nil || watchedBatch?.finished == true else { return }
        let pending = episodes.filter { watched ? !isWatched($0) : current($0).progressPercent > 0 }
        guard !pending.isEmpty else {
            app.show(watched ? "Alle Folgen sind schon gesehen." : "Alle Folgen sind schon ungesehen.")
            return
        }
        batchCancelRequested = false
        watchedBatch = WatchedBatch(watched: watched, total: pending.count)
        for (index, episode) in pending.enumerated() {
            if batchCancelRequested || Task.isCancelled {
                watchedBatch?.cancelled = true
                break
            }
            watchedBatch?.current = BrowseLogic.title(of: episode)
            if index > 0 { try? await Task.sleep(for: Self.batchPace) }
            do {
                _ = try await storeWatched(episode, watched: watched)
                watchedBatch?.done += 1
            } catch {
                // The server may just be busy: wait longer and try once more.
                try? await Task.sleep(for: Self.batchRetryPause)
                do {
                    _ = try await storeWatched(episode, watched: watched)
                    watchedBatch?.done += 1
                } catch {
                    watchedBatch?.failed += 1
                    watchedBatch?.lastError = error.localizedDescription
                }
            }
        }
        watchedBatch?.current = ""
        watchedBatch?.finished = true
        // A clean run closes by itself after a moment; problems stay until
        // the user has read them.
        if let batch = watchedBatch, batch.failed == 0, !batch.cancelled {
            try? await Task.sleep(for: .seconds(1.4))
            if watchedBatch == batch { watchedBatch = nil }
        }
    }

    /// Saves the state of one episode; the shown progress changes at once
    /// and returns to the old value when the account refuses it.
    private func storeWatched(_ episode: Episode, watched: Bool) async throws -> Bool {
        let identifier = episode.identifier
        guard !identifier.isEmpty else { return false }
        let previous = current(episode).progressPercent
        app.episodes.setProgress(identifier, percent: watched ? 100 : 0)
        do {
            try await api.updateProgress(identifier, percentage: watched ? 100 : 0)
            removeFromRecents(identifier)
            return true
        } catch {
            app.episodes.setProgress(identifier, percent: previous)
            throw error
        }
    }

    /// Marks a list of episodes; they count as watched when one of them is
    /// not watched yet (TUI `toggleWatched`).
    func toggleWatched(_ episodes: [Episode]) async {
        guard !episodes.isEmpty else { return }
        let watched = episodes.contains { !isWatched($0) }
        if episodes.count == 1 {
            await setWatched(episodes[0], watched: watched)
        } else {
            await setWatched(episodes, watched: watched)
        }
    }

    // MARK: Related lists

    /// The clips that belong to an episode (Go `app.Similar`, 10 hits).
    func loadSimilar(for episode: Episode) async {
        similarLoading = true
        defer { similarLoading = false }
        do {
            let clips = try await api.similarClips(episode.identifier, limit: 10)
            similarEpisodes = clips.map(\.episode)
            similarError = nil
        } catch is CancellationError {
        } catch {
            similarError = error.localizedDescription
            app.show(error)
        }
    }

    /// The page of a guest (Go `app.Host`, offset 0 and 50 clips).
    func loadHost(_ participant: Participant) async {
        if !participant.id.isEmpty { knownGuests[participant.id] = participant }
        let id = participant.id
        loadingHostIDs.insert(id)
        hostErrors[id] = nil
        defer { loadingHostIDs.remove(id) }
        do {
            let page = try await api.host(id, offset: 0, limit: 50)
            hostPages[id] = page
            hostErrors[id] = nil
            let full = Participant(id: page.host.id.isEmpty ? id : page.host.id,
                                   name: page.host.name.isEmpty ? participant.name : page.host.name,
                                   description: page.host.description.isEmpty ? participant.description : page.host.description,
                                   image: page.host.image.isEmpty ? participant.image : page.host.image)
            knownGuests[full.id] = full
            persistGuestDirectory()
        } catch is CancellationError {
        } catch {
            hostErrors[id] = error.localizedDescription
            app.show(error)
        }
    }

    func hostPage(for id: String) -> HostPage? { hostPages[id] }
    func isLoadingHost(_ id: String) -> Bool { loadingHostIDs.contains(id) }
    func hostError(for id: String) -> String? { hostErrors[id] }

    /// Reads the public feed page by page so the directory covers the archive,
    /// not only episodes already visited in the UI.
    func loadGuestDirectory(force: Bool = false) async {
        guard !guestDirectoryLoading, force || !guestDirectoryLoaded else { return }
        guestDirectoryLoading = true
        guestDirectoryError = nil
        defer { guestDirectoryLoading = false }

        var offset = 0
        var seenEpisodes = Set<String>()
        var guests: [String: Participant] = [:]
        do {
            while true {
                let clips = try await api.feed(
                    FeedQuery(offset: offset, count: 100, includePremium: true, includeEarlyAccess: true),
                    cacheMaxAge: force ? 0 : Self.guestDirectoryRefreshInterval)
                var added = 0
                for clip in clips {
                    if !clip.id.isEmpty, seenEpisodes.insert(clip.id).inserted { added += 1 }
                    for participant in clip.participants where !participant.id.isEmpty {
                        guests[participant.id] = participant
                    }
                    if clip.categoryId > 0 {
                        var categories = knownCategories[clip.magazineId] ?? [:]
                        if categories[clip.categoryId] == nil, !clip.categoryTitle.isEmpty {
                            categories[clip.categoryId] = clip.categoryTitle
                        }
                        knownCategories[clip.magazineId] = categories
                    }
                }
                knownGuests.merge(guests) { old, latest in
                    Participant(id: latest.id, name: latest.name.isEmpty ? old.name : latest.name,
                                description: latest.description.isEmpty ? old.description : latest.description,
                                image: latest.image.isEmpty ? old.image : latest.image)
                }
                persistGuestDirectory()
                guard clips.count == 100, added > 0 else { break }
                offset += clips.count
            }
            guestDirectoryLoaded = true
            guestDirectoryUpdatedAt = Date()
            persistGuestDirectory(updatedAt: guestDirectoryUpdatedAt)
        } catch is CancellationError {
        } catch {
            guestDirectoryError = error.localizedDescription
            app.show(error)
        }
    }

    /// The clips of the guest that were loaded.
    var hostEpisodes: [Episode] {
        hostPages.values.flatMap { $0.recents.map(\.episode) }
    }

    func hostEpisodes(for id: String) -> [Episode] { hostPages[id]?.recents.map(\.episode) ?? [] }

    private func persistGuestDirectory(updatedAt: Date? = nil) {
        let cache = GuestDirectoryCache(
            updatedAt: updatedAt ?? guestDirectoryUpdatedAt ?? .distantPast,
            guests: guestDirectory.sorted { $0.id < $1.id })
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: Self.guestDirectoryCacheKey)
    }

    // MARK: Qualities

    /// Loads the files of an episode for the quality window (Go
    /// `app.ClipInfo`, the legacy API).
    func loadQualities(for episode: Episode) async {
        let identifier = episode.identifier
        guard qualityLoading.insert(identifier).inserted else { return }
        defer { qualityLoading.remove(identifier) }
        do {
            let clip = try await app.legacy.clip(identifier)
            qualities[identifier] = clip.files
            qualityErrors[identifier] = nil
        } catch is CancellationError {
        } catch {
            qualityErrors[identifier] = error.localizedDescription
        }
    }

    /// The files of the episode, when they were loaded.
    func qualityFiles(_ episode: Episode) -> [ClipFile] {
        qualities[episode.identifier] ?? []
    }

    /// Stores the chosen quality (TUI `handleQualityKey`).
    func selectQuality(_ file: ClipFile) {
        let name = BrowseLogic.qualityName(file.desc)
        guard let quality = AppSettings.Quality(rawValue: name) else {
            app.show("Die Qualität \(file.desc) kann nicht eingestellt werden.", error: true)
            return
        }
        do {
            try app.updateSettings { $0.quality = quality }
            app.show("Qualität: \(file.desc)")
        } catch {
            app.show(error)
        }
    }

    // MARK: Downloads and playback

    /// Downloads the episodes (Go `app.DownloadEpisode`).
    func download(_ episodes: [Episode], format: Format?) {
        guard !episodes.isEmpty else {
            app.show(BrowseError.noClip)
            return
        }
        guard let downloads = app.downloads else {
            app.show(BrowseError.noDownloads)
            return
        }
        downloads.download(episodes, format: format)
    }

    /// Downloads the episodes of a format: the format joins the library and
    /// its history is written, like Go `runFormat`.
    func downloadEpisodes(_ episodes: [Episode], of format: Format?) async {
        guard !episodes.isEmpty else {
            app.show(BrowseError.noClip)
            return
        }
        if let format {
            do {
                try await app.remember(format)
            } catch {
                app.record("Das Format konnte nicht gemerkt werden: \(error.localizedDescription)", error: true)
            }
            let all = (try? await app.allEpisodes(pid: format.pid)) ?? episodes
            do {
                try await app.recordEpisodes(pid: format.pid, all)
            } catch {
                app.record("Die Episodenliste konnte nicht gespeichert werden: \(error.localizedDescription)", error: true)
            }
        }
        download(episodes, format: format)
    }

    /// Plays the episodes one after another (Go `app.Play`).
    func play(_ episodes: [Episode]) {
        guard !episodes.isEmpty else {
            app.show(BrowseError.noClip)
            return
        }
        guard let playback = app.playback else {
            app.show(BrowseError.noPlayer)
            return
        }
        playback.play(episodes)
    }

    /// Plays one episode from `seconds` on: the chapter or the passage the
    /// search found.
    func play(_ episode: Episode, from seconds: Int) {
        guard let playback = app.playback else {
            app.show(BrowseError.noPlayer)
            return
        }
        playback.play(episode, from: seconds)
    }

    /// Deletes the downloaded file of an episode (TUI `x`).
    func deleteDownload(_ episode: Episode) async {
        guard let file = downloadedFile(episode.identifier) else {
            app.show("Die Folge wurde noch nicht geladen.", error: true)
            return
        }
        do {
            try await app.deleteDownload(pid: episode.pid, identifier: episode.identifier, file: file)
            app.show("Die Datei wurde gelöscht, die Folge wird wieder angeboten.")
        } catch {
            app.show(error)
        }
    }

    /// Shows the downloaded file in the Finder.
    func reveal(_ episode: Episode) {
        guard let file = downloadedFile(episode.identifier) else {
            app.show("Die Folge wurde noch nicht geladen.", error: true)
            return
        }
        AppFormat.reveal(file)
    }

    /// Copies the title of the episode to the clipboard.
    func copyTitle(_ episode: Episode) {
        AppFormat.copy(BrowseLogic.title(of: episode))
        app.show("Der Titel wurde kopiert.")
    }
}
