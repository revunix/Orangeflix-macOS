import SwiftUI

/// The catalog: what the Mediathek lists and what may send a message.
/// One list with a search and a filter; every row switches both.
/// The search text lives here, so a keystroke does not rebuild the sidebar.
struct SettingsFormatsPage: View {
    @Binding var settingsError: String?
    /// Bumped when the sidebar search opens one format, which clears the
    /// list's own search. A fresh page already starts empty.
    var formatListGeneration: Int

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var browse
    @Environment(NewEpisodeWatcher.self) private var watcher

    @State private var formatQuery = ""
    @State private var formatFilter = SettingsFormatFilter.all

    var body: some View {
        let snapshot = formatSnapshot
        return Group {
            Section {
                SettingsFormatSearch(query: $formatQuery, filter: $formatFilter, counts: snapshot.counts)
                if browse.formats.isEmpty {
                    Text("Der Katalog wird geladen …")
                        .foregroundStyle(.secondary)
                } else if snapshot.filtered.isEmpty {
                    Text(formatQuery.isEmpty ? "Kein Format in dieser Auswahl." : "Kein Format passt zu „\(formatQuery)“.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.s)
                } else {
                    ForEach(snapshot.filtered, id: \.pid) { format in
                        SettingsFormatRow(
                            format: format,
                            visible: visibleBinding(format.pid),
                            notify: notifyBinding(format.pid),
                            notificationsOn: app.settings.notificationsOn)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Formate")
                    Spacer()
                    Text(formatSummary)
                        .font(.caption)
                        .lineLimit(1)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            } footer: {
                formatBulkActions(snapshot.filtered)
            }
        }
        .onChange(of: formatListGeneration) { _, _ in
            formatQuery = ""
            formatFilter = .all
        }
    }

    /// "38 von 40 in der Mediathek · 5 gemeldet" — the counts, in short.
    private var formatSummary: String {
        let all = browse.formats
        guard !all.isEmpty else { return "" }
        let hidden = Set(app.settings.hiddenMagazines)
        let announced = announcedFormats
        var visible = 0
        var notified = 0
        for format in all {
            if !hidden.contains(format.pid) { visible += 1 }
            if announced.contains(format.pid) { notified += 1 }
        }
        return "\(visible)/\(all.count) sichtbar · \(notified) gemeldet"
    }

    /// The chosen formats the Mediathek shows; only those are announced.
    private var announcedFormats: Set<Int> {
        NewEpisodeLogic.announced(notified: app.settings.notifiedMagazines, hidden: app.settings.hiddenMagazines)
    }

    /// The rows of the format list and the counts of the filter, from one
    /// sort. The page asks for it once per redraw.
    private struct FormatSnapshot {
        var filtered: [Format]
        var counts: [SettingsFormatFilter: Int]
    }

    private var formatSnapshot: FormatSnapshot {
        let query = formatQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let hidden = Set(app.settings.hiddenMagazines)
        let notified = Set(app.settings.notifiedMagazines)
        let sorted = browse.formats.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let searched = query.isEmpty ? sorted : sorted.filter {
            $0.title.localizedStandardContains(query) || $0.slug.localizedStandardContains(query)
                || $0.handle.localizedStandardContains(query)
        }
        func included(_ format: Format, _ filter: SettingsFormatFilter) -> Bool {
            switch filter {
            case .all: true
            case .visible: !hidden.contains(format.pid)
            case .hidden: hidden.contains(format.pid)
            case .notified: notified.contains(format.pid) && !hidden.contains(format.pid)
            }
        }
        var counts: [SettingsFormatFilter: Int] = [:]
        for filter in SettingsFormatFilter.allCases {
            counts[filter] = searched.reduce(into: 0) { if included($1, filter) { $0 += 1 } }
        }
        return FormatSnapshot(filtered: searched.filter { included($0, formatFilter) }, counts: counts)
    }

    /// Acts on the rows that show now: everything, or only the hits.
    private func formatBulkActions(_ rows: [Format]) -> some View {
        let shown = rows.map(\.pid)
        let narrowed = !formatQuery.isEmpty || formatFilter != .all
        let scope = narrowed ? "Treffer" : "Alle"
        let hidden = Set(app.settings.hiddenMagazines)
        let notified = Set(app.settings.notifiedMagazines)
        // The rows "melden" can act on: a hidden format is not announced.
        let open = shown.filter { !hidden.contains($0) }
        return VStack(alignment: .leading, spacing: Space.s) {
            FlowLayout(spacing: Space.s) {
                Button("\(scope) anzeigen") {
                    apply { $0.hiddenMagazines.removeAll { shown.contains($0) } }
                }
                .disabled(shown.allSatisfy { !hidden.contains($0) })
                .searchAnchor("formats.showAll")
                Button("\(scope) ausblenden") {
                    // The choice of "Melden" stays; a hidden format is just
                    // not announced, and showing it again brings it back.
                    apply { settings in
                        for pid in shown where !settings.hiddenMagazines.contains(pid) { settings.hiddenMagazines.append(pid) }
                    }
                }
                .disabled(shown.allSatisfy { hidden.contains($0) })
                .searchAnchor("formats.hideAll")
                Button("\(scope) melden") {
                    apply { settings in
                        for pid in shown where !settings.notifiedMagazines.contains(pid) && !settings.hiddenMagazines.contains(pid) {
                            settings.notifiedMagazines.append(pid)
                        }
                        settings.notificationsOn = true
                    }
                    Task { await watcher.refreshPermission() }
                }
                // With the main switch off nothing is announced, so the
                // button still has something to do: it turns it on.
                .disabled(open.isEmpty || (app.settings.notificationsOn && open.allSatisfy { notified.contains($0) }))
                .searchAnchor("formats.notifyAll")
                Button(narrowed ? "Treffer nicht melden" : "Keine melden") {
                    apply { $0.notifiedMagazines.removeAll { shown.contains($0) } }
                }
                .disabled(shown.allSatisfy { !notified.contains($0) })
                .searchAnchor("formats.notifyNone")
            }
            .controlSize(.small)
            Text("„Mediathek“ zeigt ein Format in der Mediathek; die Bibliothek bleibt. „Melden“ schickt eine Mitteilung, sobald eine neue Folge erscheint. Ausgeblendete Formate werden nicht gemeldet; ihre Auswahl gilt wieder, sobald sie angezeigt werden.")
        }
    }

    /// On means the catalog shows the format.
    private func visibleBinding(_ pid: Int) -> Binding<Bool> {
        Binding(
            get: { !app.settings.hiddenMagazines.contains(pid) },
            set: { show in
                apply { settings in
                    var hidden = settings.hiddenMagazines
                    if show {
                        hidden.removeAll { $0 == pid }
                    } else if !hidden.contains(pid) {
                        hidden.append(pid)
                    }
                    settings.hiddenMagazines = hidden
                }
            })
    }

    private func notifyBinding(_ pid: Int) -> Binding<Bool> {
        Binding(
            get: { app.settings.notifiedMagazines.contains(pid) },
            set: { on in
                apply { settings in
                    if on {
                        if !settings.notifiedMagazines.contains(pid) { settings.notifiedMagazines.append(pid) }
                        settings.notificationsOn = true
                    } else {
                        settings.notifiedMagazines.removeAll { $0 == pid }
                    }
                }
                if on { Task { await watcher.refreshPermission() } }
            })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
