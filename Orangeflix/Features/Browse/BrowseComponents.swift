import SwiftUI
import AppKit

// MARK: - Inspector

/// The inspector of the Browse screens: the title of the item, the quiet
/// heading "Angaben" and the fields below.
struct BrowseInspector<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title)
                    .font(AppFont.heading)
                    .foregroundStyle(Palette.textPrimary)
                Text("Angaben")
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textTertiary)
                VStack(alignment: .leading, spacing: Space.s) {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
        }
        .background(Palette.surfaceRaised)
    }
}

/// The description of a format or an episode in the inspector.
struct BrowseDescriptionText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Beschreibung")
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textTertiary)
            Text(text)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
        }
    }
}

/// The fields of an episode in the inspector (Go `episodeDetails`).
struct BrowseEpisodeDetails: View {
    let episode: Episode
    let badge: BrowseEpisodeBadge
    let bookmarked: Bool
    let percent: Int
    /// The downloaded file, when the episode is on the disk.
    var file: URL?
    /// The search shows neither the date nor the guests.
    var showsDate = true
    var showsGuests = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BrowseDetailRow(label: "Nummer", value: "\(episode.number)")
            BrowseDetailRow(label: "Kennung", value: episode.identifier)
            if showsDate {
                BrowseDetailRow(label: "Datum", value: BrowseEpisodeRow.dateText(episode.date))
            }
            BrowseDetailRow(label: "Länge", value: episode.duration.isEmpty ? "-" : episode.duration)
            if !episode.formatName.isEmpty {
                BrowseDetailRow(label: "Format", value: episode.formatName)
            }
            BrowseDetailRow(label: "Status", value: badge.label)
            BrowseDetailRow(label: "Merkliste", value: bookmarked ? "ja" : "nein")
            if percent > 0 {
                BrowseDetailRow(label: "Gesehen", value: "\(percent) %")
            }
            if showsGuests, !episode.participants.isEmpty {
                BrowseDetailRow(
                    label: "Gäste",
                    value: episode.participants.map(\.name).joined(separator: ", "))
            }
            if let file {
                BrowseDetailRow(label: "Datei", value: AppFormat.displayPath(file))
            }
        }
    }
}

// MARK: - Rows

/// One field of the inspector (the "Angaben" box of the TUI).
struct BrowseDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        BrandDetailRow(label: label, value: value)
    }
}

/// The status of an episode (the "STATUS" column of the TUI).
struct BrowseBadgeView: View {
    let badge: BrowseEpisodeBadge

    var body: some View {
        BrandPill(text: badge.label, color: color, background: background)
    }

    private var color: Color {
        switch badge {
        case .downloaded: Palette.success
        case .watched: Palette.leaf
        case .progress: Palette.info
        case .new: Palette.accentText
        case .open: Palette.textSecondary
        }
    }

    private var background: Color {
        switch badge {
        case .downloaded: Palette.successSoft
        case .watched: Palette.leafSoft
        case .progress: Palette.infoSoft
        case .new: Palette.accentSoft
        case .open: Palette.surfaceMuted
        }
    }
}

/// The measures of one episode row (the layout caches them).
struct BrowseRowMetrics: Sendable {
    var width: CGFloat = 0
    var number = CGSize.zero
    var title = CGSize.zero
    var date = CGSize.zero
    var status = CGSize.zero
    var length = CGSize.zero
    var narrow = false
    var titleWidth: CGFloat = 0
    var height: CGFloat = 0
}

/// The arrangement of an episode row: the number on the left, the title in
/// the middle, the date and the status on the right. When the row gets
/// narrow, the length moves under the title instead of standing in a
/// column of its own.
struct BrowseEpisodeRowLayout: Layout {
    /// The space between the pieces of the row.
    var spacing: CGFloat = Space.m
    /// The width the title needs; below it the length moves under the title.
    var minimumTitleWidth: CGFloat = 220

    typealias Cache = BrowseRowMetrics

