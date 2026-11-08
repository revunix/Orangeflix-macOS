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

    private let app: AppModel
    private let center = UNUserNotificationCenter.current()
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "notify")

    /// Whether the system lets the app post notifications.
    private(set) var isAllowed = false
    /// Why the last check failed, for the settings page.
    private(set) var lastError: String?

    init(app: AppModel) {
        self.app = app
    }

    /// Starts the loop and asks for the permission the first time.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.refreshPermission()
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
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

    /// Reads the catalog and announces every magazine with a newer episode
    /// than the last one announced. Without a stored time the first check
    /// only notes the state, so nothing old pops up.
    func check() async {
        guard app.settings.notificationsOn, !app.settings.notifiedMagazines.isEmpty else { return }
        do {
            try await app.ensureSession()
        } catch {
            return
        }
        let magazines: [Magazine]
        do {
            magazines = try await app.services.api.magazines()
        } catch {
            lastError = error.localizedDescription
            logger.notice("Katalog nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return
        }
        lastError = nil
        var seen = app.settings.announcedEpisodes
        var announcements: [(Magazine, Double)] = []
        for magazine in magazines where app.settings.notifiedMagazines.contains(magazine.pid) {
            let stamp = Double(magazine.timeRange.max)
            guard stamp > 0 else { continue }
            let key = String(magazine.pid)
            if let known = seen[key] {
                if stamp > known + 1 { announcements.append((magazine, stamp)) }
            }
            // First sight (or a newer date): remember it. Without a stored
            // time nothing is announced, so the first start stays quiet.
            seen[key] = max(seen[key] ?? stamp, stamp)
        }
        for (magazine, stamp) in announcements {
            logger.notice("Neue Folge: \(magazine.title, privacy: .public) (\(stamp, privacy: .public))")
            await post(title: magazine.title, body: episodeLine(magazine, stamp: stamp),
                       magazine: magazine.pid, stamp: stamp)
        }
        if seen != app.settings.announcedEpisodes {
            try? app.updateSettings { $0.announcedEpisodes = seen }
        }
    }

    /// "Neue Folge verfügbar · 05.11.2026" for the body.
    private func episodeLine(_ magazine: Magazine, stamp: Double) -> String {
        let date = Date(timeIntervalSince1970: stamp)
        return "Neue Folge verfügbar · " + date.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE")))
    }

    private func post(title: String, body: String, magazine: Int? = nil, stamp: Double? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = magazine.map(String.init) ?? "orangeflix"
        if let magazine {
            content.userInfo = ["pid": magazine, "stamp": stamp ?? 0]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            lastError = error.localizedDescription
            logger.error("Mitteilung nicht gesendet: \(error.localizedDescription, privacy: .public)")
        }
    }
}
