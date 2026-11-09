import AppKit
import CoreGraphics
import Observation
import SwiftUI

/// The full text search (Go `ScreenSearch`). It searches while the user
/// types, over titles, descriptions, chapters and the spoken text, and shows
/// for every hit the places that matched; a click previews that place in
/// the picture, while a click on the result opens the episode page.
struct SearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model
    @Environment(PlaybackCenter.self) private var playback

    @State private var selection: Set<String> = []
    private var preview: EpisodePreviewModel { playback.preview }
    @State private var pointer = SearchPointerTracker()
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        return NavigationStack(path: $model.searchPath) {
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
                // The field and the filters float: the page scrolls on
                // beneath their glass and dissolves towards the title. The
                // inset hangs on a stack and not on `content` itself: on the
                // changing content it is rebuilt with every change of the
                // page, and the field loses the focus after the first letter.
                ZStack { content }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: Space.s) {
                            searchField
                            if isQueryActive { filterBar }
                        }
                        .padding(.bottom, Space.s)
                        .background { chromeFade }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("")
            .navigationDestination(for: BrowseRoute.self) { BrowseDestination(route: $0) }
            .inspector(isPresented: $showsInspector) { inspector }
            .sheet(isPresented: Binding(get: { qualityEpisode != nil }, set: { if !$0 { qualityEpisode = nil } })) {
                if let episode = qualityEpisode {
                    BrowseQualitySheet(episode: episode)
                }
            }
        }
        .task(id: app.accountGeneration) {
            preview.resetAccess()
            model.prepare(for: app.accountGeneration)
        }
        // The live search: every key starts over, the server is asked once
        // the typing pauses. A new format filter asks at once.
        .task(id: LiveKey(text: model.searchText, format: model.searchFormatPID,
                          person: model.searchPersonID, account: app.accountGeneration)) {
            model.prepare(for: app.accountGeneration)
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
        .onChange(of: model.searchPath) { if !model.searchPath.isEmpty { preview.stop() } }
        .onDisappear { preview.stop() }
    }

    private struct LiveKey: Hashable {
        let text: String
        let format: Int?
        let person: String?
        let account: Int
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
                .focusEffectDisabled()
                .background {
                    // The field takes the focus once it stands in the window
                    // with its focus ring off, so no timing guess is needed.
                    SearchFieldRing {
                        guard model.searchPath.isEmpty else { return }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { fieldFocused = true }
                    }
                }
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
        // The text field handles focus and input itself. The plate must not
        // scale in, and it must not light up when the field becomes focused.
        // Its whole shape takes the click, so none reaches a card beneath.
        .glassPlate(in: Capsule(), quietAppear: true)
        .contentShape(Capsule())
        .focusEffectDisabled()
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
            .contentShape(Capsule())

            Spacer(minLength: 0)

            SearchFilterMenu(title: formatTitle, symbol: "rectangle.stack",
                             narrows: model.searchFormatPID != nil) {
                Picker("Format", selection: $model.searchFormatPID) {
                    Text("Alle Formate").tag(Int?.none)
                    Divider()
                    ForEach(searchableFormats, id: \.pid) { format in
                        Text(format.title).tag(Int?.some(format.pid))
                    }
                }
                .pickerStyle(.inline)
            }
            .help("Nur in einem Format suchen")

            SearchFilterMenu(title: model.searchSort.title, symbol: "arrow.up.arrow.down") {
                Picker("Reihenfolge", selection: $model.searchSort) {
                    ForEach(SearchSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            }
            .help("Reihenfolge der Treffer")

            if !searchablePersons.isEmpty {
                SearchFilterMenu(title: personTitle, symbol: "person.crop.circle",
                                 narrows: model.searchPersonID != nil) {
                    Picker("Person", selection: $model.searchPersonID) {
                        Text("Alle Personen").tag(String?.none)
                        Divider()
                        ForEach(searchablePersons, id: \.id) { person in
                            Text(person.name).tag(String?.some(person.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                .help("Nur nach einer Person suchen")
            }
        }
        .padding(.horizontal, Space.page)
    }

    /// The page colour, thinning out downwards. It lies between the page and
    /// the floating field and filters, so a card fades out beneath them
    /// instead of ending at a hard line below the title. Clicks pass through
    /// to the cards.
    private var chromeFade: some View {
        LinearGradient(colors: [Palette.background, Palette.background.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
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
                    tip("list.bullet.rectangle", "Kapitel", "Eine Sekunde über einem Kapitel zeigt eine kurze Vorschau genau dort.")
                    tip("waveform", "Gesprochenes",
                        "Jede Stelle, an der der Begriff fällt, mit Zeitmarke für die Vorschau.")
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
        return ScrollView {
            LazyVStack(spacing: Space.s) {
                if hits.isEmpty {
                    Text("Unter den geladenen Treffern ist keiner dieser Art.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                }
                ForEach(hits, id: \.id) { hit in
                    let episode = hit.episode
                    SearchHitRow(
                        hit: hit,
                        query: model.searchQuery,
                        episode: model.current(episode),
                        badge: model.badge(episode),
                        downloaded: model.isDownloaded(episode.identifier),
                        preview: preview,
                        pointer: pointer,
                        playback: playback)
                    .padding(Space.l)
                    .contentCard(selected: selection.contains(hit.id))
                    .contentShape(Rectangle())
                    .onTapGesture { open(hit) }
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
                    // Reaching the end of the list loads the next page.
                    .onAppear { Task { await model.searchMore() } }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.xs)
        }
        .background {
            SearchMouseEvents(pointer: pointer)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SearchPointerTracker.coordinateSpace)) } action: {
                    pointer.setSourceFrame($0)
                }
        }
        .coordinateSpace(name: SearchPointerTracker.coordinateSpace)
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            pointer.setViewport(CGRect(origin: .zero, size: $0))
        }
        .tint(Palette.accent)
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
        Button(model.watchLabel(episode)) { open(episode, autoplay: true) }
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: nil) }
        }
        Button(model.isBookmarked(episode) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen") {
            Task { await model.toggleBookmark(episode) }
        }
        if model.isWatched(episode) {
            Button("Als ungesehen markieren") {
                Task { await model.setWatched(episode, watched: false) }
            }
        } else {
            Button("Als gesehen markieren") {
                Task { await model.setWatched(episode, watched: true) }
            }
            Button("Als ungesehen markieren") {
                Task { await model.setWatched(episode, watched: false) }
            }
        }
        Button("Qualität wählen") { qualityEpisode = episode }
        Button("Titel kopieren") { model.copyTitle(episode) }
    }

    // MARK: Actions

    private var selectedEpisodes: [Episode] {
        model.visibleSearchHits.filter { selection.contains($0.id) }.map(\.episode)
    }

    /// A normal click opens the page; Command-click only changes selection.
    private func open(_ hit: SearchResult) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(hit.id) { selection.remove(hit.id) } else { selection.insert(hit.id) }
            return
        }
        selection = []
        open(hit.episode)
    }

    private func open(_ episode: Episode, autoplay: Bool = false) {
        preview.stop()
        model.rememberSearch()
        model.searchPath.append(.episode(episode, autoplay: autoplay))
    }

    private func watch() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        if episodes.count == 1 {
            open(episodes[0], autoplay: true)
            return
        }
        model.rememberSearch()
        model.play(episodes)
    }

    private func download() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        Task { await model.downloadEpisodes(episodes, of: nil) }
    }
}

