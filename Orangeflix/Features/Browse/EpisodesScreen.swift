import AppKit
import SwiftUI

/// Which episodes of a series show in the list.
private enum EpisodeListFilter: String, CaseIterable, Identifiable {
    case all, open, downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .open: "Offen"
        case .downloaded: "Geladen"
        }
    }
}

/// The episodes of a format (Go `ScreenEpisodes`): the list grouped by year,
/// the year filter, the multiple selection and the actions of the episodes.
struct EpisodesScreen: View {
    /// The format whose episodes are shown.
    let format: Format

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection: Set<String> = []
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?
    @State private var confirmsAllDownload = false
    @State private var deletedFile: Episode?
    @State private var showsGuests = false
    @State private var stateFilter: EpisodeListFilter = .all
    @State private var filterText = ""
    @State private var heroColor: ThemeRGB?
    /// True while the hero banner still lies under the transparent titlebar.
    @State private var heroCovers = true
    /// True once the episodes scroll under the toolbar; the bar gets a
    /// fading scrim then.
    @State private var scrolledUnderTitlebar = false

    var body: some View {
        content
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("")
            .inspector(isPresented: $showsInspector) { inspector }
            .task(id: app.accountGeneration) { await load() }
            .task(id: format.banner) {
                let color: ThemeRGB?
                if let url = URL(string: format.banner), !format.banner.isEmpty {
                    color = await ImageCache.shared.representativeColor(for: url)
                } else {
                    color = nil
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
                    heroColor = color
                }
            }
            .sheet(isPresented: Binding(get: { qualityEpisode != nil }, set: { if !$0 { qualityEpisode = nil } })) {
                if let episode = qualityEpisode {
                    BrowseQualitySheet(episode: episode)
                }
            }
            .confirmationDialog(
                "Alle Folgen herunterladen?",
                isPresented: $confirmsAllDownload,
                titleVisibility: .visible
            ) {
                Button("Alle \(displayedEpisodes.count) Folgen herunterladen", role: .destructive) {
                    Task { await model.downloadEpisodes(displayedEpisodes, of: format) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Es ist keine Folge ausgewählt. Es werden alle \(displayedEpisodes.count) gefilterten Folgen geladen.")
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
            .confirmationDialog("Welcher Gast?", isPresented: $showsGuests, titleVisibility: .visible) {
                ForEach(focusedEpisode?.participants ?? [], id: \.id) { participant in
                    Button(participant.name) {
                        model.navigationPath.append(.host(participant))
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
    }

    private var pageBackground: Color {
        guard let heroColor else { return Palette.background }
        let dark = colorScheme == .dark
        guard let base = ThemeRGB(hex: ThemeRuntime.shared.hex(.background, dark: dark)) else {
            return Palette.background
        }
        let mixed = base.mixed(with: heroColor, dark ? 0.22 : 0.09)
        return Color(.sRGB, red: mixed.red, green: mixed.green, blue: mixed.blue, opacity: 1)
    }

    /// The same line the Mediathek hero shows: the newest episode and the count.
    private var heroMeta: String {
        var parts: [String] = []
        if !format.lastEpisode.isEmpty { parts.append("Letzte Folge \(format.lastEpisode)") }
        let count = displayedEpisodes.count
        if let year = model.yearFilter {
            parts.append("\(year) · \(count) Folgen")
        } else if count > 0 {
            parts.append("\(count) Folgen")
        } else if model.episodesLoading {
            parts.append(model.episodesLoadingLabel)
        }
        return parts.joined(separator: " · ")
    }

    private var hasActiveFilter: Bool {
        model.yearFilter != nil || stateFilter != .all || !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Applies the status and text filters on top of `model.visibleEpisodes`.
    private var displayedEpisodes: [Episode] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.visibleEpisodes.filter { episode in
            switch stateFilter {
            case .all:
                break
            case .open:
                if model.isWatched(episode) { return false }
            case .downloaded:
                if !model.isDownloaded(episode.identifier) { return false }
            }
            guard !query.isEmpty else { return true }
            if BrowseLogic.title(of: episode).lowercased().contains(query) { return true }
            if episode.description.lowercased().contains(query) { return true }
            if episode.number > 0, "\(episode.number)".contains(query) { return true }
            if episode.participants.contains(where: { $0.name.lowercased().contains(query) }) { return true }
            return false
        }
    }

    private var displayedYearGroups: [BrowseYearGroup] {
        BrowseLogic.yearGroups(displayedEpisodes) { model.isDownloaded($0.identifier) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.episodesLoading && model.episodes.isEmpty {
            ProgressView(model.episodesLoadingLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.episodesError {
            ContentUnavailableView {
                Label("Die Folgen konnten nicht geladen werden.", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Erneut versuchen") { Task { await load() } }
            }
        } else if model.episodes.isEmpty {
            VStack(spacing: 0) {
                PageChrome(title: format.title) { EmptyView() }
                ContentUnavailableView("Keine Folge gefunden.", systemImage: "film")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                hero
                filterBar
                    .padding(.horizontal, Space.page)
                if displayedYearGroups.isEmpty {
                    VStack(spacing: Space.m) {
                        EmptyState(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "Keine passenden Folgen.",
                            message: "Für die gewählten Filter gibt es in diesem Format keinen Treffer.")
                        if hasActiveFilter {
                            PillButton(title: "Filter zurücksetzen", symbol: "arrow.counterclockwise", style: .glass) {
                                resetFilters()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.l)
                } else {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        ForEach(displayedYearGroups) { group in
                            VStack(alignment: .leading, spacing: Space.s) {
                                SectionHeader(
                                    title: group.year,
                                    detail: group.loaded > 0
                                        ? "\(group.episodes.count) Folgen · \(group.loaded) geladen"
                                        : "\(group.episodes.count) Folgen")
                                LazyVStack(spacing: Space.s) {
                                    ForEach(group.episodes, id: \.identifier) { episode in
                                        episodeRow(episode)
                                    }
                                }
                            }
                            .padding(.horizontal, Space.page)
                        }
                    }
                }
            }
            .padding(.bottom, Space.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .softScrollEdge()
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, distance in
            heroCovers = distance < 320
            scrolledUnderTitlebar = distance > 12
        }
        .preference(key: TitlebarBackdropKey.self, value: isTopScreen && heroCovers)
        .preference(key: TitlebarScrimKey.self, value: isTopScreen && scrolledUnderTitlebar)
    }

    /// False once an episode or guest page is pushed above this series.
    private var isTopScreen: Bool {
        model.navigationPath.last == .episodes(pid: format.pid)
    }

    // MARK: Filter bar

    private var filterBar: some View {
        let years = model.availableYears
        let primaryYears = Array(years.prefix(3))
        let olderYears = Array(years.dropFirst(3))
        return HStack(spacing: Space.s) {
            if years.count > 1 {
                yearPicker(primary: primaryYears, older: olderYears)
            }
            statePicker
            Spacer(minLength: 0)
            searchField
            inspectorToggle
        }
    }

    private func yearPicker(primary: [String], older: [String]) -> some View {
        let selectedOlder = older.first { $0 == model.yearFilter }
        return HStack(spacing: 2) {
            yearChip(title: "Alle", year: nil)
            ForEach(primary, id: \.self) { year in
                yearChip(title: year, year: year)
            }
            if !older.isEmpty {
                Menu {
                    ForEach(older, id: \.self) { year in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { model.yearFilter = year }
                        } label: {
                            if model.yearFilter == year {
                                Label(year, systemImage: "checkmark")
                            } else {
                                Text(year)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedOlder ?? "Älter")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(AppFont.captionMedium)
                    .foregroundStyle(selectedOlder != nil ? Palette.accentText : Palette.textPrimary)
                    .padding(.horizontal, Space.m)
                    .frame(height: 28)
                    .background {
                        if selectedOlder != nil { Capsule().fill(Palette.accentSoft) }
                    }
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(3)
        .glassPlate(in: Capsule(), interactive: true)
    }

    private func yearChip(title: String, year: String?) -> some View {
        let chosen = model.yearFilter == year
        return Button {
            withAnimation(.snappy(duration: 0.18)) { model.yearFilter = year }
        } label: {
            Text(title)
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

    private var statePicker: some View {
        HStack(spacing: 2) {
            ForEach(EpisodeListFilter.allCases) { item in
                let chosen = stateFilter == item
                Button {
                    withAnimation(.snappy(duration: 0.18)) { stateFilter = item }
                } label: {
                    Text(item.title)
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
    }

    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            TextField("Folgen filtern …", text: $filterText)
                .textFieldStyle(.plain)
                .font(AppFont.bodySmall)
                .frame(minWidth: 120, idealWidth: 168, maxWidth: 210)
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Filtertext leeren")
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 34)
        .glassPlate(in: Capsule(), quietAppear: true)
    }

    private var inspectorToggle: some View {
        Button {
            showsInspector.toggle()
        } label: {
            Label("Angaben", systemImage: "sidebar.trailing")
                .font(AppFont.captionMedium)
                .foregroundStyle(showsInspector ? Palette.accentText : Palette.textPrimary)
                .padding(.horizontal, Space.m)
                .frame(height: 34)
                .background {
                    if showsInspector { Capsule().fill(Palette.accentSoft) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassPlate(in: Capsule(), interactive: true)
        .help(showsInspector ? "Angaben ausblenden" : "Angaben einblenden")
    }

    private func resetFilters() {
        withAnimation(.snappy(duration: 0.18)) {
            model.yearFilter = nil
            stateFilter = .all
            filterText = ""
        }
    }

    /// One episode. A click opens its page; the command key adds it to the
    /// selection; the play button on the picture opens the page and plays.
    private func episodeRow(_ episode: Episode) -> some View {
        let current = model.current(episode)
        return EpisodeRowCard(
            episode: current,
            badge: model.badge(episode),
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier),
            bookmarked: model.isBookmarked(episode),
            onBookmark: { Task { await model.toggleBookmark(episode) } },
            onDownload: { Task { await model.downloadEpisodes([episode], of: format) } }
        ) {
            model.navigationPath.append(.episode(episode, autoplay: true))
        }
        .contentCard(radius: Radius.card, selected: selection.contains(episode.identifier))
        .contentShape(Rectangle())
        .onTapGesture { open(episode) }
        .contextMenu { menu(for: episode) }
    }

    /// A plain click opens the page of the episode. The command key only
    /// changes the selection.
    private func open(_ episode: Episode) {
        let id = episode.identifier
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            return
        }
        selection = [id]
        model.navigationPath.append(.episode(episode, autoplay: false))
    }

    /// The banner of the series with its title, its text, the back step and the actions.
    private var hero: some View {
        let inLibrary = model.libraryEntry(format.pid) != nil
        return HeroBanner(
            imageURL: format.banner.isEmpty ? format.cover : format.banner,
            height: Chrome.heroHeight,
            eyebrow: format.newEpisode ? "Neue Folge" : (format.original ? "Eigenproduktion" : nil),
            title: format.title,
            meta: heroMeta,
            text: format.description,
            backdrop: pageBackground
        ) {
            PillButton(title: "Neueste Folge ansehen", symbol: "play.fill", style: .accent) {
                Task { await model.latest(of: format, watch: true) }
            }
            PillButton(title: selection.isEmpty ? "Alle laden" : "\(selection.count) laden",
                       symbol: "arrow.down.circle", style: .onPicture) {
                download()
            }
            PillButton(title: inLibrary ? "In der Bibliothek" : "Zur Bibliothek",
                       symbol: inLibrary ? "checkmark" : "plus", style: .onPicture) {
                Task {
                    if inLibrary {
                        await model.removeFormat(format)
                    } else {
                        await model.addFormat(format)
                    }
                }
            }
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let episode = focusedEpisode {
            BrowseInspector(title: BrowseLogic.title(of: episode)) {
                if !episode.thumb.isEmpty {
                    RemoteArt(url: episode.thumb)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                                .strokeBorder(Palette.divider, lineWidth: 1)
                        }
                }
                BrowseEpisodeDetails(
                    episode: episode,
                    badge: model.badge(episode),
                    bookmarked: model.isBookmarked(episode),
                    percent: model.current(episode).progressPercent,
                    file: model.downloadedFile(episode.identifier))
                if !episode.description.isEmpty {
                    BrowseDescriptionText(text: episode.description)
                }
                qualitySection(episode)
            }
        } else {
            ContentUnavailableView("Keine Folge gewählt.", systemImage: "film")
        }
    }

    @ViewBuilder private func qualitySection(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Qualitäten")
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textTertiary)
            let files = model.qualityFiles(episode)
            if model.qualityLoading.contains(episode.identifier) {
                ProgressView("lade die Qualitäten …")
                    .controlSize(.small)
            } else if files.isEmpty {
                Text("Mit „Qualität wählen“ werden die Qualitäten geladen.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                if let error = model.qualityErrors[episode.identifier] {
                    Text(error)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                }
                Button("Qualitäten laden") {
                    Task { await model.loadQualities(for: episode) }
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(file.desc)
                                .font(AppFont.subheading)
                                .foregroundStyle(Palette.textPrimary)
                            HStack(spacing: Space.s) {
                                Text(file.dimensions.isEmpty ? "-" : file.dimensions)
                                    .font(AppFont.digits)
                                    .foregroundStyle(Palette.textSecondary)
                                Text(AppFormat.bytes(file.size))
                                    .font(AppFont.digits)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Menu

    @ViewBuilder private func menu(for episode: Episode) -> some View {
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: format) }
        }
        Button(model.watchLabel(episode)) {
            model.navigationPath.append(.episode(episode, autoplay: true))
        }
        Button("Im Player-Fenster ansehen") {
            model.play([episode])
        }
        Button("Folge öffnen") {
            model.navigationPath.append(.episode(episode, autoplay: false))
        }
        if selection.count > 1 {
            Divider()
            Button("\(selection.count) markierte herunterladen") {
                Task { await model.downloadEpisodes(selectedEpisodes, of: format) }
            }
            Button("\(selection.count) markierte ansehen") {
                model.play(selectedEpisodes)
            }
            Button("\(selection.count) markierte als gesehen markieren") {
                Task {
                    for episode in selectedEpisodes {
                        await model.setWatched(episode, watched: true)
                    }
                }
            }
            Button("\(selection.count) markierte als ungesehen markieren") {
                Task {
                    for episode in selectedEpisodes {
                        await model.setWatched(episode, watched: false)
                    }
                }
            }
            Divider()
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
        Button("Qualität wählen") {
            qualityEpisode = episode
        }
        Button("Ähnliche Folgen") {
            model.navigationPath.append(.similar(episode))
        }
        if !episode.participants.isEmpty {
            Button("Gast öffnen") {
                openHost(episode)
            }
        }
        Button("Titel kopieren") {
            model.copyTitle(episode)
        }
        if model.isDownloaded(episode.identifier) {
            Divider()
            Button("Im Finder zeigen") {
                model.reveal(episode)
            }
            Button("Datei löschen …", role: .destructive) {
                deletedFile = episode
            }
        }
    }

    // MARK: Actions

    private var selectedEpisodes: [Episode] {
        displayedEpisodes.filter { selection.contains($0.identifier) }
    }

    /// The episode the inspector and the single actions work on.
    private var focusedEpisode: Episode? {
        if !selection.isEmpty {
            return displayedEpisodes.first { selection.contains($0.identifier) }
        }
        return displayedEpisodes.first
    }

    private func load() async {
        if model.currentFormat?.pid != format.pid {
            await model.openFormat(format)
        }
    }

    private func download() {
        if selection.isEmpty {
            confirmsAllDownload = true
            return
        }
        Task { await model.downloadEpisodes(selectedEpisodes, of: format) }
    }

    private func openHost(_ episode: Episode) {
        let guests = episode.participants
        if guests.count == 1, let participant = guests.first {
            model.navigationPath.append(.host(participant))
        } else {
            showsGuests = true
        }
    }
}
