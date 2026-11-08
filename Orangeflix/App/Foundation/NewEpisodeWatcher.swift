import AppKit
import Foundation
import Observation
import UserNotifications
import os

/// Announces a new episode of the magazines the reader picked in the
/// settings. The app checks the catalog while it runs; the notification shows
/// which format has something new and opens the app.
@MainActor @Observable
final class NewEpisodeWatcher {
    /// How often the catalog is read while the app runs.
    private static let interval: Duration = .seconds(15 * 60)
    /// How often the livestream state is read; a start should not be missed
    /// by much, one small request every two minutes is cheap.
    private static let liveInterval: Duration = .seconds(2 * 60)

    private let app: AppModel
    private let center = UNUserNotificationCenter.current()
    private var task: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    /// Keeps macOS from ending the app while it runs without a window.
    private var activity: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "notify")

    /// Whether the system lets the app post notifications.
    private(set) var isAllowed = false
    /// Why the last check failed, for the settings page.
    private(set) var lastError: String?
    /// Opens a format (and its episode) after a click on a notification.
    @ObservationIgnored var onOpen: (@MainActor (_ pid: Int, _ episode: String?) -> Void)?
    /// Opens the Live page after a click on a livestream notification.
    @ObservationIgnored var onOpenLive: (@MainActor () -> Void)?
    /// Whether a livestream runs, as the last check saw it (menu bar).
    private(set) var liveTitle: String?
    /// Keeps the delegate alive; the center holds it only weakly.
    private let delegate = NotificationDelegate()

    init(app: AppModel) {
        self.app = app
        // Without a delegate macOS hides every banner while the app is in
        // front, and a click on a notification does nothing.
        if Bundle.main.bundleIdentifier != nil {
            center.delegate = delegate
            delegate.onOpen = { [weak self] pid, episode in
                NSApp.activate()
                self?.onOpen?(pid, episode)
            }
            delegate.onOpenLive = { [weak self] in
                NSApp.activate()
                self?.onOpenLive?()
            }
        }
    }

    /// Starts the loop and asks for the permission the first time.
    /// Starts both loops; they run as long as the app runs, with or
    /// without a window.
    func start() {
        guard task == nil else { return }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Mitteilungen über neue Folgen und Livestreams")
        }
        task = Task { [weak self] in
            await self?.refreshPermission()
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkLive()
                try? await Task.sleep(for: Self.liveInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        liveTask?.cancel()
        liveTask = nil
        liveTitle = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// Announces a livestream once when it starts. The first check after a
    /// start of the app announces a stream that already runs too, unless it
    /// was announced before.
    func checkLive() async {
        guard app.settings.liveNotificationsOn else {
            liveTitle = nil
            return
        }
        let info: LivestreamInfo
        do {
            try await app.ensureSession()
            info = try await app.services.api.liveActive(refresh: true)
        } catch {
            return
        }
        guard info.isLive else {
            liveTitle = nil
            return
        }
        let show = info.show
        let title = show?.title.isEmpty == false ? show!.title : "Livestream"
        liveTitle = title
        // The show id, else its start, else the title: one key per stream.
        let key = [show?.id ?? "", show.map { String($0.begin) } ?? "", title]
            .first { !$0.isEmpty && $0 != "0" } ?? title
        guard key != app.settings.announcedLiveShow else { return }
        try? app.updateSettings { $0.announcedLiveShow = key }
        logger.notice("Live: \(title, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Jetzt live"
        content.body = info.hasAccess || info.canAccess == nil ? title : "\(title) (ohne Zugang für dein Konto)"
        content.sound = .default
        content.threadIdentifier = "live"
        content.userInfo = ["live": true]
        do {
            try await center.add(UNNotificationRequest(identifier: "live-" + key, content: content, trigger: nil))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reads the permission and asks for it when the app may still ask.
    func refreshPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                isAllowed = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                isAllowed = false
                lastError = error.localizedDescription
                logger.notice("Mitteilungen nicht erlaubt: \(error.localizedDescription, privacy: .public)")
            }
        case .denied:
            isAllowed = false
        default:
            isAllowed = true
        }
    }

    /// Opens the notification settings of the system for this app.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Sends a notification right away, for the switch in the settings.
    func sendTestNotification() async {
        await refreshPermission()
        guard isAllowed else {
            lastError = "Mitteilungen sind in den Systemeinstellungen für Orangeflix nicht erlaubt."
            return
        }
        await post(title: "Orangeflix", body: "Mitteilungen sind eingeschaltet.")
    }

    /// The key in `announcedEpisodes` that holds the publication time of
    /// the newest episode already handled; later episodes are new.
    private static let watermarkKey = "feed.since"
    /// More new episodes of one format than this become one summary.
    private static let singleLimit = 3

    /// Reads the newest episodes of the feed (one request, never the stored
    /// copy) and announces those of the chosen formats that were published
    /// after the last check. The first check only notes the time, so
    /// nothing old pops up.
    func check() async {
        guard app.settings.notificationsOn, !app.settings.notifiedMagazines.isEmpty else { return }
        do {
            try await app.ensureSession()
        } catch {
            return
        }
        let episodes: [Episode]
        do {
            let clips = try await app.services.api.feed(
                FeedQuery(count: 50, includePremium: true, includeEarlyAccess: true), refresh: true)
            episodes = clips.map(\.episode)
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            logger.notice("Feed nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return
        }
        lastError = nil
        let newest = episodes.compactMap { $0.date?.timeIntervalSince1970 }.max()
        guard let newest else { return }
        let since = app.settings.announcedEpisodes[Self.watermarkKey]
        let fresh = NewEpisodeLogic.fresh(episodes, since: since, formats: Set(app.settings.notifiedMagazines))
        for group in fresh {
            logger.notice("Neue Folgen: \(group.formatName, privacy: .public) (\(group.episodes.count, privacy: .public))")
            await post(group)
        }
        if since == nil || newest > since ?? 0 {
            // Only the watermark stays; the keys of the old catalog check go.
            try? app.updateSettings { $0.announcedEpisodes = [Self.watermarkKey: max(newest, since ?? 0)] }
        }
    }

    private func post(_ group: NewEpisodeLogic.Group) async {
        let first = group.episodes[0]
        let body: String
        if group.episodes.count <= Self.singleLimit {
            body = group.episodes.map(BrowseLogic.title(of:)).joined(separator: "\n")
        } else {
            body = "\(group.episodes.count) neue Folgen, zuletzt „\(BrowseLogic.title(of: first))“"
        }
        await post(title: group.episodes.count == 1 ? "Neue Folge · \(group.formatName)" : "Neue Folgen · \(group.formatName)",
                   body: body, magazine: group.pid, episode: group.episodes.count == 1 ? first.identifier : nil,
                   identifier: "episode-" + first.identifier)
    }

    private func post(title: String, body: String, magazine: Int? = nil, episode: String? = nil,
                      identifier: String = UUID().uuidString) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = magazine.map(String.init) ?? "orangeflix"
        var info: [String: Any] = [:]
        if let magazine { info["pid"] = magazine }
        if let episode { info["episode"] = episode }
        content.userInfo = info
        // The same episode never shows twice, even after a second check.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
            logger.error("Mitteilung nicht gesendet: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Shows the notifications of the app while it is in front too and passes
/// a click on to the watcher.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    @MainActor var onOpen: (@MainActor (Int, String?) -> Void)?
    @MainActor var onOpenLive: (@MainActor () -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let pid = info["pid"] as? Int
        let episode = info["episode"] as? String
        let live = info["live"] as? Bool ?? false
        Task { @MainActor [weak self] in
            if live { self?.onOpenLive?() }
            else if let pid { self?.onOpen?(pid, episode) }
            else { NSApp.activate() }
        }
        completionHandler()
    }
}
