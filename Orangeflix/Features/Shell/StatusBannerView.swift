import SwiftUI

/// Shows `app.banner` as a small plate that floats at the top of a window
/// (the TUI's status line). Every window of the app carries one; only the
/// window in front shows the message, so it never stands twice on screen.
/// The message hides itself (`AppModel.flash`) or is closed here.
struct StatusBannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The widest the plate gets; a longer text breaks into lines.
    private static let maxWidth: CGFloat = 520

    var body: some View {
        ZStack(alignment: .top) {
            if appearsActive, let banner = app.banner {
                plate(banner)
                    .id(banner.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
        .animation(.snappy(duration: 0.25), value: app.banner)
        .animation(.snappy(duration: 0.25), value: appearsActive)
        .onChange(of: app.banner) { _, banner in
            // VoiceOver reads the message; it does not see it appear.
            guard appearsActive, let banner else { return }
            AccessibilityNotification.Announcement(banner.text).post()
        }
    }

    private func plate(_ banner: Banner) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(banner.isError ? Palette.danger : Palette.accent)
                .font(AppFont.body)
                .accessibilityHidden(true)
            Text(banner.text)
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button {
                app.dismissBanner(banner)
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Schließen")
            .accessibilityLabel("Meldung schließen")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .glassPlate(in: shape, quietAppear: true)
        .overlay {
            if banner.isError {
                shape.strokeBorder(Palette.danger.opacity(0.45), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        // The plate is as wide as its text; the frame only caps it and
        // keeps it in the middle.
        .frame(maxWidth: Self.maxWidth)
    }
}
