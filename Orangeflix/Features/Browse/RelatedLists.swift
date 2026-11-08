import SwiftUI

/// The clips that belong to an episode (Go `openSimilar`, `app.Similar`).
struct SimilarScreen: View {
    let episode: Episode

    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(
                title: "Ähnliche Folgen",
                subtitle: "\(model.similarEpisodes.count) ähnliche Folgen",
                detail: BrowseLogic.title(of: episode),
                onBack: { if !model.navigationPath.isEmpty { model.navigationPath.removeLast() } }) { EmptyView() }
            BrowseClipListView(
                episodes: model.similarEpisodes,
                isLoading: model.similarLoading,
                loadingLabel: "Suche ähnliche Folgen …",
                emptyText: "Keine ähnlichen Folgen gefunden.",
                emptyDetail: "Wähle eine andere Folge, um ihre ähnlichen Folgen zu sehen.",
                errorText: model.similarError,
                selection: $selection)
        }
        .navigationTitle("")
        .task { await model.loadSimilar(for: episode) }
    }
}

/// Guests discovered in the episodes loaded during this session.
struct GuestDirectoryScreen: View {
    @Environment(BrowseModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: Space.l)]

    var body: some View {
        let guests = model.guestDirectory
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageChrome(title: "Alle Gäste", subtitle: "\(guests.count) Gäste", onBack: {
                    if !model.navigationPath.isEmpty { model.navigationPath.removeLast() }
                }) { EmptyView() }
                if model.guestDirectoryLoading && guests.isEmpty {
                    ProgressView("Lade alle Gäste …")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.xl)
                } else if guests.isEmpty {
                    if let error = model.guestDirectoryError {
                        ContentUnavailableView {
                            Label("Die Gästeliste konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Erneut versuchen") { Task { await model.loadGuestDirectory(force: true) } }
                                .glassButtonStyle()
                        }
                    } else {
                    EmptyState(symbol: "person.2", title: "Noch keine Gäste", message: "Gäste erscheinen hier, sobald Folgen geladen wurden.")
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                        ForEach(guests, id: \.id) { guest in
                            Button { model.navigationPath.append(.host(guest)) } label: {
                                VStack(spacing: Space.s) {
                                    DirectoryGuestPortrait(image: guest.image, size: 88)
                                    Text(guest.name.isEmpty ? "Unbekannter Gast" : guest.name)
                                        .font(AppFont.body)
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(Space.m)
                                .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                                        .strokeBorder(Palette.border.opacity(0.55), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.page)
                }
            }
            .padding(.bottom, Space.xxl)
        }
        .background(Palette.background)
        .navigationTitle("")
        .task { await model.loadGuestDirectory() }
    }
}

private struct DirectoryGuestPortrait: View {
    let image: String
    let size: CGFloat

    var body: some View {
        RemoteArt(url: EpisodeDetailLogic.imageURL(image), symbol: "person.fill")
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(Palette.border.opacity(0.6), lineWidth: 1) }
    }
}

/// The page of a guest (Go `openHost`, `app.Host`): a glass portrait, the
/// formats the guest appears in, and the episodes underneath.
struct HostScreen: View {
    let participant: Participant

