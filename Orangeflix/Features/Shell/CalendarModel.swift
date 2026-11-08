import Foundation
import Observation

/// One day of the calendar.
struct CalendarDay: Identifiable, Hashable, Sendable {
    /// Unique within one grouping (the date, plus a counter when the API
    /// repeats a date after another one).
    let id: String
    /// The date as the API sends it; the group header.
    let date: String
    let entries: [CalendarEntry]
}

/// The calendar (Go `loadCalendar` with 100 entries) and the quiet load of
/// 20 entries for the live hint (Go `loadCalendarQuiet`).
@MainActor @Observable final class CalendarModel {
    @ObservationIgnored private let app: AppModel

    /// The entries of the last load, in API order.
    private(set) var entries: [CalendarEntry] = []
    /// Whether the full calendar is loading.
    private(set) var isLoading = false
    /// Whether the full calendar was loaded at least once.
    private(set) var hasLoaded = false
    /// The error of the last full load.
    private(set) var errorText: String?
    /// When the calendar was last loaded; nil loads it again.
    private(set) var lastLoadedAt: Date?

    init(app: AppModel) {
        self.app = app
    }

    /// The entries grouped by their date in API order, each day sorted by
    /// time (Go `calendarRows`).
    var days: [CalendarDay] {
        Self.group(entries)
    }

    /// Loads the calendar for the screen ("Lade den Kalender …").
    /// - Parameter force: asks the API instead of the stored answer.
    func load(force: Bool = false) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            entries = try await app.services.api.calendar(limit: 100, refresh: force)
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            errorText = error.localizedDescription
            app.show(error)
        }
    }

    /// Loads the calendar unless it was loaded within `CacheTTL.calendar`; a
    /// section switch then shows the known entries at once.
    func loadIfNeeded() async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) <= CacheTTL.calendar { return }
        await load()
    }

    /// Loads the next entries for the live hint without a message; a
    /// failure keeps the old entries (Go `CalendarMsg{Background: true}`).
    /// A full calendar that is already there is kept.
    func loadQuietly() async {
        do {
            try await app.ensureSession()
            let next = try await app.services.api.calendar(limit: 20)
            if !hasLoaded { entries = next }
        } catch {
            return
        }
    }

    /// Go `calendarRows`: consecutive entries with the same date form a
    /// group; the group is sorted (stable) by the time string.
    static func group(_ entries: [CalendarEntry]) -> [CalendarDay] {
        var groups: [(date: String, items: [CalendarEntry])] = []
        for entry in entries {
            if groups.isEmpty || groups[groups.count - 1].date != entry.date {
                groups.append((entry.date, []))
            }
            groups[groups.count - 1].items.append(entry)
        }
        // Several groups can carry the same date when the API is not
        // sorted; the id gets the position so the list stays unique.
        var seen: [String: Int] = [:]
        return groups.map { group in
            let sorted = group.items.enumerated()
                .sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }
                .map(\.element)
            let count = seen[group.date, default: 0]
            seen[group.date] = count + 1
            return CalendarDay(id: count == 0 ? group.date : "\(group.date)#\(count)", date: group.date, entries: sorted)
        }
    }

    // MARK: Actions

    /// Opens the Live view for a live entry.
    func openLive(_ entry: CalendarEntry) {
        guard entry.type == "live" else { return }
        app.selection = .live
    }

    /// Opens the link of the entry in the browser.
    func openLink(_ entry: CalendarEntry) {
        Self.open(entry.url, app: app)
    }

    /// Copies the title.
    func copyTitle(_ entry: CalendarEntry) {
        AppFormat.copy(entry.title)
        app.show("Kopiert.")
    }

    /// Go `openURL`: "Kein Link vorhanden." / "Link geöffnet.".
    static func open(_ link: String, app: AppModel) {
        ShellLinks.open(link, app: app)
    }
}

extension CalendarEntry {
    /// "LIVE", "EVENT" or "TERMIN".
    var shellBadge: String {
        switch type {
        case "live": "LIVE"
        case "event": "EVENT"
        default: "TERMIN"
        }
    }

    /// A stable list identity (the API id, else start + title).
    var shellID: String {
        id.isEmpty ? "\(timestamp)-\(type)-\(title)" : "\(type)-\(id)-\(timestamp)"
    }
}
