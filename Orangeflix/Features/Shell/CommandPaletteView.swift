import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleCommandPalette = Notification.Name("com.revunix.orangeflix.toggleCommandPalette")
}

/// Spotlight-style ⌘K quick switcher for formats, sections and quick actions.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    var onToggleLogPanel: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var browse
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private enum ItemKind: Hashable {
        case searchQuery(String)
        case format(Format)
        case section(SidebarItem, subtitle: String, symbol: String, shortcut: String?)
        case action(id: String, title: String, subtitle: String, symbol: String, shortcut: String?)
    }

    private struct PaletteItem: Identifiable, Hashable {
        let id: String
        let group: String
        let kind: ItemKind
    }

    private var items: [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = SettingsSearch.fold(trimmed)
        let words = folded.split(whereSeparator: \.isWhitespace).map(String.init)

        func matches(_ text: String) -> Bool {
            guard !words.isEmpty else { return true }
            let target = SettingsSearch.fold(text)
            return words.allSatisfy { target.contains($0) }
        }

        var result: [PaletteItem] = []

        if trimmed.count >= 2 {
            result.append(
                PaletteItem(
                    id: "search.\(trimmed)",
                    group: "Volltextsuche",
                    kind: .searchQuery(trimmed)
                )
            )
        }

        let visibleFormats = browse.formats
            .filter { !app.settings.hiddenMagazines.contains($0.pid) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let matchingFormats = visibleFormats.filter {
            matches("\($0.title) \($0.slug) \($0.handle)")
        }

        for format in matchingFormats.prefix(words.isEmpty ? 6 : 12) {
            result.append(
                PaletteItem(
                    id: "format.\(format.pid)",
                    group: "Formate",
                    kind: .format(format)
                )
            )
        }

        let sections: [(SidebarItem, String, String, String?)] = [
            (.formats, "Alle sichtbaren Serien & Regale", "square.grid.2x2", "⌘1"),
            (.recents, "Angefangene & zuletzt geschaute Folgen", "clock.arrow.circlepath", "⌘2"),
            (.bookmarks, "Deine gespeicherten Folgen", "star", "⌘3"),
            (.calendar, "Kommende Termine & Livestreams", "calendar", "⌘4"),
            (.live, "Livestream, Countdown & Chat", "dot.radiowaves.left.and.right", "⌘5"),
            (.downloads, "Aktive und geladene Dateien", "arrow.down.circle", "⌘6"),
            (.announcements, "Neuigkeiten der Plattform", "megaphone", "⌘7"),
            (.search, "Suche in Titeln, Kapiteln & Gesprochenem", "magnifyingglass", "⌘F"),
        ]

        for (section, subtitle, symbol, shortcut) in sections where matches("\(section.title) \(subtitle)") {
            result.append(
                PaletteItem(
                    id: "section.\(section.rawValue)",
                    group: "Bereiche",
                    kind: .section(section, subtitle: subtitle, symbol: symbol, shortcut: shortcut)
                )
            )
        }

        let actions: [(String, String, String, String, String?)] = [
            ("settings", "Einstellungen öffnen", "Darstellung, Konto, Wiedergabe & Downloads", "gearshape", "⌘,"),
            ("log", "Protokoll ein-/ausblenden", "Live-Diagnose am unteren Fensterrand", "terminal", "⌘L"),
            ("theme.auto", "Erscheinungsbild: Automatisch", "Folgt der Systemeinstellung von macOS", "circle.lefthalf.filled", nil),
            ("theme.light", "Erscheinungsbild: Hell", "Wechselt sofort in den hellen Modus", "sun.max", nil),
            ("theme.dark", "Erscheinungsbild: Dunkel", "Wechselt sofort in den dunklen Modus", "moon.stars", nil),
        ]

        for (id, title, subtitle, symbol, shortcut) in actions where matches("\(title) \(subtitle)") {
            result.append(
                PaletteItem(
                    id: "action.\(id)",
                    group: "Aktionen",
                    kind: .action(id: id, title: title, subtitle: subtitle, symbol: symbol, shortcut: shortcut)
                )
            )
        }

        return result
    }

    var body: some View {
        let currentItems = items
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.accent)

                    TextField(
                        "Schnellwechsel",
                        text: $query,
                        prompt: Text("Format öffnen, Bereich wechseln oder Befehl ausführen …")
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit {
                        if currentItems.indices.contains(selectedIndex) {
                            run(currentItems[selectedIndex])
                        }
                    }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("ESC")
                        .font(AppFont.micro.monospaced())
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .padding(.horizontal, Space.l)
                .frame(height: 50)

                Hairline()

                if currentItems.isEmpty {
                    Text("Keine passenden Formate oder Befehle gefunden.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(Space.xl)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                                    if index == 0 || currentItems[index - 1].group != item.group {
                                        Text(item.group.uppercased())
                                            .font(AppFont.micro)
                                            .tracking(0.7)
                                            .foregroundStyle(Palette.textTertiary)
                                            .padding(.horizontal, Space.m)
                                            .padding(.top, index == 0 ? 6 : 10)
                                            .padding(.bottom, 2)
                                    }
                                    row(item, isSelected: index == selectedIndex)
                                        .id(item.id)
                                        .onTapGesture { run(item) }
                                }
                            }
                            .padding(Space.s)
                        }
                        .frame(maxHeight: 370)
                        .onChange(of: selectedIndex) { _, next in
                            if currentItems.indices.contains(next) {
                                proxy.scrollTo(currentItems[next].id)
                            }
                        }
                    }
                }
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .fill(Palette.surfaceRaised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.38), radius: 28, y: 12)
            .padding(.top, 76)
        }
        .onAppear {
            selectedIndex = 0
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            guard !currentItems.isEmpty else { return .ignored }
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !currentItems.isEmpty else { return .ignored }
            selectedIndex = min(currentItems.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    @ViewBuilder
    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: Space.m) {
            switch item.kind {
            case .searchQuery(let text):
                iconCircle("magnifyingglass", accent: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("In Folgen & Gesprochenem nach „\(text)“ suchen")
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text("Öffnet die Volltextsuche mit Video-Vorschau")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                shortcutBadge("↩")

            case .format(let format):
                FormatCover(format: format)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(format.title)
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if format.newEpisode {
                            BrandPill(text: "Neu", color: .white, background: Palette.accent)
                        }
                    }
                    Text(format.clipCount > 0 ? "\(format.clipCount) Folgen" : "Format öffnen")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)

            case .section(let section, let subtitle, let symbol, let shortcut):
                iconCircle(symbol, accent: app.selection == section)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let shortcut { shortcutBadge(shortcut) }

            case .action(_, let title, let subtitle, let symbol, let shortcut):
                iconCircle(symbol, accent: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let shortcut { shortcutBadge(shortcut) }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .fill(isSelected ? Palette.accentSoft : .clear)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.38), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private func iconCircle(_ symbol: String, accent: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent ? Palette.accentText : Palette.textSecondary)
            .frame(width: 30, height: 30)
            .background(accent ? Palette.accentSoft : Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption.monospaced())
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func run(_ item: PaletteItem) {
        close()
        switch item.kind {
        case .searchQuery(let text):
            browse.searchText = text
            app.selection = .search
            browse.rememberSearch()
            Task { await browse.search() }

        case .format(let format):
            app.selection = .formats
            browse.formatsPath = [.episodes(pid: format.pid)]

        case .section(let section, _, _, _):
            app.selection = section

        case .action(let id, _, _, _, _):
            switch id {
            case "settings":
                openSettings()
            case "log":
                onToggleLogPanel()
            case "theme.auto":
                try? app.updateSettings { $0.theme = .auto }
            case "theme.light":
                try? app.updateSettings { $0.theme = .light }
            case "theme.dark":
                try? app.updateSettings { $0.theme = .dark }
            default:
                break
            }
        }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.16)) {
            isPresented = false
        }
    }
}
