import Foundation

/// Pure model and wire framing for Discord Rich Presence (`SET_ACTIVITY` over
/// Discord's local IPC socket). Kept free of AppKit, SwiftUI and mpv so
/// `OrangeflixLogicTests` can exercise every rule directly.
enum DiscordPresenceLogic {
    /// Fixed Discord Application ID for Orangeflix Rich Presence.
    static let clientID = "1569859656023670946"

    /// Official Orangeflix brand mark URL for fallback `large_image` and `small_image`.
    static let brandImageURL = "https://orangeflix.de/orangeflix.png"
    static let livePageURL = "https://orangeflix.de/live"
    static let clipBaseURL = "https://orangeflix.de/clip/"

    /// Discord Activity Type `3` = Watching ("Schaut …").
    static let watchingType = 3

    /// Minimum seek/drift jump (in seconds) that triggers a fresh timestamp push
    /// while the same item continues playing.
    static let driftThreshold: Double = 3.5

    /// Public web link to an episode or livestream on `orangeflix.de`.
    static func webURL(kind: Kind, identifier: String) -> String {
        switch kind {
        case .live:
            return livePageURL
        case .episode, .replay:
            let clean = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean != "live" else { return livePageURL }
            let escaped = APIHTTP.pathEscape(clean)
            return clipBaseURL + escaped
        }
    }

    enum Kind: String, Sendable, Hashable {
        case episode
        case live
        case replay
    }

    /// Snapshot of the current player state.
    struct Snapshot: Sendable, Hashable {
        var kind: Kind
        var identifier: String
        var title: String
        /// Format and episode number ("Pantoffelkino · Folge 322") or "Live".
        var detail: String
        var chapterTitle: String = ""
        var thumbURL: String = ""
        var position: Double = 0
        var duration: Double = 0
        var isPaused: Bool = false
        var showsLinkButton: Bool = true
    }

    /// Encodable Discord `activity` payload (Unix timestamps in whole seconds).
    struct Activity: Codable, Sendable, Hashable {
        struct Timestamps: Codable, Sendable, Hashable {
            var start: Int64?
            var end: Int64?
        }

        struct Assets: Codable, Sendable, Hashable {
            var largeImage: String?
            var largeText: String?
            var smallImage: String?
            var smallText: String?

            enum CodingKeys: String, CodingKey {
                case largeImage = "large_image"
                case largeText = "large_text"
                case smallImage = "small_image"
                case smallText = "small_text"
            }
        }

        struct Button: Codable, Sendable, Hashable {
            var label: String
            var url: String
        }

        var type: Int = watchingType
        var details: String
        var state: String
        var timestamps: Timestamps?
        var assets: Assets?
        var buttons: [Button]?
    }

    /// Builds a Discord `SET_ACTIVITY` payload from a playback snapshot.
    static func activity(from snapshot: Snapshot, now: Date = Date(), liveStartedAt: Date? = nil) -> Activity {
        let detailsText = clampedField(
            snapshot.title.isEmpty ? fallbackTitle(for: snapshot.kind) : snapshot.title
        )
        let stateText = clampedField(stateLine(for: snapshot))

        let timestamps: Activity.Timestamps?
        if snapshot.isPaused {
            // Omit timestamps while paused so Discord stops advancing the bar.
            timestamps = nil
        } else {
            switch snapshot.kind {
            case .live:
                let origin = liveStartedAt ?? now
                timestamps = Activity.Timestamps(start: Int64(origin.timeIntervalSince1970.rounded()), end: nil)
            case .episode, .replay:
                let pos = max(0, snapshot.position)
                let startEpoch = Int64((now.timeIntervalSince1970 - pos).rounded())
                if snapshot.duration > 1 {
                    let remaining = max(snapshot.duration - pos, 0)
                    let endEpoch = Int64((now.timeIntervalSince1970 + remaining).rounded())
                    timestamps = Activity.Timestamps(start: startEpoch, end: max(endEpoch, startEpoch + 1))
                } else {
                    timestamps = Activity.Timestamps(start: startEpoch, end: nil)
                }
            }
        }

        let largeImage: String = {
            let trimmed = snapshot.thumbURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
                return trimmed
            }
            return brandImageURL
        }()

        let largeLabelSource = snapshot.detail.isEmpty ? detailsText : "\(snapshot.detail) — \(snapshot.title)"
        let smallLabel: String = {
            if snapshot.isPaused { return "Pausiert" }
            if snapshot.kind == .live { return "LIVE · Orangeflix" }
            return "Orangeflix for Mac"
        }()

        let assets = Activity.Assets(
            largeImage: largeImage,
            largeText: clampedField(largeLabelSource),
            smallImage: brandImageURL,
            smallText: clampedField(smallLabel)
        )

        let buttons: [Activity.Button]?
        if snapshot.showsLinkButton {
            let url = webURL(kind: snapshot.kind, identifier: snapshot.identifier)
            let label: String = switch snapshot.kind {
            case .live: "Livestream ansehen"
            case .replay: "Replay auf Orangeflix"
            case .episode: "Folge öffnen"
            }
            buttons = [Activity.Button(label: String(label.prefix(32)), url: url)]
        } else {
            buttons = nil
        }

