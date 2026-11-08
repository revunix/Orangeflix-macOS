import Foundation

/// The link handling of the shell (Go `openURL`): a relative link gets the
/// orangeflix.de prefix, an empty link is an error.
@MainActor
enum ShellLinks {
    /// Opens the link in the browser. Reports "Kein Link vorhanden." for an
    /// empty link and "Link geöffnet." when the browser took it.
    static func open(_ link: String, app: AppModel) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            app.show("Kein Link vorhanden.", error: true)
            return
        }
        if AppFormat.openLink(trimmed) {
            app.record("Link geöffnet.")
        } else {
            app.show("Der Link konnte nicht geöffnet werden: \(trimmed)", error: true)
        }
    }
}