/// A filter of the bar: a menu on its own glass plate, the same glass as the
/// kinds beside it, so its words stay readable over the hits that scroll
/// beneath. A filter that narrows the search stands in the accent, like the
/// chosen kind.
private struct SearchFilterMenu<Items: View>: View {
    let title: String
    let symbol: String
    var narrows = false
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(narrows ? Palette.accentText : Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .font(AppFont.captionMedium)
            .foregroundStyle(narrows ? Palette.accentText : Palette.textPrimary)
            .padding(.horizontal, Space.m)
            // As tall as the capsule of the kinds.
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassPlate(in: Capsule(), interactive: true)
        .fixedSize()
    }
}

/// The search picture becomes a small player without opening the episode.
private struct SearchPreviewThumb: View {
    let episode: Episode
    let downloaded: Bool
    let preview: EpisodePreviewModel
    let pointer: SearchPointerTracker
    let playback: PlaybackCenter

    @State private var hovering = false
    @State private var origin = UUID()

    private var active: Bool { preview.identifier == episode.identifier }
    private var denied: Bool { preview.isDenied(episode.identifier) }

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                EpisodePreviewSurface(episode: episode, preview: preview, playback: playback)
            }
            .overlay {
                if hovering && denied && !active {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.65), in: Circle())
                        .accessibilityLabel("Für diese Folge fehlt der Zugang")
                } else if hovering && preview.failureIdentifier == episode.identifier {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.65), in: Circle())
                        .accessibilityLabel(preview.failureMessage ?? "Vorschau nicht verfügbar")
                }
            }
            .overlay(alignment: .topLeading) {
                if active && !preview.isLoading {
                    EpisodePreviewClock(position: preview.position)
                } else if !active && (episode.isPremium || episode.isEarlyAccess) {
                    Text(episode.isPremium ? "Premium" : "Vorab")
                        .font(AppFont.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xxs)
                        .background(Palette.accent, in: Capsule())
                        .padding(Space.s)
                }
            }
            .overlay(alignment: .topTrailing) {
                if active && preview.isLoading {
                    ProgressView().controlSize(.small).tint(.white).padding(Space.xs)
                } else if !active && (downloaded || episode.progressPercent >= BrowseLogic.watchedPercent) {
                    Image(systemName: downloaded ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                        .font(AppFont.heading)
                        .foregroundStyle(.white, downloaded ? Palette.success : Palette.leaf)
                        .padding(Space.s)
                }
            }
            .overlay(alignment: .bottom) {
                if active && preview.mode == .hover && !preview.positions.isEmpty {
                    EpisodePreviewSegments(preview: preview)
                } else if !active {
                    WatchBar(percent: episode.progressPercent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .contentShape(Rectangle())
            .modifier(SearchHoverRegion(pointer: pointer, id: origin) { inside in
                hovering = inside
                if inside { preview.hover(episode, origin: origin, using: playback) }
                else { preview.leave(origin) }
            })
            .onDisappear {
                hovering = false
                preview.leave(origin)
            }
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
    let preview: EpisodePreviewModel
    let pointer: SearchPointerTracker
    let playback: PlaybackCenter

    /// The passages that show before "weitere Stellen".
    private static let collapsedPassages = 3
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            SearchPreviewThumb(episode: episode, downloaded: downloaded, preview: preview, pointer: pointer, playback: playback)
                // Reserve a full media column, rather than a small thumbnail
                // beside the first line. The ScrollView supplies the width;
                // all results keep the same split even when text expands.
                .containerRelativeFrame(.horizontal) { width, _ in
                    min(360, max(256, width * 0.28))
                }
            details
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 180, alignment: .topLeading)
        .padding(.vertical, Space.xs)
    }

    /// All result information stays in the right-hand column, including
    /// the places whose preview is shown in the media column on the left.
    private var details: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                kindTag
                Text(meta)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            Text(SearchLogic.marked(BrowseLogic.title(of: episode), query: query))
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
            if let text = descriptionText {
                Text(text)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            if hit.chapter != nil || !hit.passages.isEmpty {
                moments
                    .padding(.top, Space.xxs)
            }
            BrowseBadgeView(badge: badge)
        }
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
            .font(AppFont.captionMedium)
            .fixedSize()
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Palette.accentSoft, in: Capsule())
    }

    private var moments: some View {
        let passages = expanded ? hit.passages : Array(hit.passages.prefix(Self.collapsedPassages))
        return VStack(alignment: .leading, spacing: Space.xs) {
            if let chapter = hit.chapter {
                MomentButton(moment: chapter, symbol: "list.bullet.rectangle", quoted: false,
                             episode: episode, preview: preview, pointer: pointer, playback: playback)
            }
            ForEach(Array(passages.enumerated()), id: \.offset) { _, passage in
                MomentButton(moment: passage, symbol: "waveform", quoted: true,
                             episode: episode, preview: preview, pointer: pointer, playback: playback)
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

/// A place inside an episode; hovering for a second previews it.
private struct MomentButton: View {
    let moment: SearchMoment
    let symbol: String
    let quoted: Bool
    let episode: Episode
    let preview: EpisodePreviewModel
    let pointer: SearchPointerTracker
    let playback: PlaybackCenter

    @State private var hovering = false
    @State private var ready = false
    @State private var origin = UUID()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Button {
                guard hovering, ready, !preview.isDenied(episode.identifier) else { return }
                preview.play(episode, from: moment.startSeconds, origin: origin, muted: false, using: playback)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: hovering ? "play.fill" : symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 14)
                    Text(moment.startFormatted.isEmpty ? AppFormat.position(Double(moment.startSeconds)) : moment.startFormatted)
                        .font(AppFont.subheading.monospacedDigit())
                        .foregroundStyle(Palette.accentText)
                        .frame(minWidth: 52, alignment: .leading)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .modifier(SearchHoverRegion(pointer: pointer, id: origin) { inside in
                    hovering = inside
                    if !inside {
                        ready = false
                        preview.leave(origin)
                    }
                })
            }
            .buttonStyle(.plain)
            .task(id: hovering) {
                guard hovering else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled, hovering else { return }
                ready = true
                preview.play(episode, from: moment.startSeconds, origin: origin, muted: false, using: playback)
            }
            .accessibilityHint(preview.isDenied(episode.identifier) ? "Für diese Folge fehlt der Zugang" :
                               "Eine Sekunde verweilen für eine Vorschau")
            Text(label)
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                .fill(hovering ? Palette.accentSoft : .clear)
        }
        .onDisappear {
            hovering = false
            ready = false
            preview.leave(origin)
        }
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

/// Resolves the pointer against the actual visible thumbnail and timestamp
/// rectangles. One target, at most, receives hover at any moment.
@MainActor private final class SearchPointerTracker {
    nonisolated static let coordinateSpace = "search-preview-pointer"

    private struct Target {
        let frame: CGRect
        let onChange: (Bool) -> Void
    }

    private var targets: [UUID: Target] = [:]
    private var viewport = CGRect.zero
    private var sourceFrame: CGRect?
    private var localPoint: CGPoint?
    private var active: UUID?
    private var resolutionPending = false

    func setViewport(_ value: CGRect) {
        viewport = value
        scheduleResolution()
    }

    func setSourceFrame(_ value: CGRect) {
        sourceFrame = value
        scheduleResolution()
    }

    func setTarget(_ id: UUID, frame: CGRect, onChange: @escaping (Bool) -> Void) {
        targets[id] = Target(frame: frame, onChange: onChange)
        scheduleResolution()
    }

    func removeTarget(_ id: UUID) {
        targets.removeValue(forKey: id)
        if active == id { active = nil }
        scheduleResolution()
    }

    func move(to value: CGPoint?) {
        localPoint = value
        scheduleResolution()
    }

    /// Geometry updates can arrive during SwiftUI layout. Resolve them on
    /// the next turn, once every affected row has its current rectangle.
    private func scheduleResolution() {
        guard !resolutionPending else { return }
        resolutionPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resolutionPending = false
            self.resolve()
        }
    }

    private func resolve() {
        let regions = targets.map { SearchPointerRegion(id: $0.key, frame: $0.value.frame) }
        let point = localPoint.flatMap { local in
            sourceFrame.flatMap { $0.isEmpty ? nil : SearchPointerLogic.position(local, in: $0) }
        }
        let next = SearchPointerLogic.target(at: point, viewport: viewport, regions: regions)
        guard next != active else { return }
        let previous = active
        active = next
        if let previous { targets[previous]?.onChange(false) }
        if let next { targets[next]?.onChange(true) }
    }
}

/// Registers only the view's own measured rectangle, not its whole row.
private struct SearchHoverRegion: ViewModifier {
    let pointer: SearchPointerTracker
    let id: UUID
    let onChange: (Bool) -> Void
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SearchPointerTracker.coordinateSpace)) } action: { value in
                frame = value
                pointer.setTarget(id, frame: value, onChange: onChange)
            }
            .onAppear { pointer.setTarget(id, frame: frame, onChange: onChange) }
            .onDisappear { pointer.removeTarget(id) }
    }
}

