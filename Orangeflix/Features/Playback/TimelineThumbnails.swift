import AppKit
import Foundation
import Observation

/// One picture of the timeline: the stretch of the video it belongs to and
/// where it stands in its sprite sheet.
struct TimelineCue: Hashable, Sendable {
    var start: Double
    var end: Double
    /// The sprite sheet with the picture.
    var sheet: URL
    /// The picture inside the sheet, in pixels.
    var frame: CGRect
}

/// The WebVTT file of a clip (`vttThumbnails`): cues that point at pictures
/// in sprite sheets, as `sheet.jpg#xywh=x,y,w,h`.
enum TimelineThumbnails {
    /// The cues of a WebVTT file, resolved against its own address.
    static func cues(from text: String, base: URL) -> [TimelineCue] {
        var cues: [TimelineCue] = []
        for block in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let arrow = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[arrow].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard times.count == 2, let start = seconds(times[0]), let end = seconds(times[1]),
                  let payload = lines.dropFirst(arrow + 1).first(where: { !$0.isEmpty }) else { continue }
            let parts = payload.split(separator: "#", maxSplits: 1).map(String.init)
            let sheet = parts.first ?? ""
            guard !sheet.isEmpty else { continue }
            var frame = CGRect(x: 0, y: 0, width: 0, height: 0)
            if parts.count == 2, parts[1].hasPrefix("xywh=") {
                let values = parts[1].dropFirst(5).split(separator: ",").compactMap { Double($0) }
                if values.count == 4 {
                    frame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                }
            }
            guard frame.width > 0, frame.height > 0,
                  let url = URL(string: sheet, relativeTo: base) else { continue }
            cues.append(TimelineCue(start: start, end: end, sheet: url, frame: frame))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:12:34.500" or "12:34.500" in seconds.
    private static func seconds(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard !parts.isEmpty else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// The pictures of the timeline of the running file. The store reads the
/// cue file once, keeps the sheets it has loaded and hands out the picture
/// that belongs to a moment. A sheet that is still loading simply has no
/// picture yet; the view asks again when it arrives.
@MainActor @Observable
final class TimelineThumbnailStore {
    /// The cues of the cue file, sorted by time.
    private(set) var cues: [TimelineCue] = []
    /// The loaded sheets, by address.
    private var sheets: [URL: NSImage] = [:]
    /// The pictures taken out of a sheet, by sheet and frame.
    private var frames: [FrameKey: NSImage] = [:]
    /// What is loading right now, so nothing is asked for twice.
    private var loading: Set<AnyHashable> = []
    /// The track the store belongs to; a new file replaces it.
    private var track: URL?
    /// Wakes the view once a sheet arrived.
    private(set) var generation = 0

    private struct FrameKey: Hashable {
        var sheet: URL
        var frame: CGRect
    }

    /// Points the store at the cue file of the running entry.
    func load(track url: URL?) {
        guard track != url else { return }
        track = url
        cues = []
        frames = [:]
        generation += 1
        guard let url else { return }
        Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let text = String(data: data, encoding: .utf8) else { return }
            let cues = TimelineThumbnails.cues(from: text, base: url)
            guard let self, !Task.isCancelled, self.track == url else { return }
            self.cues = cues
            self.generation += 1
        }
    }

    /// The picture of the moment; nil while it is not loaded.
    func image(at seconds: Double) -> NSImage? {
        guard let cue = cues.last(where: { seconds >= $0.start }) else { return nil }
        let key = FrameKey(sheet: cue.sheet, frame: cue.frame)
        if let image = frames[key] { return image }
        guard let sheet = sheets[cue.sheet] else {
            loadSheet(cue.sheet)
            return nil
        }
        guard let picture = crop(sheet: sheet, frame: cue.frame) else { return nil }
        frames[key] = picture
        return picture
    }

    private func loadSheet(_ url: URL) {
        guard !loading.contains(url) else { return }
        loading.insert(url)
        Task { [weak self] in
            defer { Task { @MainActor in self?.loading.remove(url) } }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = NSImage(data: data) else { return }
            guard let self else { return }
            self.sheets[url] = image
            self.generation += 1
        }
    }

    /// Cuts one picture out of a sheet.
    private func crop(sheet: NSImage, frame: CGRect) -> NSImage? {
        guard let source = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cut = source.cropping(to: frame) else { return nil }
        return NSImage(cgImage: cut, size: NSSize(width: frame.width, height: frame.height))
    }
}
