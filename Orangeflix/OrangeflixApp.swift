import SwiftUI
import Sparkle

@main
struct OrangeflixApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    /// The models of the app; nil when the library database cannot be opened.
    private let container: AppContainer?
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        do {
            let services = try AppServices.live()
            container = AppContainer(services: services)
            AppDelegate.container = container
        } catch {
            container = nil
            NSLog("Die Bibliothek konnte nicht geöffnet werden: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup(id: MainWindowSize.sceneID) {
            mainWindow
        }
        .defaultSize(width: MainWindowSize.fallback.width, height: MainWindowSize.fallback.height)
        // The size lives in `MainWindowSize`; the frame the window server
        // saved would compete with it.
        .restorationBehavior(.disabled)
        // The window follows the page: its minimum, or the fixed size of
        // the Live page.
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(container: container, updaterController: updaterController) }

        PlayerWindowScene(playback: container?.playback, app: container?.app)
        SettingsWindowScene(container: container, updaterController: updaterController)

        // The symbol in the menu bar while the app runs in the background.
        BackgroundMenuScene(container: container, updaterController: updaterController)
    }

    @ViewBuilder
    private var mainWindow: some View {
        if let container {
            MainWindowView()
                // The smallest window comes from `MainWindowView`, per page. No frame
                // here: an outer minimum would cap the one of the page.
                .opensPlayerWindow()
                .environment(container.app)
                .environment(container.account)
                .environment(container.calendar)
                .environment(container.announcements)
                .environment(container.browse)
                .environment(container.downloads)
                .environment(container.playback)
                .environment(container.live)
                .environment(container.watcher)
                .environment(container.sharing)
                .environment(container.sessions)
        } else {
            ContentUnavailableView(
                "Die Bibliothek konnte nicht geöffnet werden",
                systemImage: "exclamationmark.triangle",
                description: Text("Der Ordner der App ist nicht zugreifbar. Bitte die App neu starten."))
        }
    }
}

/// The menu bar of the app; empty when the library could not be opened.
struct AppCommands: Commands {
    let container: AppContainer?
    let updaterController: SPUStandardUpdaterController

    var body: some Commands {
        if let container {
            ShellCommands(app: container.app, account: container.account, updaterController: updaterController)
        }
    }
}

/// The window of the player (Go: mpv opens its own window).
struct PlayerWindowScene: Scene {
    let playback: PlaybackCenter?
    let app: AppModel?

    var body: some Scene {
        Window("Wiedergabe", id: "player") {
            if let playback {
                PlayerScreen(playback: playback)
                    .environment(playback)
                    .environment(\.interfaceStyle, app?.settings.interfaceStyle ?? .glass)
                    .environment(\.glassPanels, app?.settings.glassPanels ?? true)
                    .frame(minWidth: 640, minHeight: 360)
            } else {
                ContentUnavailableView("Keine Wiedergabe", systemImage: "play.slash")
            }
        }
        .defaultSize(width: 1_120, height: 630)
        .windowStyle(.hiddenTitleBar)
        // The window belongs to a running playback; after a restart there is none.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The window of the settings. A `Settings` scene, so the gear of the
/// toolbar and ⌘, open it the way macOS expects.
struct SettingsWindowScene: Scene {
    let container: AppContainer?
    let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        Settings {
            if let container {
                SettingsScreen(updaterController: updaterController)
                    .environment(container.app)
                    .environment(container.account)
                    .environment(container.browse)
                    .environment(container.playback)
                    .environment(container.live)
                    .environment(container.watcher)
                    .environment(container.sharing)
                    .environment(container.notifications)
                    .environment(container.profile)
                    .environment(container.sessions)
                    .environment(container.background)
            } else {
                ContentUnavailableView("Keine Einstellungen", systemImage: "gearshape")
                    .frame(width: 480, height: 320)
            }
        }
        // The size of the first frame. Without it the system opens the
        // standard size of a Settings window and `WindowContentSize` brings
        // it to the size of the view right after, and the jump is visible.
        .defaultSize(width: SettingsScreen.windowSize.width, height: SettingsScreen.windowSize.height)
        .windowToolbarStyle(.unified)
    }
}

/// The symbol in the menu bar; it shows while the app runs in the background.
struct BackgroundMenuScene: Scene {
    let container: AppContainer?
    let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { container?.app.settings.runsInBackground ?? false },
            set: { value in try? container?.app.updateSettings { $0.runsInBackground = value } })
        ) {
            if let container {
                BackgroundMenu(container: container, updaterController: updaterController)
            }
        } label: {
            // The monochrome iris; a dot joins it while a livestream runs.
            Image(nsImage: container?.watcher.liveTitle == nil ? IrisMenuBarIcon.plain : IrisMenuBarIcon.live)
        }
    }
}
