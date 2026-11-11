import SwiftUI

/// Live diagnostic Protokoll drawer toggled via ⌘L or the toolbar menu.
struct LogPanel: View {
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @State private var errorsOnly = false

    private var filteredEntries: [LogLine] {
        errorsOnly ? app.log.filter(\.isError) : app.log
    }

    private var errorCount: Int {
        app.log.reduce(into: 0) { if $1.isError { $0 += 1 } }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                SectionLabel(text: "Protokoll", symbol: "terminal")

                if !app.log.isEmpty {
                    BrandPill(
                        text: "\(app.log.count)",
                        color: Palette.textSecondary,
                        background: Palette.surfaceMuted
                    )
                }

                if errorCount > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.16)) { errorsOnly.toggle() }
                    } label: {
                        BrandPill(
                            text: errorsOnly ? "Nur Fehler (\(errorCount))" : "\(errorCount) Fehler",
                            color: Palette.danger,
                            background: Palette.dangerSoft
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Zwischen allen Einträgen und nur Fehlern umschalten")
                }

                Spacer(minLength: Space.s)

                Button {
                    AppFormat.copy(filteredEntries.map(Self.line).joined(separator: "\n"))
                    app.show("Protokoll kopiert")
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                        .font(AppFont.captionMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textSecondary)
                .disabled(filteredEntries.isEmpty)
                .help("Sichtbare Protokollzeilen kopieren")

                Button {
                    app.clearLog()
                    errorsOnly = false
                } label: {
                    Label("Leeren", systemImage: "trash")
                        .font(AppFont.captionMedium)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textSecondary)
                .disabled(app.log.isEmpty)
                .help("Protokoll leeren")

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Palette.surfaceMuted, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Protokoll schließen (⌘L)")
                    .accessibilityLabel("Protokoll schließen")
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)

            Hairline()

            if filteredEntries.isEmpty {
                Text(errorsOnly ? "Keine Fehler im Protokoll." : "Noch keine Einträge im Protokoll.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(filteredEntries) { entry in
                                BrandLogLine(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: filteredEntries.last?.id) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) { scrollToEnd(proxy) }
                    }
                }
            }
        }
        .frame(height: 196)
        .background(Palette.surfaceRaised, in: shape)
        .overlay {
            shape.strokeBorder(Palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.m)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = filteredEntries.last?.id {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    static func line(_ entry: LogLine) -> String {
        AppFormat.clock(entry.time) + " " + entry.text
    }
}
