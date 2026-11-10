import Foundation
import Observation

/// The models of the app. They live for the whole run of the app and are
/// shared between the main window, the player window and the settings
/// window.
@MainActor @Observable final class AppContainer {
    /// The shared state.
    let app: AppModel
    /// The subscription and the library numbers.
    let account: AccountModel
    /// The calendar.
    let calendar: CalendarModel
    /// The announcements.
    let announcements: AnnouncementsModel
    /// The formats, the episodes and the lists.
    let browse: BrowseModel
    /// The downloads.
    let downloads: DownloadCenter
    /// The playback.
    let playback: PlaybackCenter
    /// The live show with the chat and the voting.
    let live: LiveModel
    /// Announces new episodes of the magazines chosen in the settings.
    let watcher: NewEpisodeWatcher
    /// The sharing links of the account.
    let sharing: SharingModel
    /// The notifications of the account.
    let notifications: NotificationSettingsModel
    /// The preferences and the personal data of the account.
    let profile: ProfileModel
    /// The sessions of the account.
    let sessions: SessionModel
    /// The menu bar mode and the start at login.
    let background: BackgroundMode

    init(services: AppServices) {
        let app = AppModel(services: services)
        self.app = app
        self.account = AccountModel(app: app)
        self.calendar = CalendarModel(app: app)
        self.announcements = AnnouncementsModel(app: app)
        self.browse = BrowseModel(app: app)
        self.downloads = DownloadCenter(app: app)
        self.playback = PlaybackCenter(app: app)
        self.live = LiveModel(app: app)
        self.watcher = NewEpisodeWatcher(app: app)
        self.sharing = SharingModel(app: app)
        self.notifications = NotificationSettingsModel(app: app)
        self.profile = ProfileModel(app: app)
        self.sessions = SessionModel(app: app)
        let background = BackgroundMode(app: app)
        self.background = background
        app.downloads = downloads
        app.playback = playback
        playback.browseModel = browse
        // A click on a new-episode notification opens the episodes of its format.
        watcher.onOpen = { [weak app, weak browse, weak background] pid, _ in
            guard let app, let browse else { return }
            app.selection = .formats
            browse.formatsPath = [.episodes(pid: pid)]
            background?.showMainWindow()
        }
        // A click on a livestream notification opens the Live page.
        watcher.onOpenLive = { [weak app, weak background] in
            app?.selection = .live
            background?.showMainWindow()
        }
        // A mention or a reaction of the chat is announced by the watcher;
        // a click on it opens the Live page too.
        live.notify = { [weak watcher] title, body in
            watcher?.notifyChat(title: title, body: body)
        }
    }
}