    func makeCache(subviews: Subviews) -> Cache {
        BrowseRowMetrics()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        cache = metrics(width: proposal.width ?? 480, subviews: subviews)
        return CGSize(width: proposal.width ?? cache.width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count >= 4 else { return }
        if abs(cache.width - bounds.width) > 0.5 {
            cache = metrics(width: bounds.width, subviews: subviews)
        }
        let m = cache
        let firstLine = m.narrow ? max(0, m.title.height - m.length.height - Space.xs) : m.title.height
        var x = bounds.minX
        subviews[0].place(
            at: CGPoint(x: x, y: bounds.minY + max(0, (firstLine - m.number.height) / 2)),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: m.number.width, height: m.number.height))
        x += m.number.width + spacing
        subviews[1].place(
            at: CGPoint(x: x, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: m.titleWidth, height: nil))
        if m.length.width > 0 {
            if m.narrow {
                subviews[4].place(
                    at: CGPoint(x: x, y: bounds.minY + m.title.height + Space.xs),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: m.titleWidth, height: nil))
            } else {
                x += m.titleWidth + spacing
                subviews[4].place(
                    at: CGPoint(x: x, y: bounds.minY + max(0, (firstLine - m.length.height) / 2)),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: m.length.width, height: m.length.height))
                x += m.length.width + spacing
            }
        }
        let statusX = bounds.maxX - m.status.width
        subviews[3].place(
            at: CGPoint(x: statusX, y: bounds.minY + max(0, (firstLine - m.status.height) / 2)),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: m.status.width, height: m.status.height))
        let dateX = statusX - spacing - m.date.width
        subviews[2].place(
            at: CGPoint(x: dateX, y: bounds.minY + max(0, (firstLine - m.date.height) / 2)),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: m.date.width, height: m.date.height))
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> BrowseRowMetrics {
        var m = BrowseRowMetrics()
        m.width = width
        guard subviews.count >= 4 else { return m }
        m.number = subviews[0].sizeThatFits(.unspecified)
        m.date = subviews[2].sizeThatFits(.unspecified)
        m.status = subviews[3].sizeThatFits(.unspecified)
        if subviews.count > 4 {
            m.length = subviews[4].sizeThatFits(.unspecified)
        }
        let fixed = m.number.width + m.date.width + m.status.width + spacing * 3
        m.narrow = width - fixed - m.length.width < minimumTitleWidth
        m.titleWidth = max(40, width - fixed - (m.narrow ? 0 : m.length.width + spacing))
        m.title = subviews[1].sizeThatFits(ProposedViewSize(width: m.titleWidth, height: nil))
        m.height = max(m.number.height, m.date.height, m.status.height, m.title.height)
        if m.narrow, m.length.width > 0 {
            m.height = max(m.height, m.title.height + Space.xs + m.length.height)
        }
        return m
    }
}

/// One row of the episode list: the number, the title, the date and the
/// status (Go `episodeLine`).
struct BrowseEpisodeRow: View {
    let episode: Episode
    let badge: BrowseEpisodeBadge

    var body: some View {
        BrowseEpisodeRowLayout {
            Text(String(format: "%03d", episode.number))
                .font(AppFont.digits)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 40, alignment: .trailing)
            Text(BrowseLogic.title(of: episode))
                .font(AppFont.subheading)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(Self.dateText(episode.date))
                .font(AppFont.digits)
                .foregroundStyle(Palette.textSecondary)
            BrowseBadgeView(badge: badge)
            if !episode.duration.isEmpty {
                Text(episode.duration)
                    .font(AppFont.digits)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(minHeight: 28)
    }

    /// "05.11.2026", "-" without a date (Go `formatDate`).
    static func dateText(_ date: Date?) -> String {
        guard let date else { return "-" }
        return AppFormat.day(date)
    }
}

/// One row of a clip list: the star of the Merkliste, the format, the
/// length and the title (Go `clipLine`).
struct BrowseClipRow: View {
    let episode: Episode
    let badge: BrowseEpisodeBadge

