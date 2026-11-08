import Foundation

/// The header hint for the running or the next livestream (Go
/// `nextLiveHint`, `nextLiveEntry`, `formatNextLive`, `liveCountdown`,
/// internal/tui/helpers.go:279-400).
enum ShellLiveHint {
    /// Names the running or the next livestream, "" when none is known.
    /// `live` is the state of the Live screen when it was loaded.
    static func hint(entries: [CalendarEntry], live: LivestreamInfo?, now: Date,
                     timeZone: TimeZone = .current) -> String {
        if let live, live.isLive {
            var title = "Livesendung"
            if let show = live.show, !show.title.isEmpty { title = show.title }
            return "● LIVE · " + truncate(title, 24)
        }
        let unix = Int64(now.timeIntervalSince1970.rounded(.down))
        if let entry = nextLiveEntry(entries, now: now) {
            if let live = entry.live, entry.timestamp <= unix, live.end > unix {
                return "● LIVE · " + truncate(entry.title, 24)
            }
            return formatNextLive(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), now: now,
                                  title: entry.title, timeZone: timeZone)
        }
        if let scheduled = live?.scheduled, scheduled.begin > unix {
            return formatNextLive(Date(timeIntervalSince1970: TimeInterval(scheduled.begin)), now: now,
                                  title: scheduled.title, timeZone: timeZone)
        }
        return ""
    }

    /// The livestream that is on now, or the soonest one that has not
    /// started. Other calendar entries are ignored.
    static func nextLiveEntry(_ entries: [CalendarEntry], now: Date) -> CalendarEntry? {
        let unix = Int64(now.timeIntervalSince1970.rounded(.down))
        var next: CalendarEntry?
        for entry in entries where entry.type == "live" {
            if let live = entry.live, entry.timestamp <= unix, live.end > unix {
                return entry
            }
            if entry.timestamp < unix { continue }
            if next == nil || entry.timestamp < next!.timestamp {
                next = entry
            }
        }
        return next
    }

    /// "heute 19:00 · in 2 Std. 47 Min. · Titel" relative to today.
    static func formatNextLive(_ when: Date, now: Date, title: String, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = String(format: "%02d:%02d",
                           calendar.component(.hour, from: when), calendar.component(.minute, from: when))
        let day: String
        if calendar.isDate(when, inSameDayAs: now) {
            day = "heute " + clock
        } else if let tomorrow = nextCalendarDay(now, calendar: calendar),
                  calendar.isDate(when, inSameDayAs: tomorrow) {
            day = "morgen " + clock
        } else {
            day = shortWeekday(when, calendar: calendar) + " " + clock
        }
        return day + " · " + countdown(until: when, now: now) + " · " + truncate(title, 24)
    }

    /// How long it is until a livestream starts. The last ten minutes count
    /// the seconds; a longer wait stays in hours and minutes.
    static func countdown(until: Date, now: Date) -> String {
        let rest = until.timeIntervalSince(now)
        if rest < 1 { return "gleich" }
        let seconds = Int(rest)
        if seconds < 60 {
            return "in " + plural(seconds, "Sek.", "Sek.")
        }
        if seconds < 10 * 60 {
            let minutes = seconds / 60
            let remain = seconds % 60
            var text = "in " + plural(minutes, "Min.", "Min.")
            if remain > 0 { text += " " + plural(remain, "Sek.", "Sek.") }
            return text
        }
        if seconds < 24 * 60 * 60 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if hours == 0 { return "in " + plural(minutes, "Min.", "Min.") }
            if minutes == 0 { return "in " + plural(hours, "Std.", "Std.") }
            return "in " + plural(hours, "Std.", "Std.") + " " + plural(minutes, "Min.", "Min.")
        }
        let days = seconds / (24 * 60 * 60)
        let hours = (seconds % (24 * 60 * 60)) / 3600
        if hours == 0 { return "in " + plural(days, "Tag", "Tagen") }
        return "in " + plural(days, "Tag", "Tagen") + " " + plural(hours, "Std.", "Std.")
    }

    /// The start time of the next entry the hint counts down to, used to
    /// switch the refresh to seconds in the last ten minutes.
    static func nextStart(entries: [CalendarEntry], live: LivestreamInfo?, now: Date) -> Date? {
        if let live, live.isLive { return nil }
        let unix = Int64(now.timeIntervalSince1970.rounded(.down))
        if let entry = nextLiveEntry(entries, now: now) {
            if let live = entry.live, entry.timestamp <= unix, live.end > unix { return nil }
            return Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
        }
        if let scheduled = live?.scheduled, scheduled.begin > unix {
            return Date(timeIntervalSince1970: TimeInterval(scheduled.begin))
        }
        return nil
    }

    /// Noon on the following local date; noon avoids the repeated hour when
    /// the clocks go back.
    private static func nextCalendarDay(_ now: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.day = (parts.day ?? 1) + 1
        parts.hour = 12
        return calendar.date(from: parts)
    }

    /// The German abbreviation of the weekday.
    private static func shortWeekday(_ date: Date, calendar: Calendar) -> String {
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        return names[calendar.component(.weekday, from: date) - 1]
    }

    /// Go `plural`: "1 Tag", "2 Tagen".
    static func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
        count == 1 ? "1 " + singular : "\(count) " + pluralForm
    }

    /// Go `truncateColumn`: at most `width` characters, cut with "…".
    static func truncate(_ value: String, _ width: Int) -> String {
        guard width > 0 else { return "" }
        guard value.count > width else { return value }
        return String(value.prefix(width - 1)) + "…"
    }
}
