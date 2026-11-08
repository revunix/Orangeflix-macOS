import SwiftUI

/// The running playback for the toolbar of the main window. The TUI shows
/// "▶ <label> mm:ss / mm:ss" in its header.
struct NowPlayingView: View {
    @Environment(PlaybackCenter.self) private var playback
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if playback.isPlaying {
            Button {
                openPlayer()
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: playback.isPaused ? "circle.fill" : "pause.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.accent)

                    Text(playback.nowPlayingTitle)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    Text("\(AppFormat.position(playback.position)) / \(AppFormat.position(playback.duration))")
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .help("Wiedergabe öffnen")
        }
    }

    /// Brings the window of the player to the front; it opens the window
    /// when it is not there yet.
    private func openPlayer() {
        if PlayerWindows.front() { return }
        openWindow(id: "player")
    }
}
