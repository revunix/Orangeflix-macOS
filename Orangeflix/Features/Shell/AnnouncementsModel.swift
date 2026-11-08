import Foundation
import Observation

/// The announcements of the "overview" surface (Go `App.Announcements`,
/// internal/app/v3.go:494-545). They are loaded at the start of the app and
/// shown in the Ankündigungen screen.
@MainActor @Observable final class AnnouncementsModel {
    @ObservationIgnored private let app: AppModel

    /// The announcements of the last load, newest first as the API sends
    /// them.
    private(set) var items: [Announcement] = []
    /// Whether the announcements are loading.
    private(set) var isLoading = false
    /// Whether they were loaded at least once.
    private(set) var hasLoaded = false
    /// The error of the last load.
    private(set) var errorText: String?
    /// When the announcements were last loaded; nil loads them again.
    private(set) var lastLoadedAt: Date?

    init(app: AppModel) {
        self.app = app
    }

    /// Loads the announcements (Go `loadAnnouncements`: surface "overview",
    /// ten entries). The count is shown as a status message, like the TUI
    /// does at the start.
    /// - Parameter force: asks the API instead of the stored answer.
    func load(force: Bool = false) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            items = try await app.services.api.announcements(surface: "overview", limit: 10, refresh: force)
            hasLoaded = true
            lastLoadedAt = Date()
            if !items.isEmpty, app.banner == nil {
                app.show("\(items.count) Ankündigung(en) · unter „Ankündigungen“ öffnen")
            }
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
            app.show(error)
        }
    }

    /// Loads the announcements unless they were loaded within
    /// `CacheTTL.announcements`.
    func loadIfNeeded() async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) <= CacheTTL.announcements { return }
        await load()
    }
}

extension Announcement {
    /// A stable list identity (the API id, else the date and the title).
    var shellID: String {
        id.isEmpty ? "\(date)-\(type)-\(title)" : "\(type)-\(id)"
    }

    /// The "Typ" of the detail pane.
    var shellType: String {
        type.isEmpty ? "HINWEIS" : type.uppercased()
    }

    /// The text of the announcement: the description, else the short
    /// description, else the markdown body (Go `announcementDetail`).
    var shellText: String {
        if !description.isEmpty { return description }
        if !shortDescription.isEmpty { return shortDescription }
        return bodyMarkdown
    }
}
