import AppKit
import Foundation

/// German formatting and small desktop helpers shared by the features.
enum AppFormat {
    private static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = berlin
        formatter.dateFormat = pattern
        return formatter
    }

    private static let dayFormatter = formatter("dd.MM.yyyy")
    private static let dayMonthFormatter = formatter("dd.MM.")
    private static let dateTimeFormatter = formatter("dd.MM.yyyy HH:mm")
    private static let timeFormatter = formatter("HH:mm")
    private static let clockFormatter = formatter("HH:mm:ss")

    /// "05.11.2026"
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// "05.11."
    static func dayMonth(_ date: Date) -> String { dayMonthFormatter.string(from: date) }
    /// "05.11.2026 22:30"
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }
    /// "22:30"
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    /// "22:30:05" (Protokoll)
    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// "1,2 GB" — decimal units like the TUI's humanBytes.
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// A percentage supplied as whole percentage points, not a fraction.
    static func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "mm:ss" or "h:mm:ss" for player positions.
    static func position(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "weniger als einer Minute", "1 Minute", "12 Minuten", "2 Stunden 5 Minuten".
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "weniger als einer Minute" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60, rest = minutes % 60
        let minuteText = rest == 1 ? "1 Minute" : "\(rest) Minuten"
        guard hours > 0 else { return minuteText }
        let hourText = hours == 1 ? "1 Stunde" : "\(hours) Stunden"
        return rest == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    /// The path with the home folder shortened to "~".
    static func displayPath(_ url: URL) -> String {
        let path = url.path
        let home = realHome()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The user's home folder, not the sandbox container.
    private static func realHome() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    // MARK: Desktop helpers

    /// Copies text to the clipboard.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens a link in the browser; relative links get the orangeflix.de
    /// prefix like the TUI. Returns false when there is no usable link.
    @discardableResult
    static func openLink(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let absolute = trimmed.hasPrefix("/") ? "https://orangeflix.de" + trimmed : trimmed
        guard let url = URL(string: absolute), url.scheme != nil else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Shows a file (or folder) in the Finder.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
