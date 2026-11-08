import Foundation

/// The files that are stored next to a video (port of the file parts of
/// internal/app/sidecar.go and the subtitle naming of pipeline.go):
/// "<video>.de.vtt" (".1.de.vtt", ...), "<video>.jpg" and "<video>.json".
enum DownloadSidecars {
    /// The schema tag of the JSON sidecar.
    static let metadataSchema = "orangeflix-dl/episode/1"

    /// The video path without its extension (Go `filepath.Ext` semantics:
    /// the suffix from the last dot of the last path element).
    static func basePath(of video: URL) -> String {
        let path = video.path(percentEncoded: false)
        var index = path.endIndex
        while index > path.startIndex {
            let previous = path.index(before: index)
            let character = path[previous]
            if character == "/" { break }
            if character == "." { return String(path[..<previous]) }
            index = previous
        }
        return path
    }

    /// The file of the subtitle with the index.
    static func subtitleFile(for video: URL, index: Int) -> URL {
        URL(fileURLWithPath: basePath(of: video) + (index > 0 ? ".\(index)" : "") + ".de.vtt")
    }

    /// Whether the first subtitle lies next to the video.
    static func subtitlePresent(for video: URL) -> Bool {
        FileManager.default.fileExists(atPath: subtitleFile(for: video, index: 0).path(percentEncoded: false))
    }

    /// The thumbnail file of a video.
    static func thumbnailFile(for video: URL) -> URL {
        URL(fileURLWithPath: basePath(of: video) + ".jpg")
    }

    /// The metadata file of a video.
    static func metadataFile(for video: URL) -> URL {
        URL(fileURLWithPath: basePath(of: video) + ".json")
    }

    /// The JSON sidecar, byte-identical to Go's `json.MarshalIndent(meta,
    /// "", "  ")` plus a trailing newline: fixed key order, `omitempty`
    /// fields left out, Go string escaping (HTML characters, U+2028/2029).
    /// `subtitle` is the full path of the first subtitle when it is present,
    /// like the Go tool writes it.
    static func metadataJSON(_ meta: EpisodeMetadata, subtitlePath: String?) -> Data {
        var fields: [(String, String)] = [
            ("schema", quote(metadataSchema)),
            ("identifier", quote(meta.identifier)),
            ("pid", String(meta.pid)),
            ("episode", String(meta.number)),
            ("title", quote(meta.title)),
            ("format", quote(meta.formatName)),
        ]
        if !meta.description.isEmpty { fields.append(("description", quote(meta.description))) }
        if let published = meta.published { fields.append(("date", quote(utcDay(published)))) }
        if !meta.duration.isEmpty { fields.append(("duration", quote(meta.duration))) }
        if meta.durationSeconds != 0 { fields.append(("durationSeconds", String(meta.durationSeconds))) }
        if !meta.thumbnailURL.isEmpty { fields.append(("thumbURL", quote(meta.thumbnailURL))) }
        if let subtitlePath, !subtitlePath.isEmpty { fields.append(("subtitle", quote(subtitlePath))) }
        if !meta.participants.isEmpty {
            let items = meta.participants.map { "    " + quote($0) }.joined(separator: ",\n")
            fields.append(("participants", "[\n" + items + "\n  ]"))
        }
        let body = fields.map { "  \(quote($0.0)): \($0.1)" }.joined(separator: ",\n")
        return Data(("{\n" + body + "\n}\n").utf8)
    }

    /// Writes the metadata of the episode next to the video (atomically,
    /// replacing an older file). The subtitle name is filled in when the
    /// first subtitle lies there.
    @discardableResult
    static func writeMetadata(_ meta: EpisodeMetadata, video: URL) throws(DownloadError) -> URL {
        let subtitle = subtitlePresent(for: video) ? subtitleFile(for: video, index: 0).path(percentEncoded: false) : nil
        let target = metadataFile(for: video)
        do {
            try metadataJSON(meta, subtitlePath: subtitle).write(to: target, options: .atomic)
        } catch {
            throw .fileSystem(error.localizedDescription)
        }
        return target
    }

    /// "yyyy-MM-dd" of the date in UTC (Go `Format("2006-01-02")` of the
    /// UTC time the API delivers).
    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// A JSON string with the escaping of Go's encoding/json.
    static func quote(_ text: String) -> String {
        let hex = Array("0123456789abcdef")
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "<", ">", "&", "\u{2028}", "\u{2029}":
                let value = Int(scalar.value)
                out += "\\u" + String([hex[(value >> 12) & 0xF], hex[(value >> 8) & 0xF], hex[(value >> 4) & 0xF], hex[value & 0xF]])
            default:
                if scalar.value < 0x20 {
                    let value = Int(scalar.value)
                    out += "\\u00" + String([hex[value >> 4], hex[value & 0xF]])
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
