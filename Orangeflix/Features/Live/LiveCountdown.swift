import Foundation

/// How long it is until a livestream starts (Go `liveCountdown`,
/// `internal/tui/helpers.go:345`). The last ten minutes count the seconds;
/// a longer wait stays in hours and minutes.
enum LiveCountdown {
    /// The time until `until`, seen from `now`.
    static func text(until: Date, now: Date) -> String {
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

    /// Go `plural`: "1 Tag", "2 Tagen".
    static func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
        count == 1 ? "1 " + singular : "\(count) " + pluralForm
    }
}