        return Activity(
            type: watchingType,
            details: detailsText,
            state: stateText,
            timestamps: timestamps,
            assets: assets,
            buttons: buttons
        )
    }

    /// Decides whether a new `SET_ACTIVITY` frame must be sent compared with
    /// the previously sent snapshot and wall-clock moment.
    static func shouldSendUpdate(
        previous: (snapshot: Snapshot, sentAt: Date)?,
        current: Snapshot,
        now: Date = Date()
    ) -> Bool {
        guard let previous else { return true }
        let old = previous.snapshot
        if old.kind != current.kind
            || old.identifier != current.identifier
            || old.title != current.title
            || old.detail != current.detail
            || old.chapterTitle != current.chapterTitle
            || old.thumbURL != current.thumbURL
            || old.isPaused != current.isPaused
            || old.showsLinkButton != current.showsLinkButton
            || abs(old.duration - current.duration) > 1.5 {
            return true
        }
        if current.isPaused || current.kind == .live {
            return false
        }
        // While playing, position advances naturally with wall time; only push
        // when the user scrubbed, skipped or playback stalled significantly.
        let elapsed = now.timeIntervalSince(previous.sentAt)
        let expectedPosition = old.position + elapsed
        return abs(current.position - expectedPosition) >= driftThreshold
    }

    private static func fallbackTitle(for kind: Kind) -> String {
        switch kind {
        case .live: "Orangeflix Livestream"
        case .replay: "Livestream-Replay"
        case .episode: "Orangeflix"
        }
    }

    private static func stateLine(for snapshot: Snapshot) -> String {
        switch snapshot.kind {
        case .live:
            return snapshot.isPaused ? "Livestream · Pausiert" : "Gerade live"
        case .replay:
            let base = snapshot.detail.isEmpty || snapshot.detail == "Replay"
                ? "Livestream-Replay"
                : snapshot.detail
            return snapshot.isPaused ? "Pausiert · \(base)" : base
        case .episode:
            var parts: [String] = []
            if snapshot.isPaused { parts.append("Pausiert") }
            if !snapshot.detail.isEmpty { parts.append(snapshot.detail) }
            if !snapshot.chapterTitle.isEmpty { parts.append(snapshot.chapterTitle) }
            if parts.isEmpty { parts.append("Auf Orangeflix") }
            return parts.joined(separator: " · ")
        }
    }

    /// Discord rejects `details`, `state` and asset hover texts shorter than
    /// 2 characters or longer than 128 characters.
    static func clampedField(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Orangeflix" }
        if trimmed.count == 1 { return trimmed + " " }
        if trimmed.count > 128 {
            return String(trimmed.prefix(127)) + "…"
        }
        return trimmed
    }
}

// MARK: - Binary IPC Framing

/// Discord's local IPC binary packet: `[opcode: UInt32 LE][length: UInt32 LE][UTF-8 JSON]`.
struct DiscordIPCFrame: Sendable, Equatable {
    enum Opcode: UInt32, Sendable {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }

    var opcode: Opcode
    var payload: Data

    func encoded() -> Data {
        var data = Data(capacity: 8 + payload.count)
        var op = opcode.rawValue.littleEndian
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &op) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    static func decodeHeader(_ header: Data) -> (opcode: Opcode, length: Int)? {
        guard header.count == 8 else { return nil }
        let rawOp = header.prefix(4).enumerated().reduce(UInt32(0)) { acc, pair in
            acc | (UInt32(pair.element) << (pair.offset * 8))
        }
        let rawLen = header.dropFirst(4).prefix(4).enumerated().reduce(UInt32(0)) { acc, pair in
            acc | (UInt32(pair.element) << (pair.offset * 8))
        }
        guard let opcode = Opcode(rawValue: rawOp), rawLen <= 1_048_576 else { return nil }
        return (opcode, Int(rawLen))
    }

    /// Encodes a `HANDSHAKE` frame (`opcode 0`).
    static func handshake(clientID: String) throws -> Data {
        let body: [String: Any] = ["v": 1, "client_id": clientID]
        let payload = try JSONSerialization.data(withJSONObject: body)
        return DiscordIPCFrame(opcode: .handshake, payload: payload).encoded()
    }

    /// Encodes a `SET_ACTIVITY` command (`opcode 1`). Passing `nil` clears the activity.
    static func setActivity(_ activity: DiscordPresenceLogic.Activity?, pid: Int32, nonce: String = UUID().uuidString) throws -> Data {
        struct Envelope: Encodable {
            struct Args: Encodable {
                let pid: Int32
                let activity: DiscordPresenceLogic.Activity?

                func encode(to encoder: any Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(pid, forKey: .pid)
                    // Discord requires `"activity": null` explicitly to clear presence.
                    if let activity {
                        try c.encode(activity, forKey: .activity)
                    } else {
                        try c.encodeNil(forKey: .activity)
                    }
                }

                enum CodingKeys: String, CodingKey {
                    case pid, activity
                }
            }

            let cmd = "SET_ACTIVITY"
            let args: Args
            let nonce: String
        }

        let payload = try JSONEncoder().encode(Envelope(args: .init(pid: pid, activity: activity), nonce: nonce))
        return DiscordIPCFrame(opcode: .frame, payload: payload).encoded()
    }
}
