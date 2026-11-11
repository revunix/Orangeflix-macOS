import AppKit
import SwiftUI

/// The page of one episode. The player sits at the top and scrolls away
/// with the page; below it stands everything the API knows about the
/// episode: the text, the most watched places, the chapters, the guests,
/// the key words and the related episodes.
struct EpisodeDetailScreen: View {
    /// The episode as the list knew it; the page fills in the rest.
    let episode: Episode
    /// Starts the episode in the page when the page opens.
    var autoplay = false
    /// An explicit starting position, such as a chapter found in search.
    var startAt: Int?

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var browse
    @Environment(PlaybackCenter.self) private var playback
    @Environment(SharingModel.self) private var sharing

    @State private var page: EpisodeDetailModel
    @State private var didAutoplay = false
    /// The sheet of the page; only one stands open at a time.
    @State private var sheet: Sheet?

    /// The sheets of the episode page.
    private enum Sheet: Identifiable {
        /// The files of the episode.
        case quality(Episode)
        /// The sharing link that was created for this episode.
        case share(SharingLink)
        /// The editor of the chapters.
        case chapters

        var id: String {
            switch self {
            case .quality(let episode): "quality-\(episode.identifier)"
            case .share(let link): "share-\(link.code)"
            case .chapters: "chapters"
            }
        }
    }

    /// The width the picture gets; its height follows from it.
    @State private var stageWidth: CGFloat = 1100
    /// Measured inner width of the page, for switching between 1 and 2 columns.
    @State private var bodyWidth: CGFloat = 1000

    /// The widest the text of the page grows in single-column layout.
    private static let textWidth: CGFloat = 860
    /// The widest the two-column editorial body grows.
    private static let editorialMaxWidth: CGFloat = 1280
    /// The widest the picture grows; it fills the page when the window is
    /// wide enough.
    private static let stageWidth: CGFloat = 1280

