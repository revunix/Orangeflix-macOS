import Foundation

/// What the Live screen plays: the running stream or its replay (Go
/// `PlayLive` with the modes "live" and "replay").
enum LivePlaybackMode: String, Hashable, Sendable {
    /// The running live stream.
    case live
    /// The replay of the last show.
    case replay
}

/// One message of the chat of a replay, placed on the timeline of the video.
struct ReplayChatLine: Identifiable, Hashable, Sendable {
    /// The position in the video in seconds.
    var at: Double
    /// The name of the sender.
    var from: String
    /// The text of the message.
    var text: String
    /// The moment the message was written (Unix seconds).
    var unix: Int64

    var id: String { "\(unix)-\(from)-\(text)" }
}

/// Starts the playback of the live stream and its replay; implemented by the
/// Playback feature (`PlaybackCenter`). The Live screen reaches it through
/// `AppModel.playback`.
@MainActor
protocol LivePlaybackStarting: AnyObject {
    /// Plays the running stream or its replay; inline in the Live screen or
    /// in the player window.
    func playLive(_ info: LivestreamInfo, mode: LivePlaybackMode, inline: Bool) async
    /// Takes over the messages of the chat of a replay, so that they can be
    /// shown in the chat of the Live screen while the video runs.
    func setReplayChatHandler(_ handler: (@MainActor (ReplayChatLine) -> Void)?)
}
