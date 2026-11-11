import SwiftUI

// MARK: - Images

/// A picture from the network that fills its box. While it loads and when it
/// fails, a quiet surface with a symbol stands in. The pictures come from
/// `ImageCache`, so a start and a scroll back show them at once.
struct RemoteArt: View {
    let url: String
    var symbol = "film"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Palette.surfaceMuted
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if failed {
                placeholder
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            guard !url.isEmpty, let address = URL(string: url) else {
                failed = true
                return
            }
            let started = ContinuousClock.now
            let loaded = await ImageCache.shared.image(for: address)
            guard !Task.isCancelled else { return }
            let waited = ContinuousClock.now - started > .milliseconds(25)
            if waited && !reduceMotion {
                withAnimation(.easeOut(duration: 0.22)) {
                    image = loaded
                    failed = loaded == nil
                }
            } else {
                image = loaded
                failed = loaded == nil
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Palette.surfaceMuted
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// The square cover of a format, in the variant that fits the appearance.
struct FormatCover: View {
    let format: Format
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark && !format.coverDark.isEmpty
        RemoteArt(url: dark ? format.coverDark : format.cover, symbol: "tv")
    }
}

// MARK: - Poster

/// A format as a poster: the cover, the title and the state beneath it. The
/// poster lifts a little when the pointer is over it.
struct PosterCard: View {
    let format: Format
    let count: String
    let inLibrary: Bool

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { FormatCover(format: format) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.l)
                        .strokeBorder(hovering ? Palette.accent : Palette.border.opacity(0.6),
                                      lineWidth: hovering ? 2 : 1)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: Space.xs) {
                        if format.newEpisode {
                            BrandPill(text: "NEU", color: .white, background: Palette.accent)
                        }
                        if inLibrary {
                            Image(systemName: "books.vertical.fill")
                                .font(AppFont.caption)
                                .foregroundStyle(.white)
                                .padding(Space.xs)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                    }
                    .padding(Space.s)
                }
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 14 : 5, y: hovering ? 8 : 2)
                .scaleEffect(hovering ? 1.03 : 1)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(format.title)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(meta)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts: [String] = []
        if count != "-" { parts.append("\(count) Folgen") }
        if !format.lastEpisode.isEmpty { parts.append(format.lastEpisode) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Episode cards

/// The progress of an episode as a thin bar along the lower edge of its
/// picture.
struct WatchBar: View {
    /// 0…100
    let percent: Int

    var body: some View {
        if percent > 0 && percent < BrowseLogic.watchedPercent {
            Color.clear
                .frame(height: Space.xs)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.accent)
                        .scaleEffect(x: Double(percent) / 100, anchor: .leading)
                }
                .background(.black.opacity(0.5))
        }
    }
}

/// The picture of an episode in 16:9 with the progress and, on hover, the
/// play button and a short preview of five places in the episode.
struct EpisodeThumb: View {
    let episode: Episode
    let percent: Int
    var downloaded = false
    var onPlay: () -> Void

    @Environment(PlaybackCenter.self) private var playback: PlaybackCenter?
    @State private var hovering = false
    @State private var origin = UUID()

    private var preview: EpisodePreviewModel? { playback?.preview }
    private var active: Bool { preview.map { $0.identifier == episode.identifier && $0.origin == origin } ?? false }
    private var playing: Bool { active && preview?.canRender == true && preview?.isLoading == false }

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let preview, let playback, active {
                    EpisodePreviewSurface(episode: episode, preview: preview, playback: playback)
                } else {
                    RemoteArt(url: episode.thumb)
                }
            }
            .overlay {
                if hovering && !playing {
                    Color.black.opacity(0.35)
                }
            }
            .overlay(alignment: playing ? .bottomTrailing : .center) {
                if hovering {
                    Button {
                        preview?.stop()
                        onPlay()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: playing ? 12 : 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: playing ? 30 : 48, height: playing ? 30 : 48)
                            .background(Palette.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Ansehen")
                    // Above the segments while the preview runs.
                    .padding(.bottom, playing ? 22 : 0)
                    .padding(.trailing, playing ? Space.xs : 0)
                }
            }
            .overlay(alignment: .bottom) {
                if let preview, active, preview.mode == .hover, !preview.positions.isEmpty {
                    EpisodePreviewSegments(preview: preview)
                } else {
                    WatchBar(percent: percent)
                }
            }
            .overlay(alignment: .topLeading) {
                if let preview, playing {
                    EpisodePreviewClock(position: preview.position)
                } else if episode.isPremium || episode.isEarlyAccess {
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
                if active && preview?.isLoading == true {
                    ProgressView().controlSize(.small).tint(.white).padding(Space.xs)
                } else if active {
                    EmptyView()
                } else if downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(AppFont.heading)
                        .foregroundStyle(.white, Palette.success)
                        .padding(Space.s)
                        .help("heruntergeladen")
                } else if percent >= BrowseLogic.watchedPercent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.heading)
                        .foregroundStyle(.white, Palette.leaf)
                        .padding(Space.s)
                        .help("gesehen")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                guard let preview, let playback else { return }
                if inside {
                    if !preview.isDenied(episode.identifier) { preview.hover(episode, origin: origin, using: playback) }
                } else {
                    preview.leave(origin)
                }
            }
            .onDisappear {
                hovering = false
                preview?.leave(origin)
            }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.15), value: playing)
    }
}