    init(episode: Episode, autoplay: Bool = false, startAt: Int? = nil) {
        self.episode = episode
        self.autoplay = autoplay
        self.startAt = startAt
        _page = State(initialValue: EpisodeDetailModel(identifier: episode.identifier))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                stage
                    .padding(.horizontal, Space.page)
                    .padding(.top, Space.s)

                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.l) {
                        heading
                        actions
                        if let error = page.error, page.details == nil {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(AppFont.bodySmall)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                    editorialBody
                }
                .frame(maxWidth: usesTwoColumns ? Self.editorialMaxWidth : Self.textWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.page)

                if let similar = details?.similar, !similar.isEmpty {
                    similarShelf(similar)
                }
            }
            .padding(.bottom, Space.xxl)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { bodyWidth = $0 }
        }
        .hiddenScrollEdge()
        .background(Palette.background)
        .navigationTitle("")
        .preference(key: InlineStageVisibleKey.self, value: hostsInlineStage)
        .task {
            await page.load(app: app)
            if autoplay, !didAutoplay, !Task.isCancelled {
                didAutoplay = true
                play(from: startAt)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .quality(let episode):
                BrowseQualitySheet(episode: episode)
            case .share(let link):
                ShareLinkSheet(link: link)
            case .chapters:
                ChapterSuggestionSheet(categories: page.chapterCategories,
                                       initial: page.suggestedChapters) { chapters in
                    Task { await page.sendChapterSuggestion(app: app, chapters: chapters) }
                }
            }
        }
    }

    // MARK: State

    /// The episode with what the clip page added.
    private var shown: Episode {
        guard let clip = page.details?.clip, !clip.id.isEmpty else { return browse.current(episode) }
        var merged = clip.episode
        if merged.thumb.isEmpty { merged.thumb = episode.thumb }
        return browse.current(merged)
    }

    private var details: EpisodeDetails? { page.details }

    /// True when this page wants to own the inline video slot (unless manual PiP is active).
    private var hostsInlineStage: Bool {
        playback.isInline && playback.isPlaying && playback.current?.identifier == episode.identifier && !playback.manualPiP
    }

    /// Whether the picture of this episode currently renders inside this page's stage.
    private var playsHere: Bool {
        hostsInlineStage && !playback.isInPiP
    }

    /// Whether this episode is currently floating in native Picture-in-Picture.
    private var playsInPiP: Bool {
        playback.isInPiP && playback.current?.identifier == episode.identifier
    }

    /// Whether this episode plays in the player window.
    private var playsInWindow: Bool {
        !playback.isInline && playback.isPlaying && playback.current?.identifier == episode.identifier
    }

    private var isStarting: Bool { playback.preparingIdentifier == episode.identifier }

    /// The place the account stopped at, when it is worth resuming.
    private var resumeSeconds: Int? {
        let position = page.insights?.progress.lastPosition ?? 0
        let duration = shown.durationSeconds
        guard position > 10, duration == 0 || position < duration - 30 else { return nil }
        return position
    }

    private var canWatch: Bool { details?.clip.canAccess ?? true }

    private var hasHeatmap: Bool {
        guard let heatmap = page.insights?.heatmap else { return false }
        return heatmap.count > 1 && shown.durationSeconds > 0
    }

    private var nonEmptyChapterSections: [EpisodeDetails.ChapterSection] {
        (details?.chapterSections ?? []).filter { !$0.chapters.isEmpty }
    }

    private var hasChapters: Bool { !nonEmptyChapterSections.isEmpty }

    private var hasTimelineColumn: Bool {
        hasHeatmap || hasChapters || showsStandaloneChapterPrompt
    }

    private var showsStandaloneChapterPrompt: Bool {
        guard !hasChapters, let context = page.chapterContext else { return false }
        return context.canSubmit || context.openSuggestion != nil || context.lastDecision != nil
    }

    private var usesTwoColumns: Bool {
        bodyWidth >= 940 && hasTimelineColumn
    }

    private func play(from seconds: Int?) {
        playback.playInline(shown, from: seconds)
    }

    /// Jumps to `seconds`: inside the running picture, else it starts there.
    private func jump(to seconds: Double) {
        if playsHere {
            playback.seek(to: seconds, exact: true)
        } else {
            play(from: Int(seconds))
        }
    }

    // MARK: Navigation

    private var canOpenFormat: Bool {
        shown.pid > 0 && browse.format(pid: shown.pid) != nil
    }

    private func openSeries() {
        guard shown.pid > 0 else { return }
        if browse.navigationPath.count >= 2,
           case .episodes(let pid) = browse.navigationPath[browse.navigationPath.count - 2],
           pid == shown.pid {
            browse.navigationPath.removeLast()
        } else {
            browse.navigationPath.append(.episodes(pid: shown.pid))
        }
    }

    // MARK: Stage

    /// The picture of the episode in 16:9, as wide as the page allows. The
    /// size is fixed, so the picture never takes the height of the window
    /// and the page keeps its proportions.
    private var stage: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, Self.stageWidth)
            ZStack {
                if playsHere {
                    PlayerScreen(playback: playback, inline: true)
                } else {
                    poster
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .strokeBorder(Palette.divider, lineWidth: 1)
            }
            // The shadow sits behind the picture. A shadow on the picture
            // itself would photograph the OpenGL layer on every scroll step.
            .background {
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { value in
                guard abs(value - stageWidth) > 1 else { return }
                stageWidth = value
            }
        }
        .frame(height: min(stageWidth, Self.stageWidth) * 9 / 16)
    }

    /// The picture of the episode with the way to start it. The picture is
    /// the wide one of the API; the tall poster would fill the frame and
    /// crop the episode.
    private var poster: some View {
        ZStack {
            Color.black
            RemoteArt(url: posterURL)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            posterCenter
        }
        .environment(\.colorScheme, .dark)
    }

    /// The wide picture of the episode; the tall poster only when there is
    /// nothing else.
    private var posterURL: String {
        let images = details?.clip.images
        if let thumb = images?.thumbnail, !thumb.isEmpty { return thumb }
        if let image = details?.clip.image, !image.isEmpty { return image }
        if !shown.thumb.isEmpty { return shown.thumb }
        return images?.poster ?? ""
    }

    @ViewBuilder private var posterCenter: some View {
        if isStarting {
            ProgressView().controlSize(.large)
        } else if playsInPiP {
            VStack(spacing: Space.m) {
                Label("Läuft im Bild-in-Bild", systemImage: "pip")
                    .font(AppFont.heading)
                    .foregroundStyle(.white)
                PillButton(title: "Hier weitersehen", symbol: "pip.exit", style: .onPicture) {
                    playback.exitPiP()
                }
            }
        } else if playsInWindow {
            VStack(spacing: Space.m) {
                Label("Läuft im Player-Fenster", systemImage: "macwindow")
                    .font(AppFont.heading)
                    .foregroundStyle(.white)
                PillButton(title: "Hier abspielen", symbol: "rectangle.inset.filled", style: .onPicture) {
                    playback.pullIn()
                }
            }
        } else if !canWatch {
            VStack(spacing: Space.s) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Für diese Folge fehlt der Zugang.")
                    .font(AppFont.heading)
                    .foregroundStyle(.white)
                if let details, details.canPurchaseSingle, !details.priceFormatted.isEmpty {
                    Text("Einzeln erhältlich für \(details.priceFormatted)")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        } else {
            Button { play(from: resumeSeconds) } label: {
                VStack(spacing: Space.m) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 3)
                        .frame(width: 84, height: 84)
                        .background(Palette.accent, in: Circle())
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                    Text(watchTitle)
                        .font(AppFont.heading)
                        .foregroundStyle(.white)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(watchTitle)
        }
    }

    private var watchTitle: String {
        if let resumeSeconds { return "Weiter bei \(AppFormat.position(Double(resumeSeconds)))" }
        return "Ansehen"
    }

    // MARK: Heading and actions

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            metaHeader
            Text(BrowseLogic.title(of: shown))
                .font(AppFont.hero)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let short = details?.clip.shortDescription, !short.isEmpty,
               short != details?.clip.description {
                Text(short)
                    .font(AppFont.heading)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            badges
        }
    }

    /// Clickable series link followed by episode number, date and duration.
    private var metaHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if !shown.formatName.isEmpty {
                if canOpenFormat {
                    Button(action: openSeries) {
                        HStack(spacing: 3) {
                            Text(shown.formatName)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .help("Alle Folgen von \(shown.formatName)")
                } else {
                    Text(shown.formatName)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.accentText)
                }
            }
            if !metaRest.isEmpty {
                if !shown.formatName.isEmpty {
                    Text("·")
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textTertiary)
                }
                Text(metaRest)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var metaRest: String {
        var parts: [String] = []
        if shown.number > 0 { parts.append("Folge \(shown.number)") }
        parts.append(BrowseEpisodeRow.dateText(shown.date))
        parts.append(shown.duration)
        return parts.filter { !$0.isEmpty && $0 != "-" }.joined(separator: " · ")
    }

    private var badges: some View {
        HStack(spacing: Space.xs) {
            BrowseBadgeView(badge: browse.badge(shown))
            if details?.clip.isPremium == true { BrandPill(text: "Premium") }
            if details?.clip.isEarlyAccess == true { BrandPill(text: "Vorab") }
            if details?.hasClosedCaptions == true || page.insights?.hasSubtitles == true {
                BrandPill(text: "Untertitel")
            }
            if !(details?.clip.categoryTitle ?? "").isEmpty { BrandPill(text: details?.clip.categoryTitle ?? "") }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.s) {
            if canWatch, !playsHere {
                PillButton(title: watchTitle, symbol: "play.fill", style: .accent) { play(from: resumeSeconds) }
            }
            Button(browse.isBookmarked(shown) ? "Gemerkt" : "Merken",
                   systemImage: browse.isBookmarked(shown) ? "bookmark.fill" : "bookmark") {
                Task { await browse.toggleBookmark(shown) }
            }
            .help(browse.isBookmarked(shown) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen")
            Button(browse.isWatched(shown) ? "Gesehen" : "Als gesehen markieren",
                   systemImage: browse.isWatched(shown) ? "checkmark.circle.fill" : "checkmark.circle") {
                Task { await browse.toggleWatched([shown]) }
            }
            Menu {
                Button("In der eingestellten Qualität laden") {
                    Task { await browse.downloadEpisodes([shown], of: browse.format(pid: shown.pid)) }
                }
                Button("Qualität wählen …") { sheet = .quality(shown) }
            } label: {
                Label(browse.isDownloaded(shown.identifier) ? "Geladen" : "Herunterladen",
                      systemImage: browse.isDownloaded(shown.identifier) ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
            .menuStyle(.button)
            Spacer(minLength: 0)
            moreMenu
        }
        .glassButtonStyle()
        .controlSize(.large)
    }

    private var moreMenu: some View {
        Menu {
            if playsHere {
                Button("Im Player-Fenster abspielen") { playback.popOut() }
            } else {
                Button("Im Player-Fenster abspielen") { browse.play([shown]) }
            }
            if let url = forumURL {
                Link("Im Forum besprechen", destination: url)
            }
            Button("Ähnliche Folgen") { browse.navigationPath.append(.similar(shown)) }
            Divider()
            if browse.isWatched(shown) {
                Button("Als ungesehen markieren") {
                    Task { await browse.setWatched(shown, watched: false) }
                }
            } else {
                Button("Als gesehen markieren") {
                    Task { await browse.setWatched(shown, watched: true) }
                }
                Button("Als ungesehen markieren") {
                    Task { await browse.setWatched(shown, watched: false) }
                }
            }
            if canWatch {
                Divider()
                Button("Link zum Teilen erstellen") {
                    Task { await createShareLink() }
                }
            }
            Divider()
            Button("Titel kopieren") { browse.copyTitle(shown) }
            Button("Kennung kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shown.identifier, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("Weitere Aktionen")
        .accessibilityLabel("Weitere Aktionen")
    }

    private var forumURL: URL? {
        guard let text = details?.commentsURL, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// Creates a sharing link for this episode and shows it.
    private func createShareLink() async {
        guard let link = await sharing.create(for: shown.identifier) else { return }
        sheet = .share(link)
    }

    // MARK: Editorial body

    @ViewBuilder private var editorialBody: some View {
        if usesTwoColumns {
            HStack(alignment: .top, spacing: Space.xxl) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                timelineColumn
                    .frame(width: min(440, max(340, bodyWidth * 0.38)), alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.xl) {
                leftColumn
                if hasTimelineColumn {
                    timelineColumn
                }
            }
        }
    }

    @ViewBuilder private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let text = details?.clip.description, !text.isEmpty {
                section("Inhalt") {
                    Text(text)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if !shown.participants.isEmpty {
                section("Gäste", detail: "\(shown.participants.count)") { guests }
            }
            if let words = details?.keywords, !words.isEmpty {
                section("Schlagworte") { keywords(words) }
            }
            if let next = details?.nextIdentifier, !next.isEmpty {
                section("Weiter in \(shown.formatName.isEmpty ? "der Serie" : shown.formatName)") {
                    nextCard(next)
                }
            }
        }
    }

    @ViewBuilder private var timelineColumn: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(timelineHeading)
                    .font(AppFont.displaySmall)
                    .foregroundStyle(Palette.textPrimary)
                if hasChapters {
                    Text("\(details?.chapters.count ?? 0)")
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                chapterHeaderAccessory
            }

            VStack(alignment: .leading, spacing: Space.l) {
                if let heatmap = page.insights?.heatmap, heatmap.count > 1, shown.durationSeconds > 0 {
                    EpisodeHeatmap(heatmap: heatmap, duration: shown.durationSeconds,
                                   position: playsHere ? playback.position : nil, onJump: jump)
                }
                if hasHeatmap && hasChapters {
                    Hairline()
                }
                if hasChapters {
                    chapterList(nonEmptyChapterSections)
                } else if showsStandaloneChapterPrompt {
                    chapterSuggestionBanner
                }
            }
            .padding(Space.l)
            .contentCard()
        }
    }

    private var timelineHeading: String {
        if hasHeatmap && hasChapters { return "Zeitverlauf & Kapitel" }
        if hasChapters { return "Kapitel" }
        return "Meistgesehen"
    }

    private func section<Content: View>(_ title: String, detail: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: title, detail: detail)
            content()
        }
    }

    // MARK: Chapters

    /// Subtle header control for suggesting or viewing the status of chapter suggestions.
    @ViewBuilder private var chapterHeaderAccessory: some View {
        if let context = page.chapterContext {
            if context.canSubmit {
                Button {
                    sheet = .chapters
                } label: {
                    Label("Kapitel vorschlagen", systemImage: "square.and.pencil")
                        .font(AppFont.captionMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 4)
                        .glassPlate(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .help("Eigene Kapitel für diese Folge vorschlagen")
            } else if context.openSuggestion != nil {
                BrandPill(text: "Vorschlag offen", color: Palette.accentText, background: Palette.accentSoft)
            } else if let decision = context.lastDecision {
                BrandPill(
                    text: decision.isAccepted ? "Angenommen" : "Abgelehnt",
                    color: decision.isAccepted ? Palette.success : Palette.textSecondary,
                    background: decision.isAccepted ? Palette.successSoft : Palette.surfaceMuted)
            }
        }
    }

    @ViewBuilder private var chapterSuggestionBanner: some View {
        if let context = page.chapterContext {
            VStack(alignment: .leading, spacing: Space.s) {
                if context.canSubmit {
                    Text("Für diese Folge liegen noch keine Kapitel vor. Du kannst eigene Kapitel vorschlagen.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Kapitel vorschlagen") { sheet = .chapters }
                        .glassButtonStyle()
                } else if context.openSuggestion != nil {
                    Label("Dein Kapitel-Vorschlag wartet auf die Entscheidung.", systemImage: "clock")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                } else if let decision = context.lastDecision {
                    Label(decision.isAccepted ? "Dein Vorschlag wurde angenommen." : "Dein Vorschlag wurde abgelehnt.",
                          systemImage: decision.isAccepted ? "checkmark.circle" : "xmark.circle")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func chapterList(_ sections: [EpisodeDetails.ChapterSection]) -> some View {
        let running = playsHere ? PlaybackChapter.current(details?.chapters ?? [], at: playback.position) : nil
        return VStack(alignment: .leading, spacing: Space.m) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 2) {
                    if !section.title.isEmpty {
                        SectionLabel(text: section.title)
                            .padding(.bottom, Space.xs)
                    }
                    ForEach(section.chapters) { chapter in
                        ChapterRow(chapter: chapter, isRunning: running?.id == chapter.id) {
                            jump(to: chapter.start)
                        }
                    }
                }
            }
        }
    }

    // MARK: Guests and words

    private var guests: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Space.l) {
                ForEach(shown.participants, id: \.id) { guest in
                    Button {
                        browse.navigationPath.append(.host(guest))
                    } label: {
                        VStack(spacing: Space.s) {
                            GuestPortrait(image: guest.image, size: 80)
                            Text(guest.name)
                                .font(AppFont.subheading)
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 98)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Alle Folgen mit \(guest.name)")
                }
            }
        }
    }

    private func keywords(_ words: [String]) -> some View {
        FlowLayout(spacing: Space.s) {
            ForEach(words, id: \.self) { word in
                Button {
                    browse.searchText = word
                    browse.searchPath = []
                    app.selection = .search
                } label: {
                    Label(word, systemImage: "magnifyingglass")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, 6)
                        .glassPlate(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .help("Nach „\(word)“ suchen")
            }
        }
    }

    // MARK: Related

    /// Resolves the richest metadata known for `nextIdentifier` and presents a
    /// real media preview card instead of a bare button.
    private func resolvedNextEpisode(_ identifier: String) -> Episode {
        if let loaded = page.nextEpisode, loaded.identifier == identifier {
            return browse.current(loaded)
        }
        if let inFormat = browse.episodes.first(where: { $0.identifier == identifier }) {
            return browse.current(inFormat)
        }
        if let inSimilar = details?.similar.first(where: { $0.id == identifier })?.episode {
            return browse.current(inSimilar)
        }
        var fallback = Episode()
        fallback.identifier = identifier
        fallback.pid = shown.pid
        fallback.formatName = shown.formatName
        return fallback
    }

    private func nextCard(_ identifier: String) -> some View {
        let next = resolvedNextEpisode(identifier)
        let hasDetails = !next.title.isEmpty || !next.thumb.isEmpty
        return Group {
            if hasDetails {
                HStack(alignment: .center, spacing: Space.l) {
                    EpisodeThumb(
                        episode: next,
                        percent: next.progressPercent,
                        downloaded: browse.isDownloaded(next.identifier)
                    ) {
                        browse.navigationPath.append(.episode(next, autoplay: true))
                    }
                    .frame(width: 176)

                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(nextMeta(next))
                            .font(AppFont.captionMedium)
                            .tracking(0.6)
                            .foregroundStyle(Palette.accentText)
                        Text(BrowseLogic.title(of: next))
                            .font(AppFont.heading)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        if !next.description.isEmpty {
                            Text(next.description)
                                .font(AppFont.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(Space.m)
                .contentCard()
                .contentShape(Rectangle())
                .onTapGesture {
                    browse.navigationPath.append(.episode(next, autoplay: false))
                }
            } else {
                Button("Nächste Folge öffnen", systemImage: "arrow.right.circle") {
                    browse.navigationPath.append(.episode(next, autoplay: false))
                }
                .glassButtonStyle()
                .controlSize(.large)
            }
        }
    }

    private func nextMeta(_ episode: Episode) -> String {
        var parts: [String] = []
        if episode.number > 0 { parts.append("FOLGE \(episode.number)") }
        let day = BrowseEpisodeRow.dateText(episode.date)
        if day != "-" { parts.append(day) }
        if !episode.duration.isEmpty { parts.append(episode.duration) }
        return parts.isEmpty ? "NÄCHSTE FOLGE" : parts.joined(separator: " · ")
    }

    private func similarShelf(_ hits: [SearchResult]) -> some View {
        Shelf(
            title: "Ähnliche Folgen",
            trailing: "\(hits.count)",
            onShowAll: { browse.navigationPath.append(.similar(shown)) }
        ) {
            ForEach(hits, id: \.id) { hit in
                let other = browse.current(hit.episode)
                Button {
                    browse.navigationPath.append(.episode(hit.episode, autoplay: false))
                } label: {
                    EpisodeCard(episode: other, percent: other.progressPercent,
                                downloaded: browse.isDownloaded(other.identifier)) {
                        browse.navigationPath.append(.episode(hit.episode, autoplay: true))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pieces

/// The sharing link that was created; it may be copied and given to
/// somebody.
private struct ShareLinkSheet: View {
    let link: SharingLink

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Link zum Teilen")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text("Wer den Link öffnet, kann die Folge ohne Konto ansehen. Der Link ist auf \(link.accessLimit) Aufrufe begrenzt.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(link.url.isEmpty ? link.code : link.url)
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            HStack {
                Button("Link kopieren") {
                    AppFormat.copy(link.url.isEmpty ? link.code : link.url)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 420)
        .background(Palette.surfaceRaised)
    }
}

/// The editor of the chapters of an episode: the name, the beginning, the
/// end and the category of every chapter.
private struct ChapterSuggestionSheet: View {
    /// The categories a chapter may carry.
    let categories: [ChapterCategory]
    /// The chapters the editor starts from.
    let initial: [SuggestedChapter]
    /// Hands the chapters to the caller and closes the sheet.
    let send: ([SuggestedChapterBody]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chapters: [Draft] = []

    /// One chapter while it is being edited.
    private struct Draft: Identifiable {
        var id = UUID()
        var title = ""
        var start = ""
        var end = ""
        var category = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Kapitel vorschlagen")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text("Der Server nimmt deine Kapitel an, wenn sie passen. Ein Vorschlag ersetzt einen früheren.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            list
            HStack {
                Button("Kapitel hinzufügen") { addChapter() }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Senden", action: sendChapters)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 520, minHeight: 420)
        .background(Palette.surfaceRaised)
        .onAppear(perform: fill)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Space.s) {
                ForEach($chapters) { $chapter in
                    HStack(spacing: Space.s) {
                        TextField("Titel", text: $chapter.title, prompt: Text("Titel"))
                            .textFieldStyle(.roundedBorder)
                        TextField("Start", text: $chapter.start, prompt: Text("0:00"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("Ende", text: $chapter.end, prompt: Text("0:00"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        if categories.isEmpty {
                            EmptyView()
                        } else {
                            Picker("", selection: $chapter.category) {
                                Text("Ohne").tag("")
                                ForEach(categories) { category in
                                    Text(category.label).tag(category.key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        Button {
                            chapters.removeAll { $0.id == chapter.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Das Kapitel entfernen")
                    }
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    /// Whether every chapter has a name, a beginning and an end.
    private var isComplete: Bool {
        !chapters.isEmpty && chapters.allSatisfy { chapter in
            !chapter.title.trimmingCharacters(in: .whitespaces).isEmpty
                && !chapter.start.trimmingCharacters(in: .whitespaces).isEmpty
                && !chapter.end.trimmingCharacters(in: .whitespaces).isEmpty
                && Self.seconds(chapter.end) > Self.seconds(chapter.start)
        }
    }

    /// Fills the editor with the chapters the episode has.
    private func fill() {
        guard chapters.isEmpty else { return }
        chapters = initial.map { chapter in
            Draft(title: chapter.title,
                  start: AppFormat.position(chapter.start),
                  end: AppFormat.position(chapter.end),
                  category: chapter.category)
        }
    }

    /// Adds an empty chapter at the end.
    private func addChapter() {
        let last = chapters.last.map { Self.seconds($0.end) } ?? 0
        chapters.append(Draft(title: "", start: AppFormat.position(last),
                              end: AppFormat.position(last + 60), category: ""))
    }

    /// Hands the chapters to the caller.
    private func sendChapters() {
        let bodies = chapters.map { chapter in
            SuggestedChapterBody(title: chapter.title.trimmingCharacters(in: .whitespaces),
                                 start: Self.seconds(chapter.start),
                                 end: Self.seconds(chapter.end),
                                 category: chapter.category.isEmpty ? nil : chapter.category)
        }
        send(bodies)
        dismiss()
    }

    /// The seconds of a "m:ss" or "h:mm:ss" text.
    private static func seconds(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 0: return 0
        case 1: return parts[0]
        case 2: return parts[0] * 60 + parts[1]
        default: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
    }
}

/// One chapter: the start, the title and the length. The running one is
/// marked; a click jumps there.
private struct ChapterRow: View {
    let chapter: PlaybackChapter
    let isRunning: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: isRunning ? "speaker.wave.2.fill" : (hovering ? "play.fill" : "circle.fill"))
                    .font(.system(size: isRunning || hovering ? 10 : 5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 14)
                Text(AppFormat.position(chapter.start))
                    .font(AppFont.digitsMedium)
                    .foregroundStyle(Palette.accentText)
                    .frame(minWidth: 52, alignment: .leading)
                Text(chapter.title)
                    .font(isRunning ? AppFont.subheading : AppFont.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Space.s)
                Text(EpisodeDetailLogic.length(chapter))
                    .font(AppFont.digits)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(isRunning ? Palette.accentSoft : (hovering ? Palette.textPrimary.opacity(0.05) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ab \(AppFormat.position(chapter.start)) ansehen")
    }
}

/// How often each part of the episode was watched, as bars over the length
/// of the episode, with the most watched places as jumps below. A click on
/// the bars starts the episode there.
private struct EpisodeHeatmap: View {
    let heatmap: [Double]
    let duration: Int
    /// The position of the running picture, nil when it does not play here.
    let position: Double?
    let onJump: (Double) -> Void

    @State private var hover: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: "Meistgesehen", symbol: "chart.bar.xaxis")
            bars
            HStack {
                Text("0:00")
                Spacer()
                Text(AppFormat.position(Double(duration)))
            }
            .font(AppFont.digits)
            .foregroundStyle(Palette.textTertiary)

            let peaks = EpisodeDetailLogic.peaks(heatmap, duration: duration)
            if !peaks.isEmpty {
                FlowLayout(spacing: Space.xs) {
                    Text("Beliebteste Stellen:")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.vertical, 4)
                    ForEach(peaks, id: \.self) { seconds in
                        Button(AppFormat.position(Double(seconds)), systemImage: "play.fill") {
                            onJump(Double(seconds))
                        }
                        .font(AppFont.digitsMedium)
                        .controlSize(.small)
                    }
                }
                .glassButtonStyle()
                .padding(.top, Space.xxs)
            }
        }
    }

    private var bars: some View {
        GeometryReader { geo in
            let peak = max(heatmap.max() ?? 1, 0.0001)
            let width = geo.size.width / CGFloat(heatmap.count)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(heatmap.enumerated()), id: \.offset) { _, value in
                        let ratio = max(0, min(1, value / peak))
                        UnevenRoundedRectangle(
                            topLeadingRadius: 2, bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0, topTrailingRadius: 2,
                            style: .continuous)
                            .fill(Palette.accent.opacity(0.22 + 0.78 * ratio))
                            .frame(width: max(width - 1, 1), height: max(geo.size.height * ratio, 2))
                            .frame(width: width, alignment: .bottom)
                    }
                }
                Hairline()
                if let position, duration > 0 {
                    Rectangle()
                        .fill(Palette.textPrimary)
                        .frame(width: 2)
                        .offset(x: geo.size.width * min(position / Double(duration), 1) - 1)
                }
                if let hover {
                    Rectangle()
                        .fill(Palette.textPrimary.opacity(0.55))
                        .frame(width: 1)
                        .offset(x: geo.size.width * hover)
                    Text(AppFormat.position(hover * Double(duration)))
                        .font(AppFont.digitsMedium)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, 2)
                        .background(Palette.surfaceRaised, in: Capsule())
                        .overlay { Capsule().strokeBorder(Palette.border, lineWidth: 1) }
                        .offset(x: min(max(geo.size.width * hover - 24, 0), geo.size.width - 56), y: -geo.size.height - 6)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    hover = min(max(point.x / geo.size.width, 0), 1)
                } else {
                    hover = nil
                }
            }
            .onTapGesture { point in
                onJump(Double(min(max(point.x / geo.size.width, 0), 1)) * Double(duration))
            }
        }
        .frame(height: 52)
        .padding(.top, Space.m)
        .help("Wie oft welche Stelle gesehen wurde; ein Klick spielt ab dort")
    }
}
