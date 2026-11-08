import Foundation

/// Turns the DASH manifest of a replay into HLS playlists mpv can play.
///
/// The ffmpeg inside the libmpv of the app has no DASH demuxer, and the
/// own DASH path of mpv (EDL `!mp4_dash`) reads the chunked segments of the
/// server as empty. The replay manifest is static and names its segments
/// by number, so the same segments can be listed in HLS playlists with
/// fMP4 (`EXT-X-MAP`); the HLS demuxer of ffmpeg then loads them itself.
enum DashReplayPlaylist {
    /// The three playlists of a replay: the master and one for the picture
    /// and the sound. `audio` is nil when the manifest has no sound track.
    struct Playlists: Equatable {
        var master: String
        var video: String
        var audio: String?
    }

    static let videoName = "video.m3u8"
    static let audioName = "audio.m3u8"

    /// The playlists for the best picture and the best sound of a static
    /// manifest; nil when it is live, has no duration or uses a segment
    /// timeline instead of numbered segments.
    static func playlists(manifest data: Data, url: URL) -> Playlists? {
        let reader = ManifestReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), !reader.isDynamic, let duration = reader.duration, duration > 0 else { return nil }
        let base = reader.baseURL.flatMap { URL(string: $0, relativeTo: url) } ?? url
        let usable = reader.representations.filter { $0.template.isUsable }
        guard let video = usable.filter({ !$0.isAudio }).max(by: { $0.bandwidth < $1.bandwidth }),
              let videoList = media(video, duration: duration, base: base) else { return nil }
        let sound = usable.filter(\.isAudio).max(by: { $0.bandwidth < $1.bandwidth })
        let audioList = sound.flatMap { media($0, duration: duration, base: base) }

