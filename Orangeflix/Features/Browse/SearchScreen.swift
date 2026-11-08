import SwiftUI

/// The full text search (Go `ScreenSearch`). It searches while the user
/// types, over titles, descriptions, chapters and the spoken text, and shows
/// for every hit the places that matched; a click on a place starts the
/// episode there.
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s) {
                PageChrome(title: "Suche", subtitle: subtitle) {
                    MoreMenu {
                        Button("Ansehen") { watch() }
                        Button("Herunterladen") { download() }
                        Button("Angaben") { showsInspector.toggle() }
                        if let episode = focusedEpisode {
                            Divider()
                            menu(for: episode)
                        }
                    }
                }
                searchField
                if isQueryActive { filterBar }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("")
            .inspector(isPresented: $showsInspector) { inspector }
            .sheet(isPresented: Binding(get: { qualityEpisode != nil }, set: { if !$0 { qualityEpisode = nil } })) {
                if let episode = qualityEpisode {
                    BrowseQualitySheet(episode: episode)
                }
            }
        }
        .task(id: app.accountGeneration) {
            model.prepare(for: app.accountGeneration)
        }
        // The live search: every key starts over, the server is asked once
        // the typing pauses. A new format filter asks at once.
        .task(id: LiveKey(text: model.searchText, format: model.searchFormatPID, person: model.searchPersonID)) {
            let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query == model.searchQuery, model.searchFormatPID == model.searchedFormatPID,
               model.searchPersonID == model.searchedPersonID,
               !model.searchHits.isEmpty, model.searchError == nil { return }
            if query.count >= SearchLogic.minimumQueryLength {
                try? await Task.sleep(for: SearchLogic.typingDelay)
                guard !Task.isCancelled else { return }
            }
            await model.search()
        }
        .onChange(of: model.searchQuery) { selection = [] }
        .onAppear { fieldFocused = true }
    }

    private struct LiveKey: Hashable {
        let text: String
        let format: Int?
        let person: String?
    }

    private var trimmedText: String { model.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isQueryActive: Bool { trimmedText.count >= SearchLogic.minimumQueryLength }

    /// The count of the hits and the term that was searched.
    private var subtitle: String {
        guard isQueryActive, !model.searchQuery.isEmpty else { return "" }
        let count = model.searchHits.count
        let found = count == 1 && model.searchNextOffset == nil
            ? "1 Folge" : "\(count)\(model.searchNextOffset == nil ? "" : "+") Folgen"
        return "\(found) für „\(model.searchQuery)“"
    }

    // MARK: Field and filters

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            TextField("Suchbegriff", text: $model.searchText,
                      prompt: Text("Titel, Kapitel, Beschreibung oder Gesprochenes"))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($fieldFocused)
                .onSubmit {
                    model.rememberSearch()
                    Task { await model.search() }
                }
                .onKeyPress(.escape) {
                    guard !model.searchText.isEmpty else { return .ignored }
                    model.searchText = ""
                    return .handled
                }
            if model.searching {
                ProgressView()
                    .controlSize(.small)
            }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 40)
        .glassPlate(in: Capsule(), interactive: true)
        .padding(.horizontal, Space.page)
    }

    private var filterBar: some View {
        @Bindable var model = model
        let counts = SearchLogic.counts(model.searchHits)
        return HStack(spacing: Space.m) {
            // The kinds as one glass capsule; the chosen one stands in the accent.
            HStack(spacing: 2) {
                ForEach(SearchKindFilter.allCases) { kind in
                    let chosen = model.searchKind == kind
                    let count = counts[kind, default: 0]
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { model.searchKind = kind }
                    } label: {
                        HStack(spacing: Space.xs) {
                            Text(kind.title)
                            if kind != .all, count > 0 {
                                Text("\(count)")
                                    .font(AppFont.digits)
                                    .foregroundStyle(chosen ? Palette.accentText : Palette.textTertiary)
                            }
                        }
                        .font(AppFont.captionMedium)
                        .foregroundStyle(chosen ? Palette.accentText : Palette.textPrimary)
                        .padding(.horizontal, Space.m)
                        .frame(height: 28)
                        .background {
                            if chosen { Capsule().fill(Palette.accentSoft) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(3)
            .glassPlate(in: Capsule(), interactive: true)

            Spacer(minLength: 0)

            Menu {
                Picker("Format", selection: $model.searchFormatPID) {
                    Text("Alle Formate").tag(Int?.none)
                    Divider()
                    ForEach(searchableFormats, id: \.pid) { format in
                        Text(format.title).tag(Int?.some(format.pid))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(formatTitle, systemImage: "rectangle.stack")
            }
            .menuStyle(.button)
            .glassButtonStyle()
            .fixedSize()
            .help("Nur in einem Format suchen")

            Menu {
                Picker("Reihenfolge", selection: $model.searchSort) {
                    ForEach(SearchSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.searchSort.title, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .glassButtonStyle()
            .fixedSize()
            .help("Reihenfolge der Treffer")

            if !searchablePersons.isEmpty {
                Menu {
                    Picker("Person", selection: $model.searchPersonID) {
                        Text("Alle Personen").tag(String?.none)
                        Divider()
                        ForEach(searchablePersons, id: \.id) { person in
                            Text(person.name).tag(String?.some(person.id))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(personTitle, systemImage: "person.crop.circle")
                }
                .menuStyle(.button)
                .glassButtonStyle()
                .fixedSize()
                .help("Nur nach einer Person suchen")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, Space.page)
    }

    /// The name of the person the search is narrowed to.
    private var personTitle: String {
        guard let id = model.searchPersonID else { return "Alle Personen" }
        return model.guestDirectory.first { $0.id == id }?.name ?? "Person"
    }

    /// The people the search may be narrowed to: the guests the app has
    /// seen so far.
    private var searchablePersons: [Participant] {
        model.guestDirectory.filter { !$0.name.isEmpty }
    }

    /// The name of the format the search is narrowed to.
    private var formatTitle: String {
        guard let pid = model.searchFormatPID else { return "Alle Formate" }
        return model.formats.first { $0.pid == pid }?.title ?? "Format"
    }

    /// The formats of the catalog in alphabetical order.
    private var searchableFormats: [Format] {
        model.formats.filter { !$0.title.isEmpty }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if trimmedText.isEmpty {
            startPage
        } else if !isQueryActive {
            hint("Noch ein Zeichen …", symbol: "character.cursor.ibeam")
        } else if model.searchHits.isEmpty {
            if model.searching || model.searchQuery != trimmedText && model.searchError == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.searchError {
                ContentUnavailableView {
                    Label("Die Suche ist fehlgeschlagen.", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.search() } }
                        .glassButtonStyle()
                }
            } else {
                ContentUnavailableView {
                    Label("Keine Treffer für „\(model.searchQuery)“", systemImage: "magnifyingglass")
                } description: {
                    Text(model.searchFormatPID == nil
                         ? "Versuche einen anderen oder kürzeren Begriff."
                         : "In diesem Format gibt es nichts dazu.")
                } actions: {
                    if model.searchFormatPID != nil {
                        Button("In allen Formaten suchen") { model.searchFormatPID = nil }
                            .glassButtonStyle()
                    }
                    if model.searchPersonID != nil {
                        Button("Nach allen Personen suchen") { model.searchPersonID = nil }
                            .glassButtonStyle()
                    }
                }
            }
        } else {
            list
        }
    }

    /// The page before the first letter: the last searches and what the
    /// search covers.
    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if !model.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            SectionLabel(text: "Zuletzt gesucht")
                            Spacer()
                            Button("Verlauf löschen") { model.clearSearchHistory() }
                                .buttonStyle(.link)
                                .font(AppFont.caption)
                        }
                        FlowChips(items: model.recentSearches) { query in
                            model.searchText = query
                            model.rememberSearch()
                        } onRemove: { query in
                            model.forgetSearch(query)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Space.m) {
                    SectionLabel(text: "Was die Suche findet")
                    tip("textformat", "Titel und Beschreibungen", "Folgen, deren Name oder Text den Begriff enthält.")
                    tip("list.bullet.rectangle", "Kapitel", "Ein Klick auf das Kapitel startet die Folge genau dort.")
                    tip("waveform", "Gesprochenes",
                        "Jede Stelle, an der der Begriff fällt, mit Zeitmarke zum direkten Einstieg.")
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheading).foregroundStyle(Palette.textPrimary)
                Text(text).font(AppFont.bodySmall).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func hint(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(AppFont.body)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        let hits = model.visibleSearchHits
        return List(selection: $selection) {
            if hits.isEmpty {
                Text("Unter den geladenen Treffern ist keiner dieser Art.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.l)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(hits, id: \.id) { hit in
                let episode = hit.episode
                SearchHitRow(
                    hit: hit,
                    query: model.searchQuery,
                    episode: model.current(episode),
                    badge: model.badge(episode),
                    downloaded: model.isDownloaded(episode.identifier),
                    onPlay: { play(episode) },
                    onPlayAt: { seconds in play(episode, from: seconds) })
                .padding(Space.m)
                .contentCard(selected: selection.contains(hit.id))
                .tag(hit.id)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.page, bottom: Space.xs, trailing: Space.page))
                .contextMenu { menu(for: episode) }
            }
            if model.searchNextOffset != nil {
                HStack(spacing: Space.s) {
                    if model.searchingMore {
                        ProgressView().controlSize(.small)
                        Text("Lade weitere Treffer …")
                    } else {
                        PillButton(title: "Weitere Treffer laden", symbol: "arrow.down", style: .glass) {
                            Task { await model.searchMore() }
                        }
                    }
                }
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                // Reaching the end of the list loads the next page.
                .onAppear { Task { await model.searchMore() } }
            }
        }
        .listStyle(.plain)
        .tint(Palette.accent)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .onKeyPress(.return) {
            watch()
            return .handled
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let episode = focusedEpisode {
            BrowseInspector(title: BrowseLogic.title(of: episode)) {
                BrowseEpisodeDetails(
                    episode: episode,
                    badge: model.badge(episode),
                    bookmarked: model.isBookmarked(episode),
                    percent: model.current(episode).progressPercent,
                    showsDate: true,
                    showsGuests: false)
                if !episode.description.isEmpty {
                    BrowseDescriptionText(text: episode.description)
                }
            }
        } else {
            ContentUnavailableView("Keine Folge gewählt.", systemImage: "magnifyingglass")
        }
    }

    private var focusedEpisode: Episode? {
        let hits = model.visibleSearchHits
        if !selection.isEmpty, let hit = hits.first(where: { selection.contains($0.id) }) {
            return hit.episode
        }
        return hits.first?.episode
    }

    @ViewBuilder private func menu(for episode: Episode) -> some View {
        Button(model.watchLabel(episode)) { play(episode) }
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: nil) }
        }
        Button(model.isBookmarked(episode) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen") {
            Task { await model.toggleBookmark(episode) }
        }
        Button(model.isWatched(episode) ? "Als ungesehen markieren" : "Als gesehen markieren") {
            Task { await model.toggleWatched([episode]) }
        }
        Button("Qualität wählen") { qualityEpisode = episode }
        Button("Titel kopieren") { model.copyTitle(episode) }
    }

    // MARK: Actions

    private var selectedEpisodes: [Episode] {
        model.visibleSearchHits.filter { selection.contains($0.id) }.map(\.episode)
    }

    private func play(_ episode: Episode) {
        model.rememberSearch()
        model.play([episode])
    }

    private func play(_ episode: Episode, from seconds: Int) {
        model.rememberSearch()
        model.play(episode, from: seconds)
    }

    private func watch() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        model.rememberSearch()
        model.play(episodes)
    }

    private func download() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        Task { await model.downloadEpisodes(episodes, of: nil) }
    }
}

// MARK: - Hit row

/// One hit: the picture, where it comes from, the title with the term
/// marked, the matching text and the places inside the episode.
private struct SearchHitRow: View {
    let hit: SearchResult
    let query: String
    let episode: Episode
    let badge: BrowseEpisodeBadge
    let downloaded: Bool
    let onPlay: () -> Void
    let onPlayAt: (Int) -> Void

    /// The passages that show before "weitere Stellen".
    private static let collapsedPassages = 3
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            EpisodeThumb(episode: episode, percent: episode.progressPercent, downloaded: downloaded, onPlay: onPlay)
                .frame(width: 176)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    kindTag
                    Text(meta)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Text(SearchLogic.marked(BrowseLogic.title(of: episode), query: query))
                    .font(AppFont.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if let text = descriptionText {
                    Text(text)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                if hit.chapter != nil || !hit.passages.isEmpty {
                    moments
                        .padding(.top, Space.xxs)
                }
                BrowseBadgeView(badge: badge)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
    }

    private var meta: String {
        var parts = [hit.projectTitle]
        if !hit.hideSeqNr, hit.seqNr > 0 { parts.append("Folge \(hit.seqNr)") }
        parts.append(BrowseEpisodeRow.dateText(hit.date))
        parts.append(hit.duration)
        return parts.filter { !$0.isEmpty && $0 != "-" }.joined(separator: " · ")
    }

    /// The description with the term marked; the short one when the term
    /// is somewhere else.
    private var descriptionText: AttributedString? {
        if !hit.highlightedDescription.isEmpty { return SearchLogic.highlighted(hit.highlightedDescription) }
        let plain = hit.shortDescription.isEmpty ? hit.description : hit.shortDescription
        return plain.isEmpty ? nil : SearchLogic.marked(SearchLogic.unescaped(plain), query: query)
    }

    private var kindTag: some View {
        let (title, symbol): (String, String) = switch hit.kind {
        case .clip: ("Titel & Text", "textformat")
        case .chapter: ("Kapitel", "list.bullet.rectangle")
        case .transcript: ("Gesprochen", "waveform")
        }
        return Label(title, systemImage: symbol)
            .font(AppFont.micro)
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Palette.accentSoft, in: Capsule())
    }

    private var moments: some View {
        let passages = expanded ? hit.passages : Array(hit.passages.prefix(Self.collapsedPassages))
        return VStack(alignment: .leading, spacing: 2) {
            if let chapter = hit.chapter {
                MomentButton(moment: chapter, symbol: "list.bullet.rectangle", quoted: false) {
                    onPlayAt(chapter.startSeconds)
                }
            }
            ForEach(Array(passages.enumerated()), id: \.offset) { _, passage in
                MomentButton(moment: passage, symbol: "waveform", quoted: true) {
                    onPlayAt(passage.startSeconds)
                }
            }
            if hit.passages.count > Self.collapsedPassages {
                Button(expanded ? "Weniger Stellen" : "\(hit.passages.count - Self.collapsedPassages) weitere Stellen") {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .font(AppFont.caption)
                .padding(.leading, Space.s)
                .padding(.top, 2)
            }
        }
    }
}

/// A place inside an episode: the time and the text around the term. A
/// click starts the episode there.
private struct MomentButton: View {
    let moment: SearchMoment
    let symbol: String
    let quoted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: hovering ? "play.fill" : symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 14)
                Text(moment.startFormatted.isEmpty ? AppFormat.position(Double(moment.startSeconds)) : moment.startFormatted)
                    .font(AppFont.digitsMedium)
                    .foregroundStyle(Palette.accentText)
                    .frame(minWidth: 52, alignment: .leading)
                Text(label)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(hovering ? Palette.accentSoft : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ab \(moment.startFormatted) ansehen")
    }

    private var label: AttributedString {
        var text = SearchLogic.highlighted(moment.text)
        if quoted { text = AttributedString("„") + text + AttributedString("“") }
        if !moment.section.isEmpty {
            var section = AttributedString(SearchLogic.unescaped(moment.section) + " · ")
            section.foregroundColor = Palette.textSecondary
            text = section + text
        }
        return text
    }
}

/// The last searches as chips that wrap; a click searches again.
private struct FlowChips: View {
    let items: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: Space.xs) {
                    Button {
                        onSelect(item)
                    } label: {
                        Label(item, systemImage: "clock.arrow.circlepath")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Aus dem Verlauf entfernen")
                    .accessibilityLabel("„\(item)“ aus dem Verlauf entfernen")
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, 6)
                .glassPlate(in: Capsule(), interactive: true)
            }
        }
    }
}