    var body: some View {
        HStack(spacing: Space.m) {
            star
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(BrowseLogic.title(of: episode))
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Space.s) {
                    if !episode.formatName.isEmpty {
                        Text(episode.formatName)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if !episode.duration.isEmpty {
                        Text(episode.duration)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: Space.s)
            BrowseBadgeView(badge: badge)
        }
        .frame(minHeight: 28)
    }

    /// The star of the Merkliste.
    private var star: some View {
        ZStack {
            if episode.bookmarked {
                Image(systemName: "star.fill")
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(episode.bookmarked ? "Auf der Merkliste" : "Nicht auf der Merkliste")
    }
}

/// The list of a clip list (Weiterschauen, Merkliste, Ähnliche, Gast).
struct BrowseClipListView: View {
    let episodes: [Episode]
    let isLoading: Bool
    let loadingLabel: String
    let emptyText: String
    /// The hint under the empty list: what to do next.
    var emptyDetail: String?
    let errorText: String?
    /// The rows the user marked.
    @Binding var selection: Set<String>
    /// Weiterschauen puts the newest episode in a wide card.
    var emphasizeFirst = false
    /// Merkliste groups the episodes by series.
    var groupByFormat = false
    /// The icon of the empty list.
    var emptySymbol = "star"
    /// Opens the quality sheet of the episode.
    var onChooseQuality: ((Episode) -> Void)?

    @Environment(BrowseModel.self) private var model

    var body: some View {
        Group {
            if isLoading && episodes.isEmpty {
                ProgressView(loadingLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                if let errorText {
                    ContentUnavailableView {
                        Label("Die Liste konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                list
            }
        }
    }

    /// A quiet block in the middle of the free area, so the page keeps its
    /// head at the top even when there is nothing to show.
    private var emptyState: some View {
        EmptyState(symbol: emptySymbol, title: emptyText, message: emptyDetail)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 272, maximum: 300), spacing: Space.l, alignment: .top)]
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if emphasizeFirst, let first = episodes.first {
                    continueCard(first)
                        .padding(.horizontal, Space.page)
                    if episodes.count > 1 {
                        cardGrid(Array(episodes.dropFirst()))
                    }
                } else if groupByFormat {
                    ForEach(formatGroups) { group in
                        VStack(alignment: .leading, spacing: Space.m) {
                            SectionHeader(title: group.name, detail: "\(group.episodes.count)")
                                .padding(.horizontal, Space.page)
                            cardGrid(group.episodes)
                        }
                    }
                } else {
                    cardGrid(episodes)
                }
            }
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
        }
        .background(Palette.background)
    }

    private struct ClipGroup: Identifiable {
        let name: String
        var episodes: [Episode]
        var id: String { name }
    }

    /// Series in the order the episodes arrive, not sorted by name.
    private var formatGroups: [ClipGroup] {
        var groups: [ClipGroup] = []
        for episode in episodes {
            let name = episode.formatName.isEmpty ? "Weitere" : episode.formatName
            if let index = groups.firstIndex(where: { $0.name == name }) {
                groups[index].episodes.append(episode)
            } else {
                groups.append(ClipGroup(name: name, episodes: [episode]))
            }
        }
        return groups
    }

    private func cardGrid(_ episodes: [Episode]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
            ForEach(episodes, id: \.identifier) { episode in
                card(episode)
            }
        }
        .padding(.horizontal, Space.page)
    }

    private func card(_ episode: Episode) -> some View {
        let current = model.current(episode)
        return EpisodeCard(
            episode: current,
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier)
        ) {
            model.play([episode])
        }
        .padding(Space.xs)
        .background {
            if selection.contains(episode.identifier) {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .fill(Palette.accentSoft)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(episode.identifier) }
        .contextMenu { menu(for: episode) }
    }

    /// The episode to pick up: the picture, how far it was watched, and play.
    private func continueCard(_ episode: Episode) -> some View {
        let current = model.current(episode)
        let percent = current.progressPercent
        let unfinished = percent > 0 && percent < BrowseLogic.watchedPercent
        return HStack(alignment: .center, spacing: Space.l) {
            EpisodeThumb(
                episode: current,
                percent: percent,
                downloaded: model.isDownloaded(episode.identifier)
            ) {
                model.play([episode])
            }
            .frame(width: 360)
            VStack(alignment: .leading, spacing: Space.s) {
                if !current.formatName.isEmpty {
                    Text(current.formatName.uppercased())
                        .font(AppFont.captionMedium)
                        .tracking(0.8)
                        .foregroundStyle(Palette.accentText)
                }
                Text(BrowseLogic.title(of: current))
                    .font(AppFont.display)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if unfinished {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text("\(percent)")
                            .font(AppFont.hero)
                            .foregroundStyle(Palette.accentText)
                        Text("% gesehen")
                            .font(AppFont.body)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Capsule()
                        .fill(Palette.surfaceMuted)
                        .frame(width: 220, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Palette.accent)
                                .frame(width: 220 * CGFloat(percent) / 100)
                        }
                } else if !current.duration.isEmpty {
                    Text(current.duration)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                PillButton(title: model.watchLabel(episode), symbol: "play.fill", style: .accent) {
                    model.play([episode])
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .contentCard(radius: Radius.panel, selected: selection.contains(episode.identifier))
        .contentShape(Rectangle())
        .onTapGesture { select(episode.identifier) }
        .contextMenu { menu(for: episode) }
    }

    private func select(_ identifier: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(identifier) {
                selection.remove(identifier)
            } else {
                selection.insert(identifier)
            }
        } else {
            selection = [identifier]
        }
    }

    @ViewBuilder private func menu(for episode: Episode) -> some View {
        Button(model.watchLabel(episode)) {
            Task { model.play([episode]) }
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
        if let onChooseQuality {
            Button("Qualität wählen") {
                onChooseQuality(episode)
            }
        }
        Button("Titel kopieren") {
            model.copyTitle(episode)
        }
    }
}
