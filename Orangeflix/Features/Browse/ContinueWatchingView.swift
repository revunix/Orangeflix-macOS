import AppKit
import SwiftUI

/// Which part of Weiterschauen shows.
enum ContinueWatchingFilter: String, CaseIterable, Identifiable {
    case all, open, watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .open: "Offen"
        case .watched: "Gesehen"
        }
    }
}

/// Weiterschauen: the episode to pick up in a wide card, then the open and
/// the finished episodes in their own sections. A filter, a selection bar
/// and the "Markieren" menu mark single, chosen or all episodes at once.
struct ContinueWatchingView: View {
    let episodes: [Episode]
    let isLoading: Bool
    let errorText: String?
    @Binding var selection: Set<String>
    @Binding var filter: ContinueWatchingFilter
    /// True while a batch of episodes is being marked.
    let marking: Bool
    /// Marks the episodes; the screen asks first when there are several.
    let onMark: (_ episodes: [Episode], _ watched: Bool) -> Void
    var onChooseQuality: ((Episode) -> Void)?

    @Environment(BrowseModel.self) private var model

    var body: some View {
        Group {
            if isLoading && episodes.isEmpty {
                ProgressView(ClipListKind.recents.loadingLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                if let errorText {
                    ContentUnavailableView {
                        Label("Die Liste konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("Erneut versuchen") { Task { await model.loadRecents(force: true) } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(symbol: "clock.arrow.circlepath",
                               title: ClipListKind.recents.emptyText,
                               message: ClipListKind.recents.emptyDetail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    controlBar
                        .padding(.horizontal, Space.page)
                        .padding(.bottom, Space.s)
                    list
                }
            }
        }
        .onExitCommand { selection = [] }
    }

    // MARK: Grouping

    private func percent(_ episode: Episode) -> Int { model.current(episode).progressPercent }
    private func isOpen(_ episode: Episode) -> Bool { percent(episode) < BrowseLogic.watchedPercent }

    private var openEpisodes: [Episode] { episodes.filter(isOpen) }
    private var watchedEpisodes: [Episode] { episodes.filter { !isOpen($0) } }

    /// The episodes the filter lets through; "Alle" acts on these.
    var visibleEpisodes: [Episode] { filtered(filter) }

    private func filtered(_ item: ContinueWatchingFilter) -> [Episode] {
        switch item {
        case .all: episodes
        case .open: openEpisodes
        case .watched: watchedEpisodes
        }
    }

    /// The newest started episode leads the page.
    private var hero: Episode? {
        guard filter != .watched else { return nil }
        return openEpisodes.first { percent($0) > 0 } ?? openEpisodes.first
    }

    private var selectedEpisodes: [Episode] {
        episodes.filter { selection.contains($0.identifier) }
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: Space.m) {
            filterPicker
            Spacer(minLength: 0)
            if !selection.isEmpty {
                selectionBar
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            markMenu
        }
        .animation(.snappy(duration: 0.18), value: selection.isEmpty)
    }

    private var filterPicker: some View {
        HStack(spacing: 2) {
            ForEach(ContinueWatchingFilter.allCases) { item in
                let chosen = filter == item
                let count = filtered(item).count
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        filter = item
                        let shown = Set(filtered(item).map(\.identifier))
                        selection = selection.intersection(shown)
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
    }

    /// What can happen with the chosen episodes.
    private var selectionBar: some View {
        let chosen = selectedEpisodes
        return HStack(spacing: Space.xs) {
            Text(chosen.count == 1 ? "1 ausgewählt" : "\(chosen.count) ausgewählt")
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textSecondary)
                .padding(.leading, Space.s)
            barButton("Abspielen", symbol: "play.fill") {
                if chosen.count == 1, let episode = chosen.first {
                    model.navigationPath.append(.episode(episode, autoplay: true))
                } else {
                    model.play(chosen)
                }
            }
            barButton("Als gesehen markieren", symbol: "checkmark.circle") { onMark(chosen, true) }
                .disabled(marking)
            barButton("Als ungesehen markieren", symbol: "circle.dashed") { onMark(chosen, false) }
                .disabled(marking)
            barButton("Auswahl aufheben", symbol: "xmark") { selection = [] }
        }
        .padding(3)
        .glassPlate(in: Capsule(), interactive: true)
    }

    private func barButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Marks every episode the filter shows; always within reach.
    private var markMenu: some View {
        let visible = visibleEpisodes
        let scope = switch filter {
        case .all: "Alle"
        case .open: "Alle offenen"
        case .watched: "Alle gesehenen"
        }
        return Menu {
            Section(visible.count == 1 ? "1 Folge" : "\(visible.count) Folgen") {
                Button("\(scope) als gesehen markieren") { onMark(visible, true) }
                    .disabled(visible.allSatisfy { !isOpen($0) })
                Button("\(scope) als ungesehen markieren") { onMark(visible, false) }
                    .disabled(visible.allSatisfy { percent($0) == 0 })
            }
            Divider()
            Button("Neu laden") { Task { await model.loadRecents(force: true) } }
        } label: {
            HStack(spacing: Space.xs) {
                if marking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                }
                Text("Markieren")
            }
            .font(AppFont.captionMedium)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m)
            .frame(height: 34)
            .glassPlate(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(marking)
        .help("Folgen als gesehen oder ungesehen markieren")
    }

    // MARK: List

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 272, maximum: 300), spacing: Space.l, alignment: .top)]
    }

