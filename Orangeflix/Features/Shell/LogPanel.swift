import SwiftUI

/// The Protokoll: "HH:MM:SS text" lines, errors in red, newest at the
/// bottom and scrolled into view.
struct LogPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                SectionLabel(text: "Protokoll")
                if !app.log.isEmpty {
                    Text("\(app.log.count)")
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Button {
                    AppFormat.copy(app.log.map(Self.line).joined(separator: "\n"))
                    app.show("Kopiert.")
                } label: {
                    Label("Alles kopieren", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .help("Alles kopieren")
                .disabled(app.log.isEmpty)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)

            Hairline()

            if app.log.isEmpty {
                Text("Noch nichts passiert.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Space.xxs) {
                            ForEach(app.log) { entry in
                                BrandLogLine(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: app.log.last?.id) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) { scrollToEnd(proxy) }
                    }
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = app.log.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    /// "HH:MM:SS text"
    static func line(_ entry: LogLine) -> String {
        AppFormat.clock(entry.time) + " " + entry.text
    }
}