/// Reads mouse positions from this window without consuming clicks or scrolls.
private struct SearchMouseEvents: NSViewRepresentable {
    let pointer: SearchPointerTracker

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        view.pointer = pointer
        return view
    }

    func updateNSView(_ view: EventView, context: Context) {
        view.pointer = pointer
        view.window?.acceptsMouseMovedEvents = true
    }

    static func dismantleNSView(_ view: EventView, coordinator: ()) {
        view.detach()
    }

    final class EventView: NSView {
        var pointer: SearchPointerTracker?
        private var monitor: Any?
        private var area: NSTrackingArea?
        private weak var observedWindow: NSWindow?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            observedWindow = window
            window.acceptsMouseMovedEvents = true
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: window)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]) { [weak self] event in
                MainActor.assumeIsolated { self?.read(event) }
                return event
            }
            checkPointer()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { checkPointer() }
        override func mouseExited(with event: NSEvent) { checkPointer() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        @objc private func keyChanged(_ notification: Notification) { checkPointer() }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let observedWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observedWindow)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
            }
            observedWindow = nil
            pointer?.move(to: nil)
        }

        private func read(_ event: NSEvent) {
            guard let window, window.isKeyWindow, event.window === window else {
                pointer?.move(to: nil)
                return
            }
            updatePoint(window.mouseLocationOutsideOfEventStream)
        }

        private func checkPointer() {
            guard let window, window.isKeyWindow else {
                pointer?.move(to: nil)
                return
            }
            updatePoint(window.mouseLocationOutsideOfEventStream)
        }

        private func updatePoint(_ windowPoint: NSPoint) {
            let point = convert(windowPoint, from: nil)
            let local = CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
            pointer?.move(to: bounds.contains(point) ? local : nil)
        }
    }
}

