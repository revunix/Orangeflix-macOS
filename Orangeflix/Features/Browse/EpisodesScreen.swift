import AppKit
import SwiftUI

/// The episodes of a format (Go `ScreenEpisodes`): the list grouped by year,
/// the year filter, the multiple selection and the actions of the episodes.
struct EpisodesScreen: View {
    /// The format whose episodes are shown.
    let format: Format

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []
    @State private var showsInspector = false
    @State private var qualityEpisode: Episode?
    @State private var confirmsAllDownload = false
    @State private var deletedFile: Episode?
    @State private var showsGuests = false
    /// True once the episodes scroll under the toolbar; the bar gets a
    /// fading scrim then.
    @State private var scrolledUnderTitlebar = false

    var body: some View {
        content
        .navigationTitle("")
        .inspector(isPresented: $showsInspector) { inspector }
        .task(id: app.accountGeneration) { await load() }
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
            Button("Alle \(model.visibleEpisodes.count) Folgen herunterladen", role: .destructive) {
                Task { await model.downloadEpisodes(model.visibleEpisodes, of: format) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Es ist keine Folge ausgewählt. Es werden alle \(model.visibleEpisodes.count) gefilterten Folgen geladen.")
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

    /// The same line the Mediathek hero shows: the newest episode and the count.
    private var heroMeta: String {
        var parts: [String] = []
        if !format.lastEpisode.isEmpty { parts.append("Letzte Folge \(format.lastEpisode)") }
        let count = model.visibleEpisodes.count
        if let year = model.yearFilter {
            parts.append("\(year) · \(count) Folgen")
        } else if count > 0 {
            parts.append("\(count) Folgen")
        } else if model.episodesLoading {
            parts.append(model.episodesLoadingLabel)
        }
        return parts.joined(separator: " · ")
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
        } else if model.visibleEpisodes.isEmpty {
            ContentUnavailableView("Keine Folge gefunden.", systemImage: "film")
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                ForEach(model.yearGroups) { group in
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionHeader(
                            title: group.year,
                            detail: "\(group.episodes.count) Folgen · \(group.loaded) geladen")
                        ForEach(group.episodes, id: \.identifier) { episode in
                            episodeRow(episode)
                        }
                    }
                    .padding(.horizontal, Space.page)
                }
            }
            .padding(.bottom, Space.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .background(Palette.background)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, distance in
            scrolledUnderTitlebar = distance > 12
        }
        .preference(key: TitlebarScrimKey.self, value: scrolledUnderTitlebar)
    }

    /// One episode. A click opens its page; the command key adds it to the
    /// selection; the play button on the picture opens the page and plays.
    private func episodeRow(_ episode: Episode) -> some View {
        let current = model.current(episode)
        return EpisodeRowCard(
            episode: current,
            badge: model.badge(episode),
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier)
        ) {
            model.navigationPath.append(.episode(episode, autoplay: true))
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(selection.contains(episode.identifier) ? Palette.accentSoft : .clear))
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

    /// The banner of the series with its title, its text and the actions.
    private var hero: some View {
        let inLibrary = model.libraryEntry(format.pid) != nil
        return HeroBanner(
            imageURL: format.banner,
            height: Chrome.heroHeight,
            eyebrow: format.newEpisode ? "Neue Folge" : (format.original ? "Eigenproduktion" : nil),
            title: format.title,
            meta: heroMeta,
            text: format.description
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
                BrowseEpisodeDetails(
                    episode: episode,
                    badge: model.badge(episode),
                    bookmarked: model.isBookmarked(episode),
                    percent: model.current(episode).progressPercent,
                    file: model.downloadedFile(episode.identifier))
                if !episode.description.isEmpty {
                    BrowseDescriptionText(text: episode.description)
                }
                if !episode.thumb.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Vorschaubild")
                            .font(AppFont.captionMedium)
                            .foregroundStyle(Palette.textTertiary)
                        Text(episode.thumb)
                            .font(AppFont.digits)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                    }
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

    @ViewBuilder private func actions(for episode: Episode) -> some View {
        Button("Herunterladen") {
            Task { await model.downloadEpisodes([episode], of: format) }
        }
        Button(model.watchLabel(episode)) {
            model.play([episode])
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
        model.visibleEpisodes.filter { selection.contains($0.identifier) }
    }

    /// The episode the inspector and the single actions work on.
    private var focusedEpisode: Episode? {
        if !selection.isEmpty {
            return model.visibleEpisodes.first { selection.contains($0.identifier) }
        }
        return model.visibleEpisodes.first
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

    private func watch() {
        let episodes = selection.isEmpty ? (focusedEpisode.map { [$0] } ?? []) : selectedEpisodes
        guard !episodes.isEmpty else { return }
        model.play(episodes)
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
