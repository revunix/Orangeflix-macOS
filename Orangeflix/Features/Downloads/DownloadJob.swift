import Foundation
import SwiftUI

/// The state of one download in the list (the TUI job states plus the
/// GUI's "abgebrochen").
enum DownloadJobState: Sendable, Hashable {
    /// Queued, waiting for a slot, the pause or the file address.
    case waiting
    /// Bytes are arriving.
    case loading
    /// The episode was already there.
    case skipped
    /// The file is complete.
    case done
    /// The download failed.
    case failed
    /// The user cancelled it; the partial file stays.
    case cancelled

    /// The German state label of the TUI.
    var label: String {
        switch self {
        case .waiting: return "wartet"
        case .loading: return "lädt"
        case .skipped: return "übersprungen"
        case .done: return "fertig"
        case .failed: return "fehlgeschlagen"
        case .cancelled: return "abgebrochen"
        }
    }

    /// The mark of the state (Go `jobIcon`) as an SF Symbol.
    var symbolName: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .failed: return "xmark.circle.fill"
        case .waiting: return "circle"
        case .loading: return "arrow.down.circle"
        case .cancelled: return "slash.circle"
        }
    }

    /// The color of the mark: the states that are good are green, the ones
    /// that went wrong are red, the ones that are quiet stay quiet.
    var symbolColor: Color {
        switch self {
        case .done: return Palette.success
        case .failed: return Palette.danger
        case .loading: return Palette.accent
        case .waiting, .skipped, .cancelled: return Palette.textTertiary
        }
    }

    /// Whether the queue still works on the job.
    var isActive: Bool { self == .waiting || self == .loading }
}

/// One episode of the download list.
struct DownloadJob: Identifiable, Sendable, Hashable {
    /// The episode identifier (also the queue id).
    let id: String
    /// The format the download is recorded under in the library.
    let pid: Int
    /// The episode name ("Titel.S2026E012.1080p…" once the file is known).
    var label: String
    /// The target or existing file; nil until the file is known.
    var file: URL?
    var state: DownloadJobState = .waiting
    /// Bytes on disk and the size of the file (0 = unknown).
    var done: Int64 = 0
    var total: Int64 = 0
    /// Average speed of the current try.
    var bytesPerSecond: Double = 0
    /// Estimated seconds until the file is complete.
    var remaining: Double?
    /// The failure message of a failed job.
    var message: String?

    /// 0…1, nil when the size is unknown.
    var fraction: Double? {
        switch state {
        case .done, .skipped: return 1
        default: return total > 0 ? min(1, Double(done) / Double(total)) : nil
        }
    }
}

/// The German numbers of the download list: the sizes with the German
/// decimal comma ("12,4 MB") and the rest of the time in seconds
/// ("noch 9 Sekunden").
enum DownloadFormat {
    /// "12,4 MB" — decimal units, one decimal place, German comma.
    static func bytes(_ count: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(count) Bytes" }
        let number = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return "\(number) \(units[unit])"
    }

    /// "9 Sekunden", "3 Minuten", "1 Stunde 5 Minuten"
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        if seconds < 60 {
            let whole = Int(seconds.rounded())
            return whole == 1 ? "1 Sekunde" : "\(whole) Sekunden"
        }
        return AppFormat.duration(seconds)
    }
}

extension DownloadJob {
    /// "12,4 MB von 40,1 MB" — empty when the size is unknown.
    var sizeText: String {
        guard total > 0 else { return "" }
        return DownloadFormat.bytes(done) + " von " + DownloadFormat.bytes(total)
    }

    /// "40,1 MB" — the size of the finished file, empty when it is unknown.
    var totalSizeText: String {
        guard total > 0 else { return "" }
        return DownloadFormat.bytes(total)
    }

    /// "1,2 MB/s" — empty when the speed is unknown.
    var speedText: String {
        guard bytesPerSecond > 0 else { return "" }
        return DownloadFormat.bytes(Int64(bytesPerSecond)) + "/s"
    }

    /// "noch 9 Sekunden" — empty when the remaining time is unknown.
    var etaText: String {
        guard let remaining, remaining > 0 else { return "" }
        return "noch " + DownloadFormat.duration(remaining)
    }
}

/// The counts of one download run (the TUI "Fertig" screen).
struct DownloadSummary: Sendable, Hashable {
    var done = 0
    var skipped = 0
    var failed = 0
    var cancelled = 0
    /// The message of the first failure (Go `firstFailure`).
    var firstFailure: String?

    /// "Downloads fertig: 2 geladen, 1 übersprungen, 0 fehlgeschlagen."
    var finishedText: String {
        "Downloads fertig: \(done) geladen, \(skipped) übersprungen, \(failed) fehlgeschlagen."
    }

    /// Go's run error: "%d Download(s) fehlgeschlagen (erster Fehler: %s)".
    var failureText: String {
        "\(failed) Download(s) fehlgeschlagen (erster Fehler: \(firstFailure ?? ""))"
    }

    /// The counts of the header of the screen: "3 geladen · 1 übersprungen ·
    /// 0 fehlgeschlagen".
    var countsLine: String {
        "\(done) geladen · \(skipped) übersprungen · \(failed) fehlgeschlagen"
    }
}
