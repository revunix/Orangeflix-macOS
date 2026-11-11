import SwiftUI

/// The two clip lists of the sidebar (Go `ScreenClips`).
enum ClipListKind: String, Hashable, CaseIterable, Sendable {
    /// The clips the account watched most recently.
    case recents
    /// The clips on the Merkliste.
    case bookmarks

    var title: String {
        switch self {
        case .recents: "Weiterschauen"
        case .bookmarks: "Merkliste"
        }
    }

    var emptyText: String {
        switch self {
        case .recents: "Noch nichts angefangen."
        case .bookmarks: "Keine gemerkten Folgen."
        }
    }

    var emptyDetail: String {
        switch self {
        case .recents: "Wähle ein Format, um seine Folgen zu sehen."
        case .bookmarks: "Markiere eine Folge im Kontextmenü ihrer Karte oder auf der Folgenseite."
        }
    }

    var loadingLabel: String {
        switch self {
        case .recents: "Lade die zuletzt gesehenen Folgen …"
        case .bookmarks: "Lade die Merkliste …"
        }
    }
}

/// Filter options for the Merkliste screen.
private enum BookmarksFilter: String, CaseIterable, Identifiable {
    case all, open, downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .open: "Ungesehen"
        case .downloaded: "Geladen"
        }
    }
}

/// Weiterschauen and Merkliste (Go `ScreenClips`).
struct ClipListScreen: View {
    let kind: ClipListKind

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?
    @State private var filter = ContinueWatchingFilter.all
    @State private var bookmarksFilter = BookmarksFilter.all
    @State private var bookmarksGrouped = true
    @State private var bookmarksQuery = ""
    @State private var pendingMark: PendingMark?
    @State private var marking = false

    private struct PendingMark: Identifiable {
        let episodes: [Episode]
        let watched: Bool
        var id: String { "\(watched)-\(episodes.map(\.identifier).joined(separator: ","))" }
    }