/// An episode in a shelf: the picture, the title and the series beneath it.
struct EpisodeCard: View {
    let episode: Episode
    let percent: Int
    var downloaded = false
    var onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            EpisodeThumb(episode: episode, percent: percent, downloaded: downloaded, onPlay: onPlay)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(BrowseLogic.title(of: episode))
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 272)
    }

    private var subtitle: String {
        [episode.formatName, episode.duration].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// An episode in the list of a series: the picture on the left, the title,
/// the date, the description and the status next to it.
struct EpisodeRowCard: View {
    let episode: Episode
    let badge: BrowseEpisodeBadge
    let percent: Int
    var downloaded = false
    var bookmarked = false
    /// Search hits come from every series, so the series name belongs on the row.
    var showsFormat = false
    var onBookmark: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    var onPlay: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            EpisodeThumb(episode: episode, percent: percent, downloaded: downloaded, onPlay: onPlay)
                .frame(width: 192)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    if episode.number > 0 {
                        Text("\(episode.number)")
                            .font(AppFont.digitsMedium)
                            .foregroundStyle(Palette.accentText)
                    }
                    Text(BrowseLogic.title(of: episode))
                        .font(AppFont.heading)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                }
                Text(meta)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                if !episode.description.isEmpty {
                    Text(episode.description)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: Space.xs) {
                    BrowseBadgeView(badge: badge)
                    if bookmarked {
                        BrandPill(text: "Gemerkt", color: Palette.accentText, background: Palette.accentSoft)
                    }
                }
            }
            Spacer(minLength: 0)
            if onBookmark != nil || onDownload != nil {
                HStack(spacing: Space.xs) {
                    if let onBookmark {
                        rowAction(
                            symbol: bookmarked ? "bookmark.fill" : "bookmark",
                            help: bookmarked ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen",
                            tinted: bookmarked,
                            action: onBookmark)
                    }
                    if let onDownload {
                        rowAction(
                            symbol: downloaded ? "arrow.down.circle.fill" : "arrow.down.circle",
                            help: downloaded ? "Bereits geladen" : "Herunterladen",
                            tinted: downloaded,
                            action: onDownload)
                    }
                }
                .opacity(hovering || bookmarked ? 1 : 0)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(Space.m)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private func rowAction(symbol: String, help: String, tinted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tinted ? Palette.accentText : Palette.textSecondary)
                .frame(width: 32, height: 32)
                .background(Palette.surfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(Palette.border, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var meta: String {
        var parts: [String] = []
        if showsFormat, !episode.formatName.isEmpty { parts.append(episode.formatName) }
        parts.append(contentsOf: [BrowseEpisodeRow.dateText(episode.date), episode.duration])
        return parts.filter { !$0.isEmpty && $0 != "-" }.joined(separator: " · ")
    }
}

// MARK: - Shelves and hero

/// A horizontal shelf with a title, like the rows of Infuse. When the row
/// overflows the width, round arrow buttons sit on the picture so the row
/// can be paged without dragging.
/// "Alle 20 >" at the head of a shelf; it lights up under the pointer.
private struct ShelfShowAllButton: View {
    let count: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(hovering ? "Alle \(count)" : count)
                Image(systemName: "chevron.right")
                    .font(AppFont.micro)
            }
            .font(AppFont.caption)
            .foregroundStyle(hovering ? Palette.accentText : Palette.textTertiary)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background {
                if hovering { Capsule().fill(Palette.accentSoft) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Alle anzeigen: \(title)")
        .accessibilityLabel("Alle \(count) anzeigen: \(title)")
    }
}

struct Shelf<Content: View>: View {
    let title: String
    var trailing: String?
    /// Opens the whole list; the count and its arrow become a button.
    var onShowAll: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var geometry: ScrollGeometry?
    @State private var position = ScrollPosition(idType: Never.self)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title)
                    .font(AppFont.displaySmall)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Space.m)
                if let trailing {
                    if let onShowAll {
                        ShelfShowAllButton(count: trailing, title: title, action: onShowAll)
                    } else {
                        HStack(spacing: 2) {
                            Text(trailing)
                            Image(systemName: "chevron.right")
                                .font(AppFont.micro)
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Space.page)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Space.l) {
                    content
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self) { geo in
                geo
            } action: { _, geo in
                geometry = geo
            }
            .overlay(alignment: .topLeading) {
                if canScrollLeft {
                    scrollButton(systemName: "chevron.left", help: "Nach links scrollen") {
                        scroll(by: -1)
                    }
                    .padding(.leading, Space.m)
                    .padding(.top, ShelfMetrics.buttonTop)
                }
            }
            .overlay(alignment: .topTrailing) {
                if canScrollRight {
                    scrollButton(systemName: "chevron.right", help: "Nach rechts scrollen") {
                        scroll(by: 1)
                    }
                    .padding(.trailing, Space.m)
                    .padding(.top, ShelfMetrics.buttonTop)
                }
            }
            .animation(.easeOut(duration: 0.15), value: canScrollLeft)
            .animation(.easeOut(duration: 0.15), value: canScrollRight)
        }
    }

    private var canScrollLeft: Bool {
        guard let geometry else { return false }
        return geometry.contentOffset.x > 1
    }

    private var canScrollRight: Bool {
        guard let geometry else { return false }
        let limit = geometry.contentSize.width - geometry.containerSize.width
        return limit > 1 && geometry.contentOffset.x < limit - 1
    }

    /// One page, keeping a sliver of the previous card so the row still reads
    /// as a continuation.
    private func scroll(by direction: CGFloat) {
        guard let geometry else { return }
        let viewport = geometry.containerSize.width
        let limit = max(0, geometry.contentSize.width - viewport)
        let step = max(200, viewport * 0.75)
        let target = min(limit, max(0, geometry.contentOffset.x + direction * step))
        withAnimation(.easeOut(duration: 0.28)) {
            position.scrollTo(x: target)
        }
    }

    private func scrollButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.55), in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Layout numbers for `Shelf`. Kept outside the generic view, which cannot
