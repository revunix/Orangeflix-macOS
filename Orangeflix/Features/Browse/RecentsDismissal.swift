import Foundation

/// The API cannot remove a clip from "recently watched": the list is the
/// watch history of the account and has no delete. The app therefore keeps
/// the clips the user removed, with the time, and hides them until the clip
/// is watched again (a later `lastAccessed`).
enum RecentsDismissal {
    /// The server stamps `lastAccessed` itself when the progress is reset;
    /// its clock may also run ahead. Accesses this close after the removal
    /// still count as the removal, not as a new watch.
    static let tolerance: TimeInterval = 10 * 60

    /// Whether a removed clip stays hidden. Without a readable access time
    /// it stays hidden.
    static func isHidden(lastAccessed: String, dismissedAt: Double?) -> Bool {
        guard let dismissedAt else { return false }
        guard let accessed = date(lastAccessed) else { return true }
        return accessed.timeIntervalSince1970 <= dismissedAt + tolerance
    }

    /// The removals still needed: a clip no longer in the list, or watched
    /// again, needs no entry any more. Keeps the stored map small.
    static func pruned(_ dismissed: [String: Double], visibleIn clips: [(id: String, lastAccessed: String)]) -> [String: Double] {
        var kept: [String: Double] = [:]
        for clip in clips {
            if let at = dismissed[clip.id], isHidden(lastAccessed: clip.lastAccessed, dismissedAt: at) {
                kept[clip.id] = at
            }
        }
        return kept
    }

    /// ISO 8601 (recents), with or without fractions, or "YYYY-MM-DD HH:MM:SS"
    /// in UTC (the other paths).
    static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return plain.date(from: trimmed)
    }
}
