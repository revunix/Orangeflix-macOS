import AppKit
import Foundation
import UserNotifications

/// Tells the user about a finished download run while the app is in the
/// background (the GUI counterpart of the Go tool's headless finish notice).
@MainActor final class DownloadNotifier {
    private var authorizationRequested = false

    /// Notifications need an app bundle; command line hosts have none.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Asks for permission once, when the first run starts and the user is
    /// at the app.
    func prepare() {
        guard isAvailable, !authorizationRequested else { return }
        authorizationRequested = true
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Posts the summary of a run when the app is not active.
    func notifyFinished(_ summary: DownloadSummary) {
        guard isAvailable, !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = summary.failed > 0 ? "Downloads fehlgeschlagen" : "Downloads fertig"
        content.body = summary.failed > 0 ? summary.failureText : summary.finishedText
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