    private var list: some View {
        let hero = self.hero
        let rest = { (items: [Episode]) in items.filter { $0.identifier != hero?.identifier } }
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let hero {
                    heroCard(hero)
                        .padding(.horizontal, Space.page)
                }
                switch filter {
                case .all:
                    section("Offen", rest(openEpisodes))
                    section("Zuletzt gesehen", watchedEpisodes)
                case .open:
                    section(nil, rest(openEpisodes))
                case .watched:
                    section(nil, watchedEpisodes)
                }
                if visibleEpisodes.isEmpty {
                    Text(filter == .watched ? "Noch keine Folge zu Ende gesehen." : "Keine offene Folge.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.xl)
                }
            }
            .padding(.top, Space.s)
            .padding(.bottom, Space.xl)
        }
        .background(Palette.background)
    }

    @ViewBuilder private func section(_ title: String?, _ items: [Episode]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                if let title {
                    SectionHeader(title: title, detail: "\(items.count)")
                        .padding(.horizontal, Space.page)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                    ForEach(items, id: \.identifier) { card($0) }
                }
                .padding(.horizontal, Space.page)
            }
        }
    }

    private func card(_ episode: Episode) -> some View {
        let current = model.current(episode)
        return EpisodeCard(
            episode: current,
            percent: current.progressPercent,
            downloaded: model.isDownloaded(episode.identifier)
        ) {
            model.navigationPath.append(.episode(episode, autoplay: false))
        }
        .padding(Space.xs)
        .background {
            if selection.contains(episode.identifier) {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .fill(Palette.accentSoft)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(episode) }
        .contextMenu { menu(for: episode) }
    }

    /// The episode to pick up: the picture, how much is left, and play.
    private func heroCard(_ episode: Episode) -> some View {
        let current = model.current(episode)
        let percent = current.progressPercent
        return HStack(alignment: .center, spacing: Space.l) {
            EpisodeThumb(
                episode: current,
                percent: percent,
                downloaded: model.isDownloaded(episode.identifier)
            ) {
                model.navigationPath.append(.episode(episode, autoplay: false))
            }
            .frame(width: 360)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(percent > 0 ? "ZULETZT ANGEFANGEN" : "ALS NÄCHSTES")
                    .font(AppFont.captionMedium)
                    .tracking(0.8)
                    .foregroundStyle(Palette.accentText)
                Text(BrowseLogic.title(of: current))
                    .font(AppFont.display)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if !current.formatName.isEmpty {
                    Text(current.formatName)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                if percent > 0 {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Capsule()
                            .fill(Palette.surfaceMuted)
                            .frame(width: 260, height: 6)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Palette.accent)
                                    .frame(width: 260 * CGFloat(percent) / 100)
                            }
                        Text(progressText(current, percent: percent))
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else if !current.duration.isEmpty {
                    Text(current.duration)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                HStack(spacing: Space.s) {
                    PillButton(title: model.watchLabel(episode), symbol: "play.fill", style: .accent) {
                        model.navigationPath.append(.episode(episode, autoplay: true))
                    }
                    PillButton(title: "Gesehen", symbol: "checkmark", style: .glass) {
                        onMark([episode], true)
                    }
                    .disabled(marking)
                    .help("Als gesehen markieren")
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .contentCard(radius: Radius.panel, selected: selection.contains(episode.identifier))
        .contentShape(Rectangle())
        .onTapGesture { open(episode) }
        .contextMenu { menu(for: episode) }
    }

    /// "42 % gesehen · noch 23 Min."
    private func progressText(_ episode: Episode, percent: Int) -> String {
        var seconds = episode.durationSeconds
        if seconds <= 0 { seconds = BrowseLogic.clockToSeconds(episode.duration) }
        guard seconds > 0 else { return "\(percent) % gesehen" }
        let minutes = max(1, Int((Double(seconds) * Double(100 - percent) / 100 / 60).rounded()))
        let left = minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
        return "\(percent) % gesehen · noch \(left)"
    }

    // MARK: Selection and menu

    private func open(_ episode: Episode) {
        let identifier = episode.identifier
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(identifier) { selection.remove(identifier) } else { selection.insert(identifier) }
        } else if NSEvent.modifierFlags.contains(.shift), let anchor = selection.first,
                  let from = visibleEpisodes.firstIndex(where: { $0.identifier == anchor }),
                  let to = visibleEpisodes.firstIndex(where: { $0.identifier == identifier }) {
            selection = Set(visibleEpisodes[min(from, to)...max(from, to)].map(\.identifier))
        } else {
            selection = [identifier]
            model.navigationPath.append(.episode(episode, autoplay: false))
        }
    }

    @ViewBuilder private func menu(for episode: Episode) -> some View {
        // A right click on a chosen card acts on the whole selection.
        let chosen = selection.contains(episode.identifier) && selection.count > 1 ? selectedEpisodes : [episode]
        if chosen.count > 1 {
            Button("\(chosen.count) Folgen abspielen") { model.play(chosen) }
            Button("\(chosen.count) Folgen als gesehen markieren") { onMark(chosen, true) }
            Button("\(chosen.count) Folgen als ungesehen markieren") { onMark(chosen, false) }
            Button("\(chosen.count) Folgen herunterladen") {
                Task { await model.downloadEpisodes(chosen, of: nil) }
            }
        } else {
            Button(model.watchLabel(episode)) {
                model.navigationPath.append(.episode(episode, autoplay: true))
            }
            if model.isWatched(episode) {
                Button("Als ungesehen markieren") { onMark([episode], false) }
            } else {
                Button("Als gesehen markieren") { onMark([episode], true) }
                Button("Aus Weiterschauen entfernen") { onMark([episode], false) }
            }
            Divider()
            Button("Herunterladen") {
                Task { await model.downloadEpisodes([episode], of: nil) }
            }
            Button(model.isBookmarked(episode) ? "Von der Merkliste nehmen" : "Auf die Merkliste setzen") {
                Task { await model.toggleBookmark(episode) }
            }
            if let onChooseQuality {
                Button("Qualität wählen") { onChooseQuality(episode) }
            }
            Button("Titel kopieren") { model.copyTitle(episode) }
            if model.isDownloaded(episode.identifier) {
                Button("Im Finder zeigen") { model.reveal(episode) }
            }
        }
    }
}
