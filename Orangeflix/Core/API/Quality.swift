import Foundation

/// The download qualities the user can ask for.
enum ClipQuality: String, Sendable, Hashable, Codable, CaseIterable {
    case best, hd, sd, mobile, audio

    /// Reports whether the name is an accepted quality.
    static func isValid(_ name: String) -> Bool {
        ClipQuality(rawValue: name) != nil
    }
}

/// The file picked for a quality.
struct FileSelection: Sendable, Hashable {
    let file: ClipFile
    /// Whether a file of exactly the requested quality exists. `false` means
    /// the selection fell back to the closest file and the caller should
    /// report the deviation.
    let exact: Bool
}

extension ClipFile {
    /// Whether the file is an audio track.
    var isAudio: Bool {
        kind == "music" || desc.lowercased().hasPrefix("audio")
    }

    /// The comparable number of a file: the vertical resolution.
    var rank: Int {
        let height = height
        return height > 0 ? height : Self.resolutionRank(desc)
    }

    /// Maps a quality description to a comparable number: its first number,
    /// so "HD 720p" ranks as 720. Audio descriptions rank 0.
    static func resolutionRank(_ desc: String) -> Int {
        if desc.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("audio") {
            return 0
        }
        var digits = ""
        for character in desc.unicodeScalars {
            if character.value >= 48 && character.value <= 57 {
                digits.unicodeScalars.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits) ?? 0
    }

    /// The resolution used in the file name, for example "1080p". An audio
    /// track is marked as "Audio".
    var resolutionLabel: String {
        if isAudio { return "Audio" }
        var height = height
        if height == 0 { height = Self.resolutionRank(desc) }
        switch height {
        case 2160...: return "2160p"
        case 1440...: return "1440p"
        case 1080...: return "1080p"
        case 720...: return "720p"
        case 576...: return "576p"
        case 480...: return "480p"
        case 1...: return "\(height)p"
        default: return "Unknown"
        }
    }

    /// The file extension of the download, including the dot.
    var fileExtension: String {
        let ext = Self.pathExtension(url)
        if isAudio {
            return ext == ".mp3" ? ".mp3" : ".m4a"
        }
        return [".mp4", ".mkv", ".webm"].contains(ext) ? ext : ".mp4"
    }

    /// The lower-cased extension of the last path element like Go's
    /// `path.Ext`: the part from the final dot after the final slash.
    private static func pathExtension(_ path: String) -> String {
        var index = path.endIndex
        while index > path.startIndex {
            let previous = path.index(before: index)
            let character = path[previous]
            if character == "/" { break }
            if character == "." { return path[previous...].lowercased() }
            index = previous
        }
        return ""
    }
}

extension Array where Element == ClipFile {
    /// Picks the file for the quality. A missing quality falls back to the
    /// closest file and reports `exact == false`.
    func select(_ quality: ClipQuality) throws -> FileSelection {
        try select(quality: quality.rawValue)
    }

    /// Picks the file for a quality name. An empty name means "best", an
    /// unknown name falls back to the best video.
    func select(quality: String) throws -> FileSelection {
        if isEmpty { throw APIError.noFiles("die Episode") }
        var wanted = quality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if wanted.isEmpty { wanted = ClipQuality.best.rawValue }

        if wanted == ClipQuality.best.rawValue {
            guard let best = bestVideo() else { throw APIError.noVideoFile }
            return FileSelection(file: best, exact: true)
        }

        switch ClipQuality(rawValue: wanted) {
        case .hd:
            if let file = first(desc: "HD 1080p") { return FileSelection(file: file, exact: true) }
        case .sd:
            if let file = first(desc: "SD 432p") { return FileSelection(file: file, exact: true) }
            // The format may offer a different low resolution.
            if let file = lowestVideo() { return FileSelection(file: file, exact: false) }
        case .mobile:
            if let file = first(desc: "HD 720p") { return FileSelection(file: file, exact: true) }
            if let file = lowestVideo() { return FileSelection(file: file, exact: false) }
        case .audio:
            if let file = first(desc: "Audio m4a") { return FileSelection(file: file, exact: true) }
            if let file = first(desc: "Audio mp3") { return FileSelection(file: file, exact: true) }
        case .best, nil:
            break
        }

        guard let fallback = closest(to: wanted) else { throw APIError.noFileForQuality(wanted) }
        return FileSelection(file: fallback, exact: false)
    }

    private func first(desc: String) -> ClipFile? {
        first { $0.desc == desc && !$0.url.isEmpty }
    }

    /// The video file with the highest resolution; the first one wins a tie.
    func bestVideo() -> ClipFile? {
        var best: ClipFile?
        for file in self where !file.url.isEmpty && !file.isAudio {
            if best == nil || file.rank > best!.rank { best = file }
        }
        return best
    }

    /// The video file with the lowest known resolution.
    func lowestVideo() -> ClipFile? {
        var lowest: ClipFile?
        for file in self where !file.url.isEmpty && !file.isAudio {
            let rank = file.rank
            if rank == 0 { continue }
            if lowest == nil || rank < lowest!.rank { lowest = file }
        }
        return lowest
    }

    private func closest(to quality: String) -> ClipFile? {
        if quality == ClipQuality.audio.rawValue {
            return first { $0.isAudio && !$0.url.isEmpty }
        }
        return bestVideo()
    }
}
