import SwiftUI

/// The hint in the toolbar that names the running or the next livestream
/// (Go `nextLiveHint`, internal/tui/helpers.go:279-380):
/// "● LIVE · Titel" while a show runs, otherwise
/// "heute|morgen|Wd HH:MM · in X Std. Y Min. · Titel".
/// A click opens the Live section.
struct LiveHintView: View {
    @Environment(AppModel.self) private var app

    /// The live state of the API (Go `App.Live`).
    @State private var live: LivestreamInfo?
    /// The next calendar entries (Go `loadCalendarQuiet`, twenty entries).
    @State private var entries: [CalendarEntry] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let text = hint(at: context.date) {
                Button {
                    app.selection = .live
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "calendar.badge.clock")
                            .font(AppFont.caption)
                            .foregroundStyle(isLive ? Palette.accent : Palette.textTertiary)
                        Text(text)
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Live öffnen")
            }
        }
        .task(id: app.accountGeneration) { await reload() }
        .task { await refreshLoop() }
    }

    /// The hint text at a given moment; nil when no livestream is known.
    func hint(at date: Date) -> String? {
        let text = ShellLiveHint.hint(entries: entries, live: live, now: date)
        return text.isEmpty ? nil : text
    }

    /// Whether a show runs right now.
    private var isLive: Bool {
        live?.isLive == true
    }

    /// Reads the live state and the next calendar entries.
    private func reload() async {
        do {
            try await app.ensureSession()
        } catch {
            // Without a session the API answers with 401; the account model
            // shows the login.
            return
        }
        do {
            live = try await app.services.api.liveActive()
        } catch {
            live = nil
        }
        do {
            entries = try await app.services.api.calendar(limit: 20)
        } catch {
            // The old entries stay; the next round tries again.
        }
    }

    /// Reads the live state again every five minutes.
    private func refreshLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(300))
            } catch {
                return
            }
            await reload()
        }
    }
}