    var body: some View {
        @Bindable var model = model
        return NavigationStack(path: kind == .recents ? $model.recentsPath : $model.bookmarksPath) {
            VStack(spacing: 0) {
                PageChrome(title: kind.title, subtitle: subtitle) {
                    IconAction(icon: "sidebar.trailing", help: "Angaben ein-/ausblenden") {
                        showsInspector.toggle()
                    }
                    MoreMenu {
                        Button("Ansehen") { watch() }
                        Button("Herunterladen") { download() }
                        Button("Angaben") { showsInspector.toggle() }
                        Divider()
                        Button("Alle als gesehen markieren") { mark(state.episodes, watched: true) }
                            .disabled(marking || state.episodes.allSatisfy { model.isWatched($0) })
                        Button("Alle als ungesehen markieren") { mark(state.episodes, watched: false) }
                            .disabled(marking || state.episodes.allSatisfy { model.current($0).progressPercent == 0 })
                        if selection.count > 1 {
                            Button("Auswahl als gesehen markieren") { mark(selectedEpisodes, watched: true) }
                                .disabled(marking)
                            Button("Auswahl als ungesehen markieren") { mark(selectedEpisodes, watched: false) }
                                .disabled(marking)
                        }
                    }
                }
                content
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
            .confirmationDialog(
                pendingMark.map { "\($0.episodes.count) Folgen als \($0.watched ? "gesehen" : "ungesehen") markieren?" } ?? "",
                isPresented: Binding(get: { pendingMark != nil }, set: { if !$0 { pendingMark = nil } }),
                titleVisibility: .visible,
                presenting: pendingMark
            ) { pending in
                Button(pending.watched ? "Als gesehen markieren" : "Als ungesehen markieren",
                       role: pending.watched ? nil : .destructive) {
                    run(pending.episodes, watched: pending.watched)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { pending in
                Text(pending.watched
                     ? "Der Fortschritt wird auf „gesehen“ gesetzt."
                     : "Der Fortschritt dieser Folgen wird zurückgesetzt; sie verschwinden aus Weiterschauen.")
            }
        }
        .task(id: app.accountGeneration) {
            model.prepare(for: app.accountGeneration)
            await model.ensureClipList(kind)
        }
    }

    private var state: BrowseClipListState { model.clipList(kind) }

    private var subtitle: String {
        if state.isLoading && state.episodes.isEmpty { return kind.loadingLabel }
        let count = state.episodes.count
        return count == 1 ? "1 Folge" : "\(count) Folgen"
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if kind == .recents {
            ContinueWatchingView(
                episodes: state.episodes,
                isLoading: state.isLoading,
                errorText: state.error,
                selection: $selection,
                filter: $filter,
                marking: marking,
                onMark: { mark($0, watched: $1) },
                onChooseQuality: { qualityEpisode = $0 }
            )
        } else {
            bookmarksContent
        }
    }

    // MARK: - Upgraded Merkliste

    private func matchesBookmarksFilter(_ episode: Episode, _ item: BookmarksFilter) -> Bool {
        switch item {
        case .all: true
        case .open: !model.isWatched(episode)
        case .downloaded: model.isDownloaded(episode.identifier)
        }
    }

    private var searchedBookmarks: [Episode] {
        let q = bookmarksQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return state.episodes }
        return state.episodes.filter {
            BrowseLogic.title(of: $0).localizedStandardContains(q)
                || $0.formatName.localizedStandardContains(q)
                || $0.description.localizedStandardContains(q)
        }
    }

    private var filteredBookmarks: [Episode] {
        searchedBookmarks.filter { matchesBookmarksFilter($0, bookmarksFilter) }
    }

    @ViewBuilder private var bookmarksContent: some View {
        if state.isLoading && state.episodes.isEmpty {
            ProgressView(kind.loadingLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.episodes.isEmpty {
            if let error = state.error {
                ContentUnavailableView {
                    Label("Die Merkliste konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.loadBookmarks(force: true) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "star", title: kind.emptyText, message: kind.emptyDetail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                bookmarksControlBar
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.s)

                if filteredBookmarks.isEmpty {
                    EmptyState(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "Keine gemerkten Folgen für diesen Filter.",
                        message: "Passe den Filter oder den Suchbegriff oben an."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BrowseClipListView(
                        episodes: filteredBookmarks,
                        isLoading: false,
                        loadingLabel: kind.loadingLabel,
                        emptyText: kind.emptyText,
                        emptyDetail: kind.emptyDetail,
                        errorText: nil,
                        selection: $selection,
                        emphasizeFirst: false,
                        groupByFormat: bookmarksGrouped,
                        emptySymbol: "star",
                        onChooseQuality: { qualityEpisode = $0 }
                    )
                }
            }
            .onExitCommand { selection = [] }
        }
    }

    private var bookmarksControlBar: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: 2) {
                ForEach(BookmarksFilter.allCases) { item in
                    let chosen = bookmarksFilter == item
                    let count = searchedBookmarks.reduce(into: 0) {
                        if matchesBookmarksFilter($1, item) { $0 += 1 }
                    }
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            bookmarksFilter = item
                        }
                    } label: {
                        HStack(spacing: Space.xs) {
                            Text(item.title)
                            Text("\(count)")
                                .font(AppFont.digits)
                                .foregroundStyle(chosen ? Palette.accentText : Palette.textTertiary)
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

            Button {
                withAnimation(.snappy(duration: 0.18)) { bookmarksGrouped.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: bookmarksGrouped ? "rectangle.stack" : "square.grid.2x2")
                    Text(bookmarksGrouped ? "Nach Format" : "Alle zusammen")
                }
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Space.m)
                .frame(height: 34)
                .glassPlate(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Zwischen Format-Gruppen und durchgehendem Raster wechseln")

            Spacer(minLength: 0)

            if !selection.isEmpty {
                bookmarksSelectionBar
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                TextField("Filtern", text: $bookmarksQuery, prompt: Text("Merkliste filtern …"))
                    .textFieldStyle(.plain)
                    .font(AppFont.bodySmall)
                    .frame(width: 150)
                if !bookmarksQuery.isEmpty {
                    Button {
                        bookmarksQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 34)
            .glassPlate(in: Capsule(), quietAppear: true)
        }
        .animation(.snappy(duration: 0.18), value: selection.isEmpty)
    }

    private var bookmarksSelectionBar: some View {
        let chosen = selectedEpisodes
        return HStack(spacing: Space.xs) {
            Text(chosen.count == 1 ? "1 gewählt" : "\(chosen.count) gewählt")
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textSecondary)
                .padding(.leading, Space.s)

            selectionIcon("Abspielen", symbol: "play.fill") { watch() }
            selectionIcon("Herunterladen", symbol: "arrow.down.circle") { download() }
            selectionIcon("Von Merkliste entfernen", symbol: "star.slash") {
                Task {
                    for ep in chosen {
                        await model.toggleBookmark(ep)
                    }
                    selection = []
                }
            }
            selectionIcon("Auswahl aufheben", symbol: "xmark") { selection = [] }
        }
        .padding(3)
        .glassPlate(in: Capsule(), interactive: true)
    }

    private func selectionIcon(_ help: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Inspector

    @ViewBuilder private var inspector: some View {
        if let episode = focusedEpisode {
            BrowseInspector(title: BrowseLogic.title(of: episode)) {
                BrowseEpisodeDetails(
                    episode: episode,
                    badge: model.badge(episode),
                    bookmarked: model.isBookmarked(episode),
                    percent: model.current(episode).progressPercent
                )
                if !episode.description.isEmpty {
                    BrowseDescriptionText(text: episode.description)
                }
            }
        } else {
            ContentUnavailableView("Keine Folge gewählt.", systemImage: "list.bullet")
        }
    }

    private var focusedEpisode: Episode? {
        let episodes = state.episodes
        if !selection.isEmpty {
            return episodes.first { selection.contains($0.identifier) }
        }
        return episodes.first
    }

    // MARK: - Actions

    private var selectedEpisodes: [Episode] {
        state.episodes.filter { selection.contains($0.identifier) }
    }

    private func watch() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        if episodes.count == 1, let episode = episodes.first {
            model.navigationPath.append(.episode(episode, autoplay: true))
        } else {
            model.play(episodes)
        }
    }

    private func mark(_ episodes: [Episode], watched: Bool) {
        guard !episodes.isEmpty, !marking else { return }
        if episodes.count == 1 {
            run(episodes, watched: watched)
        } else {
            pendingMark = PendingMark(episodes: episodes, watched: watched)
        }
    }

    private func run(_ episodes: [Episode], watched: Bool) {
        marking = true
        Task {
            if episodes.count == 1 {
                await model.setWatched(episodes[0], watched: watched)
            } else {
                await model.setWatched(episodes, watched: watched)
            }
            selection = selection.filter { id in state.episodes.contains { $0.identifier == id } }
            marking = false
        }
    }

    private func download() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        Task { await model.downloadEpisodes(episodes, of: nil) }
    }
}