/// Prepares the search field before it takes the focus. It turns off the AppKit
/// focus ring of the field, which is a second drawing of the focus, and calls
/// `onReady` once the field stands in the window with its frame. Focusing
/// earlier draws the shared field editor for one frame at the window origin.
private struct SearchFieldRing: NSViewRepresentable {
    /// Called once the field is prepared; it may take the focus.
    let onReady: () -> Void

    func makeNSView(context: Context) -> AnchorView { AnchorView(onReady: onReady) }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.onReady = onReady
        view.prepare()
    }

    final class AnchorView: NSView {
        var onReady: () -> Void
        private var done = false

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("AnchorView is not loaded from a nib")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            prepare()
        }

        override func layout() {
            super.layout()
            prepare()
        }

        /// Finds the field under the anchor, which fills its background, and
        /// turns its ring off. Runs once per field.
        func prepare() {
            guard !done, let window, bounds.width > 1, let root = window.contentView else { return }
            let middle = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            guard let field = Self.textField(in: root, containing: middle) else { return }
            done = true
            field.focusRingType = .none
            // After the layout pass, so the focus moves into a placed field.
            DispatchQueue.main.async { [onReady] in onReady() }
        }

        private static func textField(in node: NSView, containing point: NSPoint) -> NSTextField? {
            if let field = node as? NSTextField, field.convert(field.bounds, to: nil).contains(point) {
                return field
            }
            for subview in node.subviews {
                if let field = textField(in: subview, containing: point) { return field }
            }
            return nil
        }
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
                .glassPlate(in: Capsule(), interactive: true, quietAppear: true)
            }
        }
    }
}
