import AppKit
import Observation
import ServiceManagement
import Sparkle
import SwiftUI

/// Lets the app keep running without a window, so notifications about new
/// episodes and livestreams keep coming: the Dock symbol goes, a symbol in
/// the menu bar stays, and the app can start hidden at login.
///
/// Without an Apple push service this is the only way to notify while the
/// window is closed; a quit app (⌘Q) sends nothing.
@MainActor @Observable final class BackgroundMode {
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Whether macOS starts the app at login.
    private(set) var launchesAtLogin = false
    /// Whether the login item waits for a yes in the system settings.
    private(set) var needsApproval = false
    /// Why the last change of the login item failed.
    private(set) var loginError: String?

    init(app: AppModel) {
        self.app = app
        refreshLoginItem()
    }

    // MARK: Login item

    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        launchesAtLogin = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginItem()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Dock and windows

    /// Follows the windows: the last one closing hides the Dock symbol when
    /// the app runs in the background, a new one brings it back.
    func observeWindows() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated {
                // The window is still listed while it closes.
                DispatchQueue.main.async { self?.updateDock(ignoring: closing) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDock(ignoring: nil) }
        })
    }

    /// The windows the user sees (also minimized ones); the menu bar and
    /// its menus do not count.
    private static func userWindows(ignoring closing: NSWindow?) -> [NSWindow] {
        NSApp.windows.filter { window in
            window !== closing && (window.isVisible || window.isMiniaturized)
                && window.styleMask.contains(.titled) && window.level == .normal
        }
    }

    func updateDock(ignoring closing: NSWindow? = nil) {
        let hasWindows = !Self.userWindows(ignoring: closing).isEmpty
        let policy: NSApplication.ActivationPolicy = app.settings.runsInBackground && !hasWindows ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Brings the main window to the front, or opens a new one.
    func showMainWindow(using openWindow: OpenWindowAction? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let window = NSApp.windows.first(where: Self.isMainWindow) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else if let openWindow {
            openWindow(id: MainWindowSize.sceneID)
        } else {
            app.openMainWindow?()
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(MainWindowSize.sceneID) == true && window.styleMask.contains(.titled)
    }

    /// After a hidden start at login: no window, no Dock symbol.
    func hideForLoginLaunch() {
        guard app.settings.runsInBackground else { return }
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI opens its window right after the launch.
        for delay in [0.1, 0.5, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows where Self.isMainWindow(window) { window.close() }
            }
        }
    }
}

/// The delegate of the application: starts the background work without a
/// window and notices a start at login.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `OrangeflixApp.init`, before the launch finishes.
    static var container: AppContainer?
    private var container: AppContainer? { Self.container }
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A login item is opened with this marker in the open event.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedAtLogin = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let container else { return }
        container.background.observeWindows()
        if launchedAtLogin { container.background.hideForLoginLaunch() }
        // The checks need no window: start them here, not in the window.
        Task {
            await container.app.start()
            if container.app.hasCredentials {
                container.watcher.start()
                container.live.start()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A click on the Dock symbol without a window opens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { container?.background.showMainWindow() }
        return false
    }
}

/// Compact macOS menu bar mini-dashboard shown while running in the background.
struct BackgroundMenu: View {
    let container: AppContainer
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let watcher = container.watcher
        let playback = container.playback
        let downloads = container.downloads

        VStack(alignment: .leading, spacing: Space.m) {
            // Header
            HStack(spacing: Space.s) {
                IrisColorMark()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Orangeflix")
                        .font(AppFont.heading)
                        .foregroundStyle(Palette.textPrimary)
                    Text(watcher.liveTitle != nil ? "Gerade live auf Sendung" : "Läuft im Hintergrund")
                        .font(AppFont.caption)
                        .foregroundStyle(watcher.liveTitle != nil ? Palette.live : Palette.textSecondary)
                }
                Spacer(minLength: Space.s)
                Button {
                    container.background.showMainWindow(using: openWindow)
                    dismiss()
                } label: {
                    Label("Öffnen", systemImage: "macwindow")
                        .font(AppFont.captionMedium)
                }
                .controlSize(.small)
                .keyboardShortcut("o")
            }

