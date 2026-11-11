import SwiftUI

/// Compact toolbar item shown in the main window's navbar while native
/// Picture-in-Picture (`PIPViewController`) is active. Clicking it navigates
/// straight back to the episode or livestream page and docks the video back in.
struct NowPlayingView: View {
    let ink: Color

    @Environment(PlaybackCenter.self) private var playback

    var body: some View {
        if playback.isInPiP, let entry = playback.current {
            Button {
                playback.returnFromPiP()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)

                    Text(shortLabel(for: entry))
                        .font(AppFont.captionMedium)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .frame(maxWidth: 132, alignment: .leading)

                    if entry.kind != .live, playback.duration > 0 {
                        Text(AppFormat.position(playback.position))
                            .font(AppFont.digits)
                            .foregroundStyle(ink.opacity(0.72))
                    }
                }
                .padding(.horizontal, 6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Bild-in-Bild beenden und zurück zur Wiedergabe wechseln")
            .accessibilityLabel("Zurück zur laufenden Wiedergabe")
        }
    }

    private func shortLabel(for entry: PlaybackEntry) -> String {
        switch entry.kind {
        case .live:
            return "Zur Live-Sendung"
        case .replay:
            return "Zum Replay"
        case .episode:
            return playback.nowPlayingTitle.isEmpty ? "Zur Folge" : playback.nowPlayingTitle
        }
    }
}