/// store static properties.
private enum ShelfMetrics {
    /// The 16:9 picture is about 150 pt tall and the titles sit under it, so
    /// the arrow rests in the middle of the picture, not of the whole card.
    static let buttonTop: CGFloat = 66
}

/// The banner of a series with its title, a line of text and the actions,
/// laid over a gradient so the text stays readable on any picture.
struct HeroBanner<Actions: View>: View {
    let imageURL: String
    /// The height of the picture band.
    var height: CGFloat = Chrome.heroHeight
    let eyebrow: String?
    let title: String
    let meta: String
    let text: String
    /// Only the Mediathek supplies an image-derived page background.
    var backdrop: Color? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                RemoteArt(url: imageURL, symbol: "tv")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.0),
                        .init(color: .black.opacity(0.16), location: 0.62),
                        .init(color: .black.opacity(0.58), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0),
                        .init(color: .black.opacity(0.12), location: 0.18),
                        .init(color: .clear, location: 0.38),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) {
                if let backdrop {
                    // Ease into the page color over a broad band. The last
                    // part is fully opaque, so no image edge remains below.
                    // Keep this behind the title and actions.
                    LinearGradient(
                        stops: [
                            .init(color: backdrop.opacity(0), location: 0),
                            .init(color: backdrop.opacity(0.08), location: 0.2),
                            .init(color: backdrop.opacity(0.35), location: 0.45),
                            .init(color: backdrop.opacity(0.75), location: 0.7),
                            .init(color: backdrop, location: 0.94),
                            .init(color: backdrop, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: min(180, height * 0.48))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Space.s) {
                    if let eyebrow {
                        Text(eyebrow.uppercased())
                            .font(AppFont.captionMedium)
                            .tracking(1.2)
                            .foregroundStyle(Palette.accent)
                    }
                    Text(title)
                        .font(AppFont.hero)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if !text.isEmpty {
                        Text(text)
                            .font(AppFont.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                    HStack(spacing: Space.m) { actions }
                        .padding(.top, Space.xs)
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.xl)
            }
            .overlay(alignment: .bottom) {
                if backdrop == nil {
                    LinearGradient(
                        colors: [.clear, Palette.background],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
    }
}


/// A format as a wide tile: the banner in 16:9, the name and the episode count
/// beneath it. The home layout uses these instead of square posters.
struct FormatTile: View {
    let format: Format
    let count: String
    var inLibrary = false

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    RemoteArt(url: format.banner.isEmpty ? format.cover : format.banner, symbol: "tv")
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                .overlay(alignment: .topLeading) {
                    if format.newEpisode || inLibrary {
                        HStack(spacing: Space.xs) {
                            if format.newEpisode {
                                BrandPill(text: "NEU", color: .white, background: Palette.accent)
                            }
                            if inLibrary {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.black.opacity(0.58), in: Circle())
                                    .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                                    .help("In der Bibliothek")
                            }
                        }
                        .padding(Space.s)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.m)
                        .strokeBorder(hovering ? Palette.accent : .white.opacity(0.08),
                                      lineWidth: hovering ? 2 : 1)
                }
                .shadow(color: .black.opacity(hovering ? 0.3 : 0.12),
                        radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.02 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(format.title)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(meta)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }

    private var meta: String {
        var parts: [String] = []
        if count != "-" { parts.append("\(count) Folgen") }
        if !format.lastEpisode.isEmpty { parts.append(format.lastEpisode) }
        return parts.joined(separator: " · ")
    }
}
