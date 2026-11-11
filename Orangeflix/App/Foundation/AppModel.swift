import Foundation
import Observation
import os

/// One line of the Protokoll.
struct LogLine: Identifiable, Hashable, Sendable {
    let id: Int
    let time: Date
    let text: String
    let isError: Bool
}

/// A short message shown at the top of the active window (the TUI's status
/// line).
struct Banner: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// The login failures the interface handles specially (Go `ErrTotpRequired`,
/// `ErrTotpRejected`).
enum AuthError: LocalizedError, Equatable {
    case missingCredentials
    case totpRequired
    case totpRejected
    /// The account has too many open sessions; one has to be ended before the
    /// login works.
    case sessionLimit

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "E-Mail und Passwort werden gebraucht."
        case .totpRequired: "Das Konto verlangt einen 2FA-Code. Bitte den aktuellen Code eintragen."
        case .totpRejected: "Der 2FA-Code wurde nicht angenommen. Bitte den aktuellen Code eintragen."
        case .sessionLimit: "Das Konto hat zu viele offene Sitzungen. Bitte eine Sitzung beenden."
        }
    }
}

/// Starts downloads; implemented by the Downloads feature.
@MainActor protocol DownloadStarting: AnyObject {
    /// Downloads the episodes. `format` is nil when the episodes come from a
    /// mixed list (search, Merkliste, …); the format is then derived from
    /// `Episode.pid` / `formatName` as Go `DownloadEpisode` does.
    func download(_ episodes: [Episode], format: Format?)
    /// Discovers and downloads the new episodes of a library format (Go
    /// `DownloadNew`).
    func downloadNew(of format: LibraryFormat)
}

/// Starts the playback of episodes; implemented by the Playback feature.
@MainActor protocol PlaybackStarting: AnyObject {
    /// Plays the episodes one after another, resuming each at the stored
    /// position (Go `App.Play`).
    func play(_ episodes: [Episode])
    /// Plays one episode from `seconds` on, ignoring the stored position.
    func play(_ episode: Episode, from seconds: Int)
    /// Ends the running playback.
    func stop()
}

/// The sections of the main window (the TUI's tabs).
enum SidebarItem: String, Hashable, CaseIterable, Identifiable, Sendable {
    case formats, recents, bookmarks, calendar, live, downloads, announcements, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formats: "Formate"
        case .recents: "Weiterschauen"
        case .bookmarks: "Merkliste"
        case .calendar: "Kalender"
        case .live: "Live"
        case .downloads: "Downloads"
        case .announcements: "Ankündigungen"
        case .search: "Suche"
        }
    }
}

