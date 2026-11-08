import SwiftUI

/// The Mediathek: the home of the app. The newest series stands on top as a
/// banner, shelves lead back into what was started, saved or just released,
/// and below them the whole catalog follows as posters, grouped by status
/// (Go `ScreenFormats`).
struct FormatsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model

    /// True while the hero still covers the transparent titlebar.
    @State private var heroCovers = true
    /// True once the catalog scrolls under the toolbar; the bar gets a
    /// fading scrim then.
    @State private var scrolledUnderTitlebar = false
    /// The banner that shows; the carousel moves it on.
    @State private var heroIndex = 0
    /// The episode whose quality picker is open from Weiterschauen.
    @State private var qualityEpisode: Episode?
    /// The downloaded episode waiting for the delete confirmation.
    @State private var deletedFile: Episode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.l, alignment: .top), count: 3)

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.formatsPath) {
            content
                .background(Palette.background)
                .navigationTitle("")
                .navigationDestination(for: BrowseRoute.self) { BrowseDestination(route: $0) }
        }
        .sheet(isPresented: Binding(get: { qualityEpisode != nil }, set: { if !$0 { qualityEpisode = nil } })) {
            if let qualityEpisode { BrowseQualitySheet(episode: qualityEpisode) }
        }
        .confirmationDialog(
            "Datei löschen?",
            isPresented: Binding(get: { deletedFile != nil }, set: { if !$0 { deletedFile = nil } }),
            presenting: deletedFile
        ) { episode in
            Button("Löschen", role: .destructive) {
                Task { await model.deleteDownload(episode) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { episode in
            Text("Die Datei von „\(BrowseLogic.title(of: episode))“ wird gelöscht.")
        }
        .task(id: app.accountGeneration) {
            model.prepare(for: app.accountGeneration)
            await model.ensureLoaded()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.formatsLoading && model.formats.isEmpty {
            ProgressView("Lade den Katalog …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.formatGroups.isEmpty {
            ContentUnavailableView {
                Label("Kein Format gefunden.", systemImage: "tv")
            } description: {
                Text("Der Katalog ist leer.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if showsShelves {
                        hero
                        shelves
                    } else {
                        header
                    }
                    catalog
                }
                .padding(.bottom, Space.xxl)
            }
            .ignoresSafeArea(edges: showsShelves ? .top : [])
            .softScrollEdge()
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, distance in
                heroCovers = distance < 320
                scrolledUnderTitlebar = distance > 12
            }
            .preference(key: TitlebarBackdropKey.self, value: showsShelves && heroCovers)
            .preference(key: TitlebarScrimKey.self, value: showsShelves && scrolledUnderTitlebar)
        }
    }

    /// The banner and the shelves only make sense for the whole catalog.
    private var showsShelves: Bool {
        !model.libraryOnly
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(model.libraryOnly ? "Bibliothek" : "Formate")
                .font(AppFont.display)
                .foregroundStyle(Palette.textPrimary)
            Text(subtitle)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.l)
    }

    private var subtitle: String {
        let count = model.formatGroups.reduce(0) { $0 + $1.formats.count }
        return model.libraryOnly ? "\(count) Formate in der Bibliothek" : "\(count) Formate"
    }

    // MARK: Hero

    /// The series that take turns on the banner: the ones with a new episode
    /// first, then the newest ones. Five are enough, the rest waits below.
    private var heroFormats: [Format] {
        let withBanner = model.visibleFormats.filter { !$0.banner.isEmpty }
        let sorted = withBanner.sorted { lhs, rhs in
            if lhs.newEpisode != rhs.newEpisode { return lhs.newEpisode }
            return (lhs.lastEpisodeTime ?? .distantPast) > (rhs.lastEpisodeTime ?? .distantPast)
        }
        return Array(sorted.prefix(5))
    }

    @ViewBuilder private var hero: some View {
        let items = heroFormats
        if items.isEmpty {
            header
        } else {
            ZStack(alignment: .bottomTrailing) {
                ForEach(Array(items.enumerated()), id: \.element.pid) { index, format in
                    heroItem(format)
                        .opacity(index == heroIndex ? 1 : 0)
                        .allowsHitTesting(index == heroIndex)
                        .zIndex(index == heroIndex ? 1 : 0)
                }
                if items.count > 1 {
                    heroDots(items)
                        .padding(.trailing, Space.page)
                        .padding(.bottom, Space.xl + 28)
                        .zIndex(2)
                }
            }
            .frame(height: Chrome.heroHeight)
            .animation(.easeInOut(duration: 0.9), value: heroIndex)
            .task(id: items.map(\.pid)) {
                // The banner moves on every few seconds; the pointer holds it.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled, items.count > 1 else { continue }
                    withAnimation(.easeInOut(duration: 0.9)) {
                        heroIndex = (heroIndex + 1) % items.count
                    }
                }
            }
            .onChange(of: items.count) { _, count in
                if heroIndex >= count { heroIndex = 0 }
            }
            .onAppear {
                if heroIndex >= items.count { heroIndex = 0 }
            }
        }
    }

    /// One banner of the carousel with its own words and buttons.
    private func heroItem(_ format: Format) -> some View {
        HeroBanner(
            imageURL: format.banner,
            height: Chrome.heroHeight,
            eyebrow: format.newEpisode ? "Neue Folge" : "Empfohlen",
            title: format.title,
            meta: heroMeta(format),
            text: format.description
        ) {
            PillButton(title: "Neueste Folge ansehen", symbol: "play.fill", style: .accent) {
                Task { await model.latest(of: format, watch: true) }
            }
            PillButton(title: "Alle Folgen", symbol: "list.bullet", style: .onPicture) {
                open(format)
            }
        }
    }

    /// The dots that name the place in the carousel; a click jumps there.
    private func heroDots(_ items: [Format]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.pid) { index, _ in
                Button {
                    withAnimation(.easeInOut(duration: 0.9)) { heroIndex = index }
                } label: {
                    Capsule()
                        .fill(.white.opacity(index == heroIndex ? 0.9 : 0.35))
                        .frame(width: index == heroIndex ? 18 : 6, height: 6)
                        .frame(height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Banner \(index + 1)")
                .accessibilityLabel("Banner \(index + 1)")
                .accessibilityValue(index == heroIndex ? "sichtbar" : "")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: heroIndex)
    }

    private func heroMeta(_ format: Format) -> String {
        var parts: [String] = []
        if !format.lastEpisode.isEmpty { parts.append("Letzte Folge \(format.lastEpisode)") }
        let count = model.episodeCountText(format)
        if count != "-" { parts.append("\(count) Folgen") }
        return parts.joined(separator: " · ")
    }

    // MARK: Shelves

    @ViewBuilder private var shelves: some View {
        if !model.recents.episodes.isEmpty {
            Shelf(title: "Weiterschauen", trailing: "\(model.recents.episodes.count)") {
                ForEach(model.recents.episodes, id: \.identifier) { episode in
                    episodeCard(episode, opensPage: true)
                        .contextMenu { recentMenu(episode) }
                }
            }
        }
        if !model.premiumEpisodes.isEmpty {
            Shelf(title: "Premium", trailing: "\(model.premiumEpisodes.count)") {
                ForEach(model.premiumEpisodes, id: \.identifier) { episode in
                    episodeCard(episode, opensPage: true)
                }
            }
        }
        let fresh = model.visibleFormats.filter(\.newEpisode)
        if !fresh.isEmpty {
            Shelf(title: "Neu", trailing: "\(fresh.count)") {
                ForEach(fresh, id: \.pid) { format in
                    Button { open(format) } label: {
                        FormatTile(format: format, count: model.episodeCountText(format))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 260)
                }
            }
        }
        if !model.bookmarks.episodes.isEmpty {
            Shelf(title: "Merkliste", trailing: "\(model.bookmarks.episodes.count)") {
                ForEach(model.bookmarks.episodes, id: \.identifier) { episode in
                    episodeCard(episode)
                }
            }
        }
    }

    private func episodeCard(_ episode: Episode, opensPage: Bool = false) -> some View {
        let current = model.current(episode)
        return EpisodeCard(
            episode: current,
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier)
        ) {
            if opensPage {
                model.formatsPath.append(.episode(episode, autoplay: false))
            } else {
                model.play([episode])
            }
        }
    }

    /// The right-click menu of a card in Weiterschauen.
    @ViewBuilder private func recentMenu(_ episode: Episode) -> some View {
        Button(model.watchLabel(episode)) {
            model.formatsPath.append(.episode(episode, autoplay: true))
        }
        Button("Im Player-Fenster ansehen") {
            model.play([episode])
        }
        Button("Folge öffnen") {
            model.formatsPath.append(.episode(episode, autoplay: false))
        }
        Divider()
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: nil) }
        }
        Button("Qualität wählen") { qualityEpisode = episode }
        Divider()
        Button(model.isBookmarked(episode) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen") {
            Task { await model.toggleBookmark(episode) }
        }
        Button(model.isWatched(episode) ? "Als ungesehen markieren" : "Als gesehen markieren") {
            Task { await model.toggleWatched([episode]) }
        }
        Button("Ähnliche Folgen") {
            model.formatsPath.append(.similar(episode))
        }
        if episode.participants.count == 1, let guest = episode.participants.first {
            Button("Gast öffnen") { model.formatsPath.append(.host(guest)) }
        } else if episode.participants.count > 1 {
            Menu("Gast öffnen") {
                ForEach(episode.participants, id: \.id) { guest in
                    Button(guest.name.isEmpty ? "Gast" : guest.name) {
                        model.formatsPath.append(.host(guest))
                    }
                }
            }
        }
        Button("Titel kopieren") { model.copyTitle(episode) }
        if model.isDownloaded(episode.identifier) {
            Divider()
            Button("Im Finder zeigen") { model.reveal(episode) }
            Button("Datei löschen …", role: .destructive) { deletedFile = episode }
        }
    }

    // MARK: Catalog

    private var catalog: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(model.formatGroups) { group in
                VStack(alignment: .leading, spacing: Space.m) {
                    SectionHeader(title: groupTitle(group), detail: "\(group.formats.count)")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                        ForEach(group.formats, id: \.pid) { format in
                            Button { open(format) } label: {
                                FormatTile(format: format, count: model.episodeCountText(format))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.page)
    }

    private func groupTitle(_ group: BrowseFormatGroup) -> String {
        switch group.status {
        case .active: "Aktuell"
        case .seasonal: "Saisonal"
        case .archived: "Archiv"
        default: group.label
        }
    }

    @ViewBuilder private func actions(for format: Format) -> some View {
        Button("Folgen öffnen") { open(format) }
        Button("Neueste Folge ansehen") {
            Task { await model.latest(of: format, watch: true) }
        }
        Button("Neueste Folge herunterladen") {
            Task { await model.latest(of: format, watch: false) }
        }
        Divider()
        if model.libraryEntry(format.pid) != nil {
            Button("Neue Folgen herunterladen") { model.downloadNew(format) }
            Button("Bibliothek prüfen") {
                Task { await model.checkFormat(format) }
            }
            Button("Aus der Bibliothek entfernen") {
                Task { await model.removeFormat(format) }
            }
        } else {
            Button("Zur Bibliothek hinzufügen") {
                Task { await model.addFormat(format) }
            }
        }
        Divider()
        Button("Titel kopieren") {
            AppFormat.copy(format.title)
            app.show("Der Titel wurde kopiert.")
        }
    }

    // MARK: Actions

    private func open(_ format: Format) {
        model.formatsPath.append(.episodes(pid: format.pid))
    }

}

/// Destinations shared by the Mediathek and search navigation stacks.
struct BrowseDestination: View {
    let route: BrowseRoute
    @Environment(BrowseModel.self) private var model

    @ViewBuilder var body: some View {
        switch route {
        case .episodes(let pid):
            if let format = model.format(pid: pid) {
                EpisodesScreen(format: format)
            } else {
                ContentUnavailableView("Das Format ist nicht mehr im Katalog.", systemImage: "exclamationmark.triangle")
            }
        case .similar(let episode):
            SimilarScreen(episode: episode)
        case .host(let participant):
            HostScreen(participant: participant)
        case .guests:
            GuestDirectoryScreen()
        case .episode(let episode, let autoplay):
            EpisodeDetailScreen(episode: episode, autoplay: autoplay)
        case .episodeAt(let episode, let seconds):
            EpisodeDetailScreen(episode: episode, autoplay: true, startAt: seconds)
        }
    }
}