        var master = ["#EXTM3U", "#EXT-X-VERSION:7"]
        var codecs = [video.codecs]
        var info = "#EXT-X-STREAM-INF:BANDWIDTH=\(video.bandwidth + (sound?.bandwidth ?? 0))"
        if let sound, audioList != nil {
            master.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"Ton\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioName)\"")
            codecs.append(sound.codecs)
            info += ",AUDIO=\"audio\""
        }
        if video.width > 0, video.height > 0 { info += ",RESOLUTION=\(video.width)x\(video.height)" }
        let named = codecs.filter { !$0.isEmpty }
        if !named.isEmpty { info += ",CODECS=\"\(named.joined(separator: ","))\"" }
        master.append(info)
        master.append(videoName)
        return Playlists(master: master.joined(separator: "\n") + "\n", video: videoList, audio: audioList)
    }

    /// The length of the presentation in seconds (`mediaPresentationDuration`).
    /// The slot of the show in the schedule is often shorter than the replay.
    static func presentationSeconds(manifest data: Data) -> Double? {
        let reader = ManifestReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), let duration = reader.duration, duration > 0 else { return nil }
        return duration
    }

    /// The media playlist of one representation: the init segment and
    /// every numbered segment up to the end of the presentation.
    private static func media(_ rep: Representation, duration: Double, base: URL) -> String? {
        let template = rep.template
        guard let length = template.segmentSeconds, length > 0,
              let initialization = template.initialization,
              let mediaTemplate = template.media,
              let initURL = resolve(expand(initialization, rep: rep, number: nil), base: base) else { return nil }
        let count = Int((duration / length - 1e-6).rounded(.up))
        guard count > 0 else { return nil }
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7",
                     "#EXT-X-TARGETDURATION:\(Int(length.rounded(.up)))",
                     "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MEDIA-SEQUENCE:\(template.startNumber)",
                     "#EXT-X-MAP:URI=\"\(initURL)\""]
        lines.reserveCapacity(lines.count + count * 2 + 1)
        for index in 0..<count {
            let seconds = min(length, duration - Double(index) * length)
            guard let segment = resolve(expand(mediaTemplate, rep: rep, number: template.startNumber + index),
                                        base: base) else { return nil }
            lines.append("#EXTINF:" + String(format: "%.3f", seconds) + ",")
            lines.append(segment)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func resolve(_ path: String, base: URL) -> String? {
        URL(string: path, relativeTo: base)?.absoluteString
    }

    /// Fills the identifiers of a segment template: `$RepresentationID$`,
    /// `$Bandwidth$`, `$Number$` with an optional `%0Nd` width, and `$$`.
    static func expand(_ template: String, id: String, bandwidth: Int, number: Int?) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "$") {
            result += rest[..<open]
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "$") else {
                result += rest[open...]
                return result
            }
            let name = rest[after..<close]
            rest = rest[rest.index(after: close)...]
            if name.isEmpty {
                result += "$"
                continue
            }
            let parts = name.split(separator: "%", maxSplits: 1)
            let key = parts.first.map(String.init) ?? ""
            let value: Int?
            switch key {
            case "RepresentationID":
                result += id
                continue
            case "Bandwidth": value = bandwidth
            case "Number": value = number
            default: value = nil
            }
            guard let value else {
                result += "$" + name + "$"
                continue
            }
            if parts.count == 2, parts[1].hasSuffix("d"),
               let width = Int(parts[1].dropFirst(parts[1].hasPrefix("0") ? 1 : 0).dropLast()) {
                let digits = String(value)
                result += String(repeating: "0", count: max(width - digits.count, 0)) + digits
            } else {
                result += String(value)
            }
        }
        result += rest
        return result
    }

    private static func expand(_ template: String, rep: Representation, number: Int?) -> String {
        expand(template, id: rep.id, bandwidth: rep.bandwidth, number: number)
    }

    /// Seconds of an ISO 8601 duration like `PT2H3M14.400S` or `P1DT2H`.
    static func seconds(isoDuration value: String) -> Double? {
        var text = Substring(value.trimmingCharacters(in: .whitespaces))
        guard text.first == "P" else { return nil }
        text = text.dropFirst()
        var total = 0.0
        var number = ""
        var inTime = false
        for character in text {
            switch character {
            case "T": inTime = true
            case "0"..."9", ".": number.append(character)
            default:
                guard let amount = Double(number) else { return nil }
                number = ""
                switch (character, inTime) {
                case ("D", false): total += amount * 86_400
                case ("H", true): total += amount * 3_600
                case ("M", true): total += amount * 60
                case ("S", true): total += amount
                default: return nil
                }
            }
        }
        return number.isEmpty ? total : nil
    }

    // MARK: Reading the manifest

    fileprivate struct Template {
        var timescale = 1
        var duration: Int?
        var initialization: String?
        var media: String?
        var startNumber = 1
        var hasTimeline = false

        var segmentSeconds: Double? { duration.map { Double($0) / Double(max(timescale, 1)) } }
        var isUsable: Bool { !hasTimeline && duration != nil && initialization != nil && media != nil }

        /// The template of a representation fills its gaps from the one of
        /// its adaptation set.
        func merged(over parent: Template) -> Template {
            var result = self
            if duration == nil { result.duration = parent.duration; result.timescale = parent.timescale }
            if initialization == nil { result.initialization = parent.initialization }
            if media == nil { result.media = parent.media }
            return result
        }
    }

    fileprivate struct Representation {
        var id = ""
        var bandwidth = 0
        var codecs = ""
        var width = 0
        var height = 0
        var isAudio = false
        var template = Template()
    }

    private final class ManifestReader: NSObject, XMLParserDelegate {
        var isDynamic = false
        var duration: Double?
        var baseURL: String?
        var representations: [Representation] = []

        private var setTemplate = Template()
        private var setIsAudio = false
        private var setCodecs = ""
        private var current: Representation?
        private var ownTemplate: Template?
        private var path: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "MPD":
                isDynamic = attributes["type"] == "dynamic"
                duration = attributes["mediaPresentationDuration"].flatMap(DashReplayPlaylist.seconds(isoDuration:))
            case "AdaptationSet":
                setTemplate = Template()
                setCodecs = attributes["codecs"] ?? ""
                let kind = attributes["contentType"] ?? attributes["mimeType"] ?? ""
                setIsAudio = kind.hasPrefix("audio")
            case "Representation":
                let mime = attributes["mimeType"] ?? ""
                current = Representation(
                    id: attributes["id"] ?? "",
                    bandwidth: Int(attributes["bandwidth"] ?? "") ?? 0,
                    codecs: attributes["codecs"] ?? setCodecs,
                    width: Int(attributes["width"] ?? "") ?? 0,
                    height: Int(attributes["height"] ?? "") ?? 0,
                    isAudio: mime.isEmpty ? setIsAudio : mime.hasPrefix("audio"))
                ownTemplate = nil
            case "SegmentTemplate":
                var template = Template()
                template.timescale = Int(attributes["timescale"] ?? "") ?? 1
                template.duration = attributes["duration"].flatMap { Int($0) }
                template.initialization = attributes["initialization"]
                template.media = attributes["media"]
                template.startNumber = Int(attributes["startNumber"] ?? "") ?? 1
                if current != nil { ownTemplate = template } else { setTemplate = template }
            case "SegmentTimeline":
                if current != nil { ownTemplate?.hasTimeline = true } else { setTemplate.hasTimeline = true }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            defer { path.removeLast() }
            switch name {
            case "BaseURL":
                // Only the base of the whole manifest; deeper ones are rare
                // for replays and would need their own resolution.
                if path.count == 2, baseURL == nil {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { baseURL = value }
                }
            case "Representation":
                guard var rep = current else { return }
                rep.template = ownTemplate.map { $0.merged(over: setTemplate) } ?? setTemplate
                rep.template.hasTimeline = rep.template.hasTimeline || setTemplate.hasTimeline
                representations.append(rep)
                current = nil
            default:
                break
            }
        }
    }
}