/// The state every feature shares: services, settings, credentials and the
/// session, the Protokoll, the status banner, the download folder and the
/// per-episode overrides.
@MainActor @Observable final class AppModel {
    @ObservationIgnored let services: AppServices
    @ObservationIgnored private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "app")

    /// The section shown in the main window.
    var selection: SidebarItem = .formats

    /// The persisted GUI settings. Change them with `updateSettings`.
    private(set) var settings: AppSettings
    /// The login name (e-mail).
    private(set) var username = ""
    /// Whether the login screen can be skipped: a stored token, or a stored
    /// user with password (Go `credentials`).
    private(set) var hasCredentials = false
    /// True until `start()` has read the stored credentials.
    private(set) var isStarting = true
    /// The one run of `start()`; the window and the background both wait for it.
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// Opens the main window when none is open (set by the window itself).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    /// The short-lived credential that may list and end the sessions of the
    /// account. The server hands it out when it refuses a login because the
    /// account has too many sessions; it is nil otherwise.
    private(set) var sessionRecovery: SessionRecovery?
    /// Increases whenever the account changes; features reload their data.
    private(set) var accountGeneration = 0
    /// The legacy client (basic auth); rebuilt when the credentials change.
    @ObservationIgnored private(set) var legacy = LegacyAPIClient()

    /// The status message of the moment; `show` sets it and it hides itself.
    private(set) var banner: Banner?
    /// Hides the status message when its time is over.
    @ObservationIgnored private var bannerTimer: Task<Void, Never>?
    /// How long a message stays; an error stays longer, it wants to be read.
    private static let messageLifetime = Duration.seconds(4)
    private static let errorLifetime = Duration.seconds(8)
    /// The Protokoll, newest last, capped at 500 lines.
    private(set) var log: [LogLine] = []
    @ObservationIgnored private var nextLogID = 0

    /// The folder the downloads go to: the bookmarked folder or
    /// ~/Downloads/Orangeflix.
    private(set) var downloadFolder: URL

    /// Progress, bookmark and download state that changed in this session.
    let episodes = EpisodeStates()

    /// Feature entry points, wired by the app at launch.
    @ObservationIgnored weak var downloads: (any DownloadStarting)?
    @ObservationIgnored weak var playback: (any PlaybackStarting)?

    @ObservationIgnored private var password = ""
    @ObservationIgnored private var pendingTotp = ""
    @ObservationIgnored private var authTask: Task<Void, any Error>?
    @ObservationIgnored private var sessionSaver: Task<Void, Never>?

    /// The prefix of this account's stored API answers.
    var cacheScope: String { ResponseCache.scope(username) }

    init(services: AppServices) {
        self.services = services
        let stored = services.settingsStore.load()
        ThemeRuntime.shared.apply(stored)
        self.settings = stored
        self.downloadFolder = FolderBookmarkStore.defaultFolder()
    }

    // MARK: Launch and login

    /// Reads the stored credentials and session and hands them to the
    /// clients (Go `resolveCredentials` + `loadSession`). Call once at launch.
    /// Reads the stored login once; later calls wait for that first run.
    func start() async {
        if let startTask { return await startTask.value }
        let task = Task { await performStart() }
        startTask = task
        await task.value
    }

    private func performStart() async {
        AppIconController.shared.apply(style: settings.appIcon, theme: settings.theme)
        startSessionSaver()
        let stored = await services.credentials.load()
        // An older build kept the login in the SQLite settings; keep it usable.
        let fallbackUser = (try? await services.store.setting(LibrarySettingKey.username)) ?? ""
        let user = stored.email.isEmpty ? fallbackUser : stored.email
        let storedPassword = stored.password

        username = user
        password = storedPassword
        await services.api.setCredentials(email: user, password: storedPassword)
        await services.api.setCacheScope(cacheScope)
        legacy = LegacyAPIClient(username: user, password: storedPassword)
        if stored.hasSession {
            await services.api.adopt(AuthSession(accessToken: stored.accessToken,
                                                 refreshToken: stored.refreshToken,
                                                 expiresAt: stored.expiry))
        }
        hasCredentials = stored.hasSession || (stored.hasLogin && !user.isEmpty)
        refreshDownloadFolder()
        isStarting = false
        logger.notice("Start: Benutzer=\(user, privacy: .public) Passwort=\(storedPassword.isEmpty ? "nein" : "ja", privacy: .public) Sitzung=\(stored.hasSession ? "ja" : "nein", privacy: .public)")
    }

    /// Stores new credentials and logs in (Go `SetCredentials` + keychain
    /// write + `SetTotp` + `EnsureV3`). A different account drops the old
    /// session. Throws `AuthError` for the 2FA cases.
    func signIn(email: String, password newPassword: String, totp: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !newPassword.isEmpty else { throw AuthError.missingCredentials }

        try await services.credentials.setLogin(email: email, password: newPassword)
        try await services.credentials.clearSession()
        try await services.store.setSetting(LibrarySettingKey.username, email)
        await services.api.setCredentials(email: email, password: newPassword)
        await services.api.setToken(AuthSession(accessToken: "", refreshToken: "", expiresAt: nil))
        legacy = LegacyAPIClient(username: email, password: newPassword)
        username = email
        password = newPassword
        // A different account must not read the answers of the old one.
        await services.api.setCacheScope(cacheScope)
        await services.cache.removeAll()
        pendingTotp = totp.trimmingCharacters(in: .whitespacesAndNewlines)

        try await ensureSession()
        // Store the fresh session immediately: the stream save runs a moment
        // later and would be lost if the app quits right after the login.
        let fresh = await services.api.session()
        try? await services.credentials.storeSession(
            accessToken: fresh.accessToken,
            refreshToken: fresh.refreshToken,
            expiry: fresh.expiresAt)
        hasCredentials = true
        accountGeneration += 1
        sessionRecovery = nil
    }

    /// Ends the session at the server and forgets the login, the tokens and
    /// the stored answers of the account. The call to the server is best
    /// effort: a Mac without network still signs out locally.
    func signOut() async {
        playback?.stop()
        // Without the password a rejected token cannot start a new login.
        await services.api.setCredentials(email: "", password: "")
        do {
            try await services.api.logout()
        } catch {
            record("Die Abmeldung beim Server ist fehlgeschlagen: \(error.localizedDescription)", error: true)
        }
        await services.api.setToken(AuthSession(accessToken: "", refreshToken: "", expiresAt: nil))
        await services.credentials.clear()
        try? await services.store.setSetting(LibrarySettingKey.username, "")
        await services.cache.removeAll()
        username = ""
        password = ""
        pendingTotp = ""
        legacy = LegacyAPIClient()
        await services.api.setCacheScope(cacheScope)
        hasCredentials = false
        accountGeneration += 1
        sessionRecovery = nil
        record("Abgemeldet.")
    }

    /// Makes sure a usable access token exists (Go `EnsureV3`): keeps a valid
    /// token, refreshes, or logs in; finishes a 2FA login with the code given
    /// to `signIn`. Concurrent callers are serialized like Go's `V3.mu`.
    func ensureSession() async throws {
        while let running = authTask {
            _ = try? await running.value
            if authTask == running { authTask = nil }
        }
        let task = Task { try await self.performEnsureSession() }
        authTask = task
        defer { if authTask == task { authTask = nil } }
        try await task.value
    }

    private func performEnsureSession() async throws {
        // Without credentials the API can only answer with an error; the
        // login screen asks for them instead (Go `EnsureV3` is only called
        // with credentials). A stored session is enough on its own: it can
        // be used and refreshed without the password.
        let session = await services.api.session()
        let hasSession = !session.accessToken.isEmpty || !session.refreshToken.isEmpty
        guard hasSession || (!username.isEmpty && !password.isEmpty) else {
            throw AuthError.missingCredentials
        }
        do {
            try await services.api.ensureToken()
        } catch APIError.totpRequired(let token) {
            let code = pendingTotp
            pendingTotp = ""
            guard !code.isEmpty else { throw AuthError.totpRequired }
            do {
                try await services.api.completeTotpLogin(totpToken: token, code: code)
                record("Anmeldung mit dem zweiten Faktor abgeschlossen.")
            } catch {
                record("Die Anmeldung mit dem zweiten Faktor ist fehlgeschlagen: \(error.localizedDescription)", error: true)
                throw AuthError.totpRejected
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let APIError.sessionLimitReached(recovery) {
            // The account has too many sessions. The server hands out a
            // short-lived credential that may list and end them.
            sessionRecovery = recovery
            record("Das Konto hat zu viele offene Sitzungen.", error: true)
            throw AuthError.sessionLimit
        } catch {
            record("Der Token konnte nicht geholt werden: \(error.localizedDescription)", error: true)
            throw error
        }
    }

    /// Basic-auth credentials of the legacy API (download fallback, quality
    /// window).
    var legacyCredentials: (username: String, password: String) {
        (username, password)
    }

    /// Persists every new session the API obtains (login, refresh, 401
    /// recovery) — the Go `saveSession`, for every renewal.
    private func startSessionSaver() {
        guard sessionSaver == nil else { return }
        let api = services.api
        let credentials = services.credentials
        let logger = logger
        sessionSaver = Task.detached {
            for await session in api.sessionUpdates {
                do {
                    try await credentials.storeSession(
                        accessToken: session.accessToken,
                        refreshToken: session.refreshToken,
                        expiry: session.expiresAt)
                } catch {
                    logger.error("Sitzung nicht gespeichert: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: Settings

    /// Validates and stores changed settings.
    func updateSettings(_ change: (inout AppSettings) -> Void) throws {
        let previous = settings
        var next = settings
        change(&next)
        try services.settingsStore.save(next)
        ThemeRuntime.shared.apply(next)
        settings = next
        if next.appIcon != previous.appIcon || next.theme != previous.theme {
            AppIconController.shared.apply(style: next.appIcon, theme: next.theme)
        }
    }

    // MARK: Download folder

    /// Re-reads the bookmarked folder for display.
    func refreshDownloadFolder() {
        if let access = try? services.folders.access() {
            downloadFolder = access.url
            access.stop()
        } else {
            downloadFolder = FolderBookmarkStore.defaultFolder()
        }
    }

    /// Uses `url` (picked in an open panel) as the download folder (Go
    /// `applyPath`): checks that it is writable, then stores the bookmark.
    func chooseDownloadFolder(_ url: URL) throws {
        try FolderBookmarkStore.ensureWritable(url)
        try services.folders.save(url)
        downloadFolder = url
        show("Speicherort: \(AppFormat.displayPath(url))")
    }

    /// Goes back to ~/Downloads/Orangeflix.
    func resetDownloadFolder() {
        services.folders.clear()
        downloadFolder = FolderBookmarkStore.defaultFolder()
        show("Speicherort: \(AppFormat.displayPath(downloadFolder))")
    }

    /// Opens the download folder for writing. The caller must call `stop()`
    /// on the returned access (nil for the default folder, which needs no
    /// security scope) when done.
    func accessDownloadFolder() throws -> (url: URL, access: ScopedFolderAccess?) {
        if let access = try services.folders.access() {
            return (access.url, access)
        }
        let url = FolderBookmarkStore.defaultFolder()
        try FolderBookmarkStore.ensureWritable(url)
        return (url, nil)
    }

    // MARK: Protokoll and status

    /// Appends a line to the Protokoll (Go `logf`).
    func record(_ text: String, error: Bool = false) {
        nextLogID += 1
        log.append(LogLine(id: nextLogID, time: Date(), text: text, isError: error))
        if log.count > 500 { log.removeFirst(log.count - 500) }
        if error {
            logger.error("\(text, privacy: .public)")
        } else {
            logger.info("\(text, privacy: .public)")
        }
    }

    /// Clears the in-memory Protokoll lines.
    func clearLog() {
        log.removeAll()
    }

    /// Shows a status message (and logs errors).
    func show(_ text: String, error: Bool = false) {
        flash(text, error: error)
        if error, !text.isEmpty { record(text, error: true) }
    }

    /// Shows a status message without a line in the Protokoll, for what is
    /// logged already. The message hides itself after a few seconds; the
    /// time belongs to the message and not to a window, so it also ends
    /// while no window shows it.
    func flash(_ text: String, error: Bool = false) {
        guard !text.isEmpty else { return }
        let next = Banner(text: text, isError: error)
        banner = next
        bannerTimer?.cancel()
        bannerTimer = Task { [weak self] in
            try? await Task.sleep(for: error ? Self.errorLifetime : Self.messageLifetime)
            guard !Task.isCancelled else { return }
            self?.dismissBanner(next)
        }
    }

    /// Takes the status message away when it is still the one that shows.
    func dismissBanner(_ shown: Banner) {
        guard banner?.id == shown.id else { return }
        banner = nil
        bannerTimer?.cancel()
        bannerTimer = nil
    }

    /// Shows an error as status message.
    func show(_ error: any Error) {
        show(error.localizedDescription, error: true)
    }
}
