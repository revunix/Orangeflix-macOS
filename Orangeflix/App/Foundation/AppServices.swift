import Foundation

/// The long-lived services of the app. Created once at launch and shared by
/// every feature model.
final class AppServices: Sendable {
    /// The client of the version 3 API.
    let api: OrangeflixAPI
    /// The persisted answers of the API (catalog, feeds, lists).
    let cache: ResponseCache
    /// The SQLite library (formats, episode history, settings of the CLI).
    let store: LibraryStore
    /// Login and session tokens.
    let credentials: CredentialStore
    /// The GUI settings (quality, layout, parallel downloads, …).
    let settingsStore: SettingsStore
    /// The security-scoped bookmark of the download folder.
    let folders: FolderBookmarkStore

    init(
        api: OrangeflixAPI,
        cache: ResponseCache,
        store: LibraryStore,
        credentials: CredentialStore,
        settingsStore: SettingsStore,
        folders: FolderBookmarkStore
    ) {
        self.api = api
        self.cache = cache
        self.store = store
        self.credentials = credentials
        self.settingsStore = settingsStore
        self.folders = folders
    }

    /// The services of the running app. Throws when the library database
    /// cannot be opened.
    static func live() throws -> AppServices {
        let cache = try ResponseCache()
        return AppServices(
            api: OrangeflixAPI(deviceName: "Orangeflix für macOS", cache: cache),
            cache: cache,
            store: try LibraryStore(),
            credentials: try CredentialStore(),
            settingsStore: SettingsStore(),
            folders: FolderBookmarkStore()
        )
    }
}
