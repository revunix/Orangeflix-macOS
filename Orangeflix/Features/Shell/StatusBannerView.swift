import SwiftUI

/// Shows `app.banner` at the top of the window (the TUI's status line).
/// Messages hide after a few seconds; errors stay until they are closed.
struct StatusBannerView: View {
    @Environment(AppModel.self) private var app

    /// How long a message stays before it hides itself.
    private static let messageLifetime = Duration.seconds(5)

    var body: some View {
        Group {
            if let banner = app.banner {
                HStack(spacing: Space.s) {
                    Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(banner.isError ? Palette.danger : Palette.accent)
                        .font(AppFont.bodySmall)
                    Text(banner.text)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(banner.isError ? Palette.danger : Palette.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: Space.s)
                    Button {
                        dismiss(banner)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .help("Schließen")
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .background(banner.isError ? Palette.dangerSoft : Palette.accentSoft)
                .overlay(alignment: .bottom) {
                    Hairline(color: banner.isError ? Palette.danger.opacity(0.35) : Palette.accent.opacity(0.25))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: banner.id) {
                    // Errors stay until they are closed.
                    guard !banner.isError else { return }
                    do {
                        try await Task.sleep(for: Self.messageLifetime)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    dismiss(banner)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.banner)
    }

    /// Removes the message when it is still the current one.
    private func dismiss(_ banner: Banner) {
        if app.banner?.id == banner.id { app.banner = nil }
    }
}