    @Environment(BrowseModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 272, maximum: 300), spacing: Space.l, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageChrome(
                    title: name,
                    subtitle: episodeCountText,
                    onBack: back
                ) { EmptyView() }
                profile
                episodes
            }
            .padding(.bottom, Space.xxl)
        }
        .background(Palette.background)
        .navigationTitle("")
        .task(id: participant.id) { await model.loadHost(participant) }
    }

    private var page: HostPage? { model.hostPage(for: participant.id) }
    private var hostEpisodes: [Episode] { model.hostEpisodes(for: participant.id) }
    private var hostLoading: Bool { model.isLoadingHost(participant.id) }
    private var hostError: String? { model.hostError(for: participant.id) }

    private var name: String {
        let loaded = page?.host.name ?? ""
        return loaded.isEmpty ? participant.name : loaded
    }

    private var portrait: String {
        let loaded = page?.host.image ?? ""
        return loaded.isEmpty ? participant.image : loaded
    }

    private var about: String {
        let loaded = page?.host.description ?? ""
        return loaded.isEmpty ? participant.description : loaded
    }

    /// Loaded episodes, and the full count when the page knows more.
    private var episodeCountText: String {
        let loaded = hostEpisodes.count
        let total = page?.host.clipCount ?? page?.pagination.total ?? loaded
        if hostLoading && loaded == 0 { return "Lade den Gast …" }
        if total > loaded, loaded > 0 { return "\(loaded) von \(total) Folgen" }
        if total > 0 { return total == 1 ? "1 Folge" : "\(total) Folgen" }
        return loaded == 1 ? "1 Folge" : "\(loaded) Folgen"
    }

    private var profile: some View {
        HStack(alignment: .top, spacing: Space.l) {
            GuestPortrait(image: portrait, size: 112)
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel(text: "Gast", symbol: "person")
                if !about.isEmpty {
                    Text(about)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let magazines = page?.magazines, !magazines.isEmpty {
                    FlowLayout(spacing: Space.s) {
                        ForEach(magazines, id: \.pid) { magazine in
                            magazineChip(magazine)
                        }
                    }
                }
                if !socialLinks.isEmpty || headerLink != nil {
                    FlowLayout(spacing: Space.s) {
                        if let headerLink {
                            Link(destination: headerLink) {
                                glassChip(page?.headerText ?? "Webseite", symbol: "safari")
                            }
                        }
                        ForEach(socialLinks, id: \.key) { link in
                            Link(destination: link.url) {
                                glassChip(link.title, symbol: link.symbol)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.l)
        .glassPlate(in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .padding(.horizontal, Space.page)
    }

    private var headerLink: URL? {
        guard let text = page?.headerLink, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    private struct SocialLink: Identifiable {
        let key: String
        let title: String
        let symbol: String
        let url: URL
        var id: String { key }
    }

    private var socialLinks: [SocialLink] {
        guard let social = page?.host.social else { return [] }
        return social.compactMap { key, value in
            guard let url = URL(string: value), url.scheme != nil else { return nil }
            return SocialLink(key: key, title: Self.socialTitle(key), symbol: Self.socialSymbol(key), url: url)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @ViewBuilder private var episodes: some View {
        if hostLoading && hostEpisodes.isEmpty {
            ProgressView("Lade die Folgen …")
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xl)
        } else if hostEpisodes.isEmpty {
            if let error = hostError {
                ContentUnavailableView {
                    Label("Der Gast konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.loadHost(participant) } }
                        .glassButtonStyle()
                }
            } else if !hostLoading {
                EmptyState(
                    symbol: "person",
                    title: "Keine Folgen dieses Gasts.",
                    message: "Dieser Gast hat keine Folgen im Katalog.")
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Folgen", detail: "\(hostEpisodes.count)")
                    .padding(.horizontal, Space.page)
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                    ForEach(hostEpisodes, id: \.identifier) { episode in
                        episodeCard(episode)
                    }
                }
                .padding(.horizontal, Space.page)
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
            model.navigationPath.append(.episode(episode, autoplay: true))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.navigationPath.append(.episode(episode, autoplay: false))
        }
        .contextMenu { menu(for: episode) }
    }

    @ViewBuilder private func menu(for episode: Episode) -> some View {
        Button(model.watchLabel(episode)) {
            model.navigationPath.append(.episode(episode, autoplay: true))
        }
        Button("Folge öffnen") {
            model.navigationPath.append(.episode(episode, autoplay: false))
        }
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
        Button("Titel kopieren") { model.copyTitle(episode) }
        if model.isDownloaded(episode.identifier) {
            Button("Im Finder zeigen") { model.reveal(episode) }
        }
    }

    @ViewBuilder private func magazineChip(_ magazine: Magazine) -> some View {
        let title = magazine.title.isEmpty ? "Format" : magazine.title
        if model.format(pid: magazine.pid) != nil {
            Button {
                model.navigationPath.append(.episodes(pid: magazine.pid))
            } label: {
                glassChip(title, symbol: "rectangle.stack")
            }
            .buttonStyle(.plain)
            .help("Folgen von \(title)")
        } else {
            glassChip(title, symbol: "rectangle.stack")
        }
    }

    private func glassChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(AppFont.bodySmall)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 6)
            .glassPlate(in: Capsule(), interactive: true)
    }

    private func back() {
        model.navigationPath = [.guests]
    }

    private static func socialTitle(_ key: String) -> String {
        switch key.lowercased() {
        case "twitter", "x": "X"
        case "instagram": "Instagram"
        case "youtube": "YouTube"
        case "twitch": "Twitch"
        case "facebook": "Facebook"
        case "website", "web", "url", "homepage": "Webseite"
        default: key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    private static func socialSymbol(_ key: String) -> String {
        switch key.lowercased() {
        case "youtube": "play.rectangle"
        case "twitch": "gamecontroller"
        case "website", "web", "url", "homepage": "safari"
        default: "link"
        }
    }
}

/// A round portrait on liquid glass. Paths from the API ("/img/faces/…")
/// are completed to an address.
struct GuestPortrait: View {
    let image: String
    var size: CGFloat = 84

    var body: some View {
        RemoteArt(url: EpisodeDetailLogic.imageURL(image), symbol: "person.fill")
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(3)
            .glassPlate(in: Circle(), interactive: true)
    }
}

/// The whole Premium shelf of the Mediathek as a page.
struct PremiumListScreen: View {
    @Environment(BrowseModel.self) private var model

    @State private var selection: Set<String> = []
    @State private var qualityEpisode: Episode?

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(
                title: "Premium",
                subtitle: "\(model.premiumEpisodes.count) Folgen",
                onBack: { if !model.navigationPath.isEmpty { model.navigationPath.removeLast() } }) {
                MoreMenu {
                    Button("Neu laden") { Task { await model.loadPremium(force: true) } }
                }
            }
            BrowseClipListView(
                episodes: model.premiumEpisodes,
                isLoading: false,
                loadingLabel: "Lade Premium-Folgen …",
                emptyText: "Keine Premium-Folgen.",
                emptyDetail: "Neue Premium- und Vorab-Folgen erscheinen hier.",
                errorText: nil,
                selection: $selection,
                emptySymbol: "crown",
                onChooseQuality: { qualityEpisode = $0 })
        }
        .navigationTitle("")
        .sheet(isPresented: Binding(get: { qualityEpisode != nil }, set: { if !$0 { qualityEpisode = nil } })) {
            if let qualityEpisode { BrowseQualitySheet(episode: qualityEpisode) }
        }
    }
}

/// Every series of the Mediathek that has a new episode.
struct NewFormatsScreen: View {
    @Environment(BrowseModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: Space.l, alignment: .top)]

    var body: some View {
        let fresh = model.visibleFormats.filter(\.newEpisode)
        VStack(spacing: 0) {
            PageChrome(
                title: "Neu",
                subtitle: fresh.count == 1 ? "1 Format mit neuer Folge" : "\(fresh.count) Formate mit neuer Folge",
                onBack: { if !model.navigationPath.isEmpty { model.navigationPath.removeLast() } }) { EmptyView() }
            if fresh.isEmpty {
                EmptyState(symbol: "sparkles", title: "Nichts Neues.", message: "Formate mit neuen Folgen erscheinen hier.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                        ForEach(fresh, id: \.pid) { format in
                            Button { model.navigationPath.append(.episodes(pid: format.pid)) } label: {
                                FormatTile(format: format, count: model.episodeCountText(format))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.vertical, Space.l)
                }
                .background(Palette.background)
            }
        }
        .navigationTitle("")
    }
}
