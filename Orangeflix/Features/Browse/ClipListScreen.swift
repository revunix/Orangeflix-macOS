import SwiftUI

/// The two clip lists of the sidebar (Go `ScreenClips`).
enum ClipListKind: String, Hashable, CaseIterable, Sendable {
    /// The clips the account watched most recently.
    case recents
    /// The clips on the Merkliste.
    case bookmarks

    /// The title of the list.
    var title: String {
        switch self {
        case .recents: "Weiterschauen"
        case .bookmarks: "Merkliste"
        }
    }

    /// The text of the empty list (Go `clipPanel`).
    var emptyText: String {
        switch self {
        case .recents: "Noch nichts angefangen."
        case .bookmarks: "Keine gemerkten Folgen."
        }
    }

    /// The hint under the empty list: what to do next.
    var emptyDetail: String {
        switch self {
        case .recents: "Wähle ein Format, um seine Folgen zu sehen."
        case .bookmarks: "Markiere eine Folge im Kontextmenü ihrer Karte."
        }
    }

    /// The label of the loading list (Go `clips_cmds.go`).
    var loadingLabel: String {
        switch self {
        case .recents: "Lade die zuletzt gesehenen Folgen …"
        case .bookmarks: "Lade die Merkliste …"
        }
    }
}

/// Weiterschauen and Merkliste (Go `ScreenClips`).
struct ClipListScreen: View {
    /// The list that is shown.
    let kind: ClipListKind

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageChrome(title: kind.title, subtitle: subtitle) {
                    MoreMenu {
                        Button("Ansehen") { watch() }
                        Button("Herunterladen") { download() }
                        Button("Angaben") { showsInspector.toggle() }
                    }
                }
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
            await model.ensureClipList(kind)
        }
    }

    private var state: BrowseClipListState { model.clipList(kind) }

    /// The count of the list and its state.
    private var subtitle: String {
        if state.isLoading && state.episodes.isEmpty { return kind.loadingLabel }
        return "\(state.episodes.count) Folgen"
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        BrowseClipListView(
            episodes: state.episodes,
            isLoading: state.isLoading,
            loadingLabel: kind.loadingLabel,
            emptyText: kind.emptyText,
            emptyDetail: kind.emptyDetail,
            errorText: state.error,
            selection: $selection,
            emphasizeFirst: kind == .recents,
            groupByFormat: kind == .bookmarks,
            emptySymbol: kind == .bookmarks ? "star" : "clock.arrow.circlepath",
            onChooseQuality: { qualityEpisode = $0 })
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let episode = focusedEpisode {
            BrowseInspector(title: BrowseLogic.title(of: episode)) {
                BrowseEpisodeDetails(
                    episode: episode,
                    badge: model.badge(episode),
                    bookmarked: model.isBookmarked(episode),
                    percent: model.current(episode).progressPercent)
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

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                watch()
            } label: {
                Label("Ansehen", systemImage: "play")
            }
            .help("Die gewählten Folgen abspielen")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                download()
            } label: {
                Label("Herunterladen", systemImage: "arrow.down.circle")
            }
            .help("Die gewählten Folgen herunterladen")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showsInspector.toggle()
            } label: {
                Label("Angaben", systemImage: "sidebar.trailing")
            }
            .help("Die Angaben zur Folge zeigen")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let episode = focusedEpisode {
                    actions(for: episode)
                } else {
                    Text("Keine Folge gewählt.")
                }
            } label: {
                Label("Aktionen", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder private func actions(for episode: Episode) -> some View {
        Button(model.watchLabel(episode)) {
            model.play([episode])
        }
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: nil) }
        }
        Button(model.isBookmarked(episode) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen") {
            Task { await model.toggleBookmark(episode) }
        }
        Button(model.isWatched(episode) ? "Als ungesehen markieren" : "Als gesehen markieren") {
            Task { await model.toggleWatched([episode]) }
        }
        Button("Qualität wählen") {
            qualityEpisode = episode
        }
        Button("Titel kopieren") {
            model.copyTitle(episode)
        }
        if model.isDownloaded(episode.identifier) {
            Divider()
            Button("Im Finder zeigen") {
                model.reveal(episode)
            }
        }
    }

    // MARK: Actions

    private var selectedEpisodes: [Episode] {
        state.episodes.filter { selection.contains($0.identifier) }
    }

    private func watch() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        model.play(episodes)
    }

    private func download() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        Task { await model.downloadEpisodes(episodes, of: nil) }
    }
}