            // Live show card
            if let liveTitle = watcher.liveTitle {
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(Palette.live)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("JETZT LIVE")
                            .font(AppFont.micro)
                            .tracking(0.6)
                            .foregroundStyle(Palette.live)
                        Text(liveTitle)
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.xs)
                    Button("Ansehen") {
                        container.app.selection = .live
                        container.background.showMainWindow(using: openWindow)
                        dismiss()
                    }
                    .controlSize(.small)
                }
                .padding(Space.m)
                .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .strokeBorder(Palette.live.opacity(0.35), lineWidth: 1)
                }
            }

            // Active playback card
            if playback.isPlaying, let current = playback.current {
                HStack(spacing: Space.s) {
                    Image(systemName: playback.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(current.title)
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if !current.detail.isEmpty {
                            Text(current.detail)
                                .font(AppFont.caption)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: Space.xs)
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPaused ? "play.fill" : "pause.fill")
                            .frame(width: 24, height: 24)
                    }
                    .controlSize(.small)
                }
                .padding(Space.s)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .strokeBorder(Palette.divider, lineWidth: 1)
                }
            }

            // Active downloads bar
            if let progress = downloads.overallProgress, downloads.activeCount > 0 {
                Button {
                    container.app.selection = .downloads
                    container.background.showMainWindow(using: openWindow)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(
                                downloads.activeCount == 1 ? "1 Download aktiv" : "\(downloads.activeCount) Downloads aktiv",
                                systemImage: "arrow.down.circle.fill"
                            )
                            .font(AppFont.captionMedium)
                            .foregroundStyle(Palette.textPrimary)
                            Spacer()
                            Text(AppFormat.percent(Int((progress * 100).rounded())))
                                .font(AppFont.digits)
                                .foregroundStyle(Palette.accentText)
                        }
                        ProgressView(value: progress)
                            .tint(Palette.accent)
                    }
                    .padding(Space.s)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                            .strokeBorder(Palette.divider, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            Hairline()

            // Quick notification toggles
            VStack(spacing: Space.s) {
                HStack {
                    Label("Neue Folgen melden", systemImage: "bell")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Toggle("Neue Folgen melden", isOn: Binding(
                        get: { container.app.settings.notificationsOn },
                        set: { value in try? container.app.updateSettings { $0.notificationsOn = value } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack {
                    Label("Livestreams melden", systemImage: "dot.radiowaves.left.and.right")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Toggle("Livestreams melden", isOn: Binding(
                        get: { container.app.settings.liveNotificationsOn },
                        set: { value in try? container.app.updateSettings { $0.liveNotificationsOn = value } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            Hairline()

            // Footer actions
            HStack(spacing: Space.xs) {
                Button {
                    Task {
                        await watcher.check()
                        await watcher.checkLive()
                    }
                } label: {
                    Label("Prüfen", systemImage: "arrow.clockwise")
                        .font(AppFont.captionMedium)
                }
                .controlSize(.small)
                .help("Jetzt auf neue Folgen und Livestreams prüfen")

                Button {
                    updaterController.checkForUpdates(nil)
                    dismiss()
                } label: {
                    Label("Updates", systemImage: "arrow.down.app")
                        .font(AppFont.captionMedium)
                }
                .controlSize(.small)

                Spacer(minLength: 0)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .controlSize(.small)
                .keyboardShortcut(",")
                .help("Einstellungen öffnen")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .foregroundStyle(Palette.danger)
                }
                .controlSize(.small)
                .keyboardShortcut("q")
                .help("Orangeflix beenden")
            }
        }
        .padding(Space.l)
        .frame(width: 310)
        .tint(Palette.accent)
        .background(Palette.background)
    }
}
