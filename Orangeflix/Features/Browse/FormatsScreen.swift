import Foundation
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
    @State private var heroHovering = false
    @State private var heroSlideProgress: CGFloat = 0
    @State private var heroColor: ThemeRGB?
    /// The episode whose quality picker is open from Weiterschauen.
    @State private var qualityEpisode: Episode?
    /// The downloaded episode waiting for the delete confirmation.
    @State private var deletedFile: Episode?
    /// Filter and card style of the catalog below the shelves.
    @State private var catalogFilter: CatalogFilter = .all
    @State private var catalogQuery = ""
    @AppStorage("catalogCardStylePosters") private var usePosters = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private enum CatalogFilter: String, CaseIterable, Identifiable {
        case all, library, fresh
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle Formate"
            case .library: "Bibliothek"
            case .fresh: "Neue Folgen"
            }
        }
    }

    private var columns: [GridItem] {
        if usePosters {
            [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: Space.l, alignment: .top)]
        } else {
            [GridItem(.adaptive(minimum: 264, maximum: 360), spacing: Space.l, alignment: .top)]
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.formatsPath) {
            content
                .background(homeBackground.ignoresSafeArea())
                .task(id: heroImageURL) {
                    let color: ThemeRGB?
                    if let url = URL(string: heroImageURL), !heroImageURL.isEmpty {
                        color = await ImageCache.shared.representativeColor(for: url)
                    } else {
                        color = nil
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                        heroColor = color
                    }
                }
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
            .preference(key: TitlebarBackdropKey.self, value: isTopScreen && showsShelves && heroCovers)
            .preference(key: TitlebarScrimKey.self, value: isTopScreen && showsShelves && scrolledUnderTitlebar)
        }
    }

    /// Pushed destinations sit in the same `NavigationStack`; while one is
    /// open, the root catalog must not project its scrim onto the toolbar.
    private var isTopScreen: Bool {
        app.selection == .formats && model.formatsPath.isEmpty
    }

    /// The banner and the shelves only make sense for the whole catalog.
    private var showsShelves: Bool {
        !model.libraryOnly
    }

    /// A local background only: no theme tokens or destination colors change.
    private var homeBackground: Color {
        guard showsShelves, let heroColor else { return Palette.background }
        let dark = colorScheme == .dark
        guard let base = ThemeRGB(hex: ThemeRuntime.shared.hex(.background, dark: dark)) else {
            return Palette.background
        }
        let mixed = base.mixed(with: heroColor, dark ? 0.28 : 0.12)
        return Color(.sRGB, red: mixed.red, green: mixed.green, blue: mixed.blue, opacity: 1)
    }

    private var heroImageURL: String {
        let items = heroFormats
        guard showsShelves, items.indices.contains(heroIndex) else { return "" }
        return items[heroIndex].banner
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
                        .padding(.bottom, Space.xl + 4)
                        .zIndex(2)
                }
            }
            .frame(height: Chrome.heroHeight)
            .onHover { heroHovering = $0 }
            .animation(.easeInOut(duration: 0.75), value: heroIndex)
            .task(id: items.map(\.pid)) {
                guard !reduceMotion else { return }
                let tickSeconds = 0.08
                let totalSeconds = 8.0
                var elapsed = 0.0
                var observedIndex = heroIndex
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled, items.count > 1 else { continue }
                    if observedIndex != heroIndex {
                        observedIndex = heroIndex
                        elapsed = 0
                        heroSlideProgress = 0
                        continue
                    }
                    guard !heroHovering else { continue }
                    elapsed += tickSeconds
                    heroSlideProgress = min(CGFloat(elapsed / totalSeconds), 1)
                    if elapsed >= totalSeconds {
                        elapsed = 0
                        heroSlideProgress = 0
                        withAnimation(.easeInOut(duration: 0.75)) {
                            heroIndex = (heroIndex + 1) % items.count
                        }
                        observedIndex = heroIndex
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

    /// One banner of the carousel with its own words, cover emblem and buttons.
    private func heroItem(_ format: Format) -> some View {
        HeroBanner(
            imageURL: format.banner,
            height: Chrome.heroHeight,
            eyebrow: format.newEpisode ? "Neue Folge" : "Empfohlen",
            title: format.title,
            meta: heroMeta(format),
            text: format.description,
            coverFormat: format,
            backdrop: homeBackground
        ) {
            PillButton(title: "Neueste Folge ansehen", symbol: "play.fill", style: .accent) {
                Task { await model.latest(of: format, watch: true) }
            }
            PillButton(title: "Alle Folgen", symbol: "list.bullet", style: .onPicture) {
                open(format)
            }
        }
    }

    /// Dark-glass carousel capsule with previous/next arrows and animated progress pill.
    private func heroDots(_ items: [Format]) -> some View {
        HStack(spacing: 7) {
            Button {
                heroSlideProgress = 0
                withAnimation(.easeInOut(duration: 0.6)) {
                    heroIndex = (heroIndex - 1 + items.count) % items.count
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Voriges Banner")

            ForEach(Array(items.enumerated()), id: \.element.pid) { index, _ in
                let active = index == heroIndex
                Button {
                    heroSlideProgress = 0
                    withAnimation(.easeInOut(duration: 0.6)) { heroIndex = index }
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(active ? 0.26 : 0.35))
                        if active {
                            Capsule()
                                .fill(Palette.accent)
                                .frame(width: max(6, 26 * (reduceMotion ? 1 : heroSlideProgress)))
                        }
                    }
                    .frame(width: active ? 26 : 6, height: 6)
                    .frame(height: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Banner \(index + 1)")
                .accessibilityLabel("Banner \(index + 1)")
                .accessibilityValue(active ? "sichtbar" : "")
            }

            Button {
                heroSlideProgress = 0
                withAnimation(.easeInOut(duration: 0.6)) {
                    heroIndex = (heroIndex + 1) % items.count
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Nächstes Banner")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .animation(.snappy(duration: 0.22), value: heroIndex)
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
            Shelf(title: "Weiterschauen", trailing: "\(model.recents.episodes.count)",
                  onShowAll: { app.selection = .recents }) {
                ForEach(model.recents.episodes, id: \.identifier) { episode in
                    episodeCard(episode)
                        .contextMenu { recentMenu(episode) }
                }
            }
        }
        if !model.premiumEpisodes.isEmpty {
            Shelf(title: "Premium", trailing: "\(model.premiumEpisodes.count)",
                  onShowAll: { model.formatsPath.append(.premium) }) {
                ForEach(model.premiumEpisodes, id: \.identifier) { episode in
                    episodeCard(episode)
                }
            }
        }
        let fresh = model.visibleFormats.filter(\.newEpisode)
        if !fresh.isEmpty {
            Shelf(title: "Neu", trailing: "\(fresh.count)",
                  onShowAll: { model.formatsPath.append(.newFormats) }) {
                ForEach(fresh, id: \.pid) { format in
                    Button { open(format) } label: {
                        FormatTile(
                            format: format,
                            count: model.episodeCountText(format),
                            inLibrary: model.libraryEntry(format.pid) != nil,
                            onQuickPlay: { Task { await model.latest(of: format, watch: true) } }
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 260)
                    .contextMenu { actions(for: format) }
                }
            }
        }
        if !model.bookmarks.episodes.isEmpty {
            Shelf(title: "Merkliste", trailing: "\(model.bookmarks.episodes.count)",
                  onShowAll: { app.selection = .bookmarks }) {
                ForEach(model.bookmarks.episodes, id: \.identifier) { episode in
                    episodeCard(episode)
                }
            }
        }
    }

    private func episodeCard(_ episode: Episode) -> some View {
        let current = model.current(episode)
        return EpisodeCard(
            episode: current,
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier)
        ) {
            model.formatsPath.append(.episode(episode, autoplay: false))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.formatsPath.append(.episode(episode, autoplay: false))
        }
    }

    /// The right-click menu of a card in Weiterschauen.
    @ViewBuilder private func recentMenu(_ episode: Episode) -> some View {
        Button("Aus Weiterschauen entfernen") {
            Task { await model.setWatched(episode, watched: false) }
        }
        Divider()
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

    private func matchesCatalogFilter(_ format: Format, filter: CatalogFilter) -> Bool {
        switch filter {
        case .all: true
        case .library: model.libraryEntry(format.pid) != nil
        case .fresh: format.newEpisode
        }
    }

    private func matchesCatalogQuery(_ format: Format) -> Bool {
        let q = catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return format.title.localizedStandardContains(q)
            || format.description.localizedStandardContains(q)
            || format.slug.localizedStandardContains(q)
    }

    private var filteredGroups: [BrowseFormatGroup] {
        model.formatGroups.compactMap { group -> BrowseFormatGroup? in
            let formats = group.formats.filter {
                matchesCatalogFilter($0, filter: catalogFilter) && matchesCatalogQuery($0)
            }
            guard !formats.isEmpty else { return nil }
            return BrowseFormatGroup(status: group.status, formats: formats)
        }
    }

    private var catalogFilterBar: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: 2) {
                ForEach(CatalogFilter.allCases) { item in
                    let chosen = catalogFilter == item
                    let count = model.visibleFormats.reduce(into: 0) {
                        if matchesCatalogFilter($1, filter: item) && matchesCatalogQuery($1) { $0 += 1 }
                    }
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { catalogFilter = item }
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

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                TextField("Format filtern", text: $catalogQuery, prompt: Text("Format filtern …"))
                    .textFieldStyle(.plain)
                    .font(AppFont.bodySmall)
                    .frame(width: 148)
                if !catalogQuery.isEmpty {
                    Button {
                        catalogQuery = ""
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

            Button {
                withAnimation(.snappy(duration: 0.2)) { usePosters.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: usePosters ? "square.grid.3x3" : "rectangle.grid.2x2")
                    Text(usePosters ? "Poster" : "16:9 Kacheln")
                }
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Space.m)
                .frame(height: 34)
                .glassPlate(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Zwischen breiten 16:9-Kacheln und quadratischen Postern wechseln")
        }
    }

    private var catalog: some View {
        let groups = filteredGroups
        return VStack(alignment: .leading, spacing: Space.xl) {
            catalogFilterBar

            if groups.isEmpty {
                EmptyState(
                    symbol: "tv",
                    title: "Kein Format passt zu diesem Filter.",
                    message: "Setze den Katalog-Filter oder den Suchbegriff zurück."
                )
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Space.m) {
                        SectionHeader(title: groupTitle(group), detail: "\(group.formats.count)")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                            ForEach(group.formats, id: \.pid) { format in
                                Button { open(format) } label: {
                                    if usePosters {
                                        PosterCard(
                                            format: format,
                                            count: model.episodeCountText(format),
                                            inLibrary: model.libraryEntry(format.pid) != nil,
                                            onQuickPlay: { Task { await model.latest(of: format, watch: true) } }
                                        )
                                    } else {
                                        FormatTile(
                                            format: format,
                                            count: model.episodeCountText(format),
                                            inLibrary: model.libraryEntry(format.pid) != nil,
                                            onQuickPlay: { Task { await model.latest(of: format, watch: true) } }
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu { actions(for: format) }
                            }
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
        case .premium:
            PremiumListScreen()
        case .newFormats:
            NewFormatsScreen()
        }
    }
}
