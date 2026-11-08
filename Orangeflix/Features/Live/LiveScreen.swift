import AppKit
import SwiftUI

/// The Live screen (the screen "Live" of the TUI): the show on top, the
/// picture below it; the chat stands either as a column at the right edge
/// of the window or under the picture.
/// The page starts without the chat; the reader puts it where it belongs.
/// During a show the voting is pinned to the top of the chat.
struct LiveScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveModel.self) private var model
    @Environment(PlaybackCenter.self) private var playback
    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    /// Whether the chat sticks to the newest message. Scrolling up keeps the
    /// place and offers a jump back down.
    @State private var followLatest = true
    @State private var unreadBelow = false
    @State private var scrollToken = 0
    /// Whether the pointer is dragging the chat. Layout passes must not
    /// unpin the newest line; only a real scroll does.
    @State private var userScrolling = false
    /// Whether the reader put the chat away. The page starts as the settings
    /// say; the messages come in the background either way.
    @State private var chatHidden = true
    /// Where the chat stands when it shows.
    /// The size of the whole page, picture and chat column together; the
    /// automatic placement of the chat follows it.
    @State private var pageSize: CGSize = .zero
    /// The size of the Live window, chosen in the size menu.
    @AppStorage("liveWindowSize") private var windowStep: LiveWindowStep = .medium
    /// Where the chat stands in the Live window while the settings leave it
    /// open (`Automatisch`).
    @AppStorage("liveWindowLayout") private var windowLayout: LiveWindowLayout = .side
    /// The height of the description and the programme under the picture.
    @State private var bodyHeight: CGFloat = 0
    /// Whether the voting over the picture is folded into its pill.
    @State private var pollCollapsed = false
    /// The height of the show above the picture.
    @State private var headerHeight: CGFloat = 90

    /// The width of the chat column.
    /// The narrowest chat column; it widens with the window.
    private static let chatWidth: CGFloat = 360
    /// The widest chat column; beyond it the picture would reach its full
    /// height anyway, and the page centres.
    private static let maxChatWidth: CGFloat = 560
    /// The room the chat needs under the picture; the picture gives way
    /// before the chat does.
    /// The room under the picture for the chat at the least: the gap and
    /// 300 pt of chat. The chat takes all the height beyond it.
    private static let belowChatRoom: CGFloat = belowChatHeight
    /// The chat under the picture in the Live window, with the gap above it.
    private static let belowChatHeight: CGFloat = Space.l + 420
    /// The room of the titlebar with the toolbar above the page.
    private static let titlebarRoom: CGFloat = 60
    /// The page width beside the picture and the chat column: the margins
    /// left, between and right.
    private static let sideGutters: CGFloat = Space.page * 3
    /// The width of the voting over the picture.
    private static let pollWidth: CGFloat = 300

    /// Where the chat stands on the page.
    private enum ChatPlacement {
        /// A column at the right edge of the window.
        case side
        /// Under the picture, beside the show details.
        case below
    }

    var body: some View {
        HStack(spacing: 0) {
            standardArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsSideChat {
                chatColumn
                    .frame(width: sideChatWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        .background(Palette.background)
        // The Live page has fixed sizes; the window takes the chosen one.
        .preference(key: FixedPageSizeKey.self, value: fixedPageSize)
        // The window keeps the navigation pill clear of the chat column.
        .preference(key: TrailingColumnKey.self, value: showsSideChat ? Self.chatWidth : 0)
        .animation(.snappy(duration: 0.25), value: showsSideChat)
        .navigationTitle("")
        .onAppear {
            model.screenAppeared()
            applyStartSettings()
        }
        .task(id: app.accountGeneration) {
            await model.refresh(account: app.accountGeneration)
        }
        .task {
            // A show that starts while the screen is open shows up on its
            // own; a chat that did not connect is opened again.
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                ticks += 1
                if ticks % 12 == 0 {
                    await model.load()
                } else {
                    await model.ensureChat()
                }
            }
        }
        .onDisappear {
            if playback.isInline { playback.stop() }
            model.screenDisappeared()
        }
    }

    @Environment(\.colorScheme) private var systemScheme

    /// The banner of the format of the show, behind the stage while nothing plays.
    private var banner: String {
        guard let pid = model.info?.show?.pid ?? model.info?.scheduled?.pid,
              let format = browse.format(pid: pid) else { return "" }
        return format.banner.isEmpty ? format.cover : format.banner
    }

    // MARK: The show

    /// What the page is about: the running show, else the next one, else
    /// the replay of the last one.
    private enum Subject {
        case live(LivestreamShow?)
        case next(LivestreamScheduled)
        case replay(LivestreamReplay)
        case none
    }

    /// The running show comes first; a replay that plays is next, so the
    /// page talks about what is on the picture.
    private func subject(_ info: LivestreamInfo) -> Subject {
        if info.isLive { return .live(info.show) }
        if replayPlays, let replay = info.replay { return .replay(replay) }
        if let next = info.scheduled { return .next(next) }
        if let replay = info.replay, replay.possible { return .replay(replay) }
        return .none
    }

    /// Whether the replay plays, here or in the player window.
    private var replayPlays: Bool { playback.isPlaying && playback.current?.kind == .replay }

    /// The name of the format of a show, from the catalog.
    private func formatTitle(pid: Int, fallback: String = "") -> String {
        guard pid > 0, let format = browse.format(pid: pid) else { return fallback }
        return format.title
    }

    /// The wide picture of a format; the cover when it has no banner.
    private func formatArt(pid: Int) -> String {
        guard pid > 0, let format = browse.format(pid: pid) else { return "" }
        return format.banner.isEmpty ? format.cover : format.banner
    }

    private func formatName(_ subject: Subject) -> String {
        switch subject {
        case .live(let show): formatTitle(pid: show?.pid ?? 0)
        case .next(let next): formatTitle(pid: next.pid)
        case .replay(let replay): formatTitle(pid: replay.pid, fallback: replay.projectTitle)
        case .none: ""
        }
    }

    /// The chat column stands beside the picture until the reader puts it
    /// away; outside a show it says when the chat opens.
    private var showsChat: Bool { !chatHidden }
    /// Where the chat stands: as the settings fix it, or automatically where
    /// the picture grows larger.
    private var chatPlacement: ChatPlacement {
        switch app.settings.liveChatPosition {
        case .side: .side
        case .below: .below
        case .auto: windowLayout == .below ? .below : .side
        }
    }

    /// Whether the chat stands as the column at the right edge.
    private var showsSideChat: Bool { showsChat && chatPlacement == .side }
    /// Whether the chat stands under the picture.
    private var showsBelowChat: Bool { showsChat && chatPlacement == .below }
    private var playsHere: Bool { playback.isPlaying && playback.isInline }
    private var hairline: CGFloat { Chrome.hairline(displayScale) }

    // MARK: Standard

    /// The margin of the picture and of the chat column. Both use it, so the
    /// upper edge of the chat stands on the same line as the picture.
    private static let margin = Space.l

    /// The stage at 16:9 for the given area. It fills the width but leaves
    /// room for the show below, so a short window shrinks the picture
    /// instead of hiding the show. With the chat under the picture it needs
    /// more room; the picture gives way first. Computed in the layout pass
    /// itself, so a live resize never draws with the size of the frame
    /// before.
    private func stageSize(in area: CGSize) -> CGSize {
        let width = max(area.width - Space.page * 2, 320)
        // The show stands above the picture; under it the chat, or else a
        // glimpse of what follows.
        let header = model.info == nil ? 0 : headerHeight + Space.l
        // Under the picture only the chat takes room; without it the
        // picture reaches down to the margin.
        let reserved = header + (showsBelowChat ? Self.belowChatRoom : 0)
        let height = min(width * 9 / 16, max(area.height - Self.margin * 2 - reserved, 220))
        return CGSize(width: height * 16 / 9, height: height)
    }

    private var standardArea: some View {
        GeometryReader { geo in
            let size = stageSize(in: geo.size)
            if showsBelowChat {
                belowStage(size: size)
            } else if showsSideChat {
                // Beside the chat the window holds exactly the show and the
                // picture: nothing to scroll.
                VStack(alignment: .leading, spacing: Space.l) {
                    if let info = model.info {
                        measuredHeader(info)
                    }
                    stage()
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, alignment: .leading)
                .padding(.top, topInset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        if let info = model.info {
                            measuredHeader(info)
                        }
                        stage()
                            .frame(width: size.width, height: size.height)
                        if let info = model.info {
                            showBody(info)
                                .padding(.top, Space.s)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                        }
                    }
                    .frame(width: size.width, alignment: .leading)
                    .padding(.top, topInset)
                    .padding(.bottom, Self.margin)
                    .frame(width: geo.size.width)
                }
            }
        }
    }

    /// The chat under the picture: what runs, with the actions, above the
    /// picture, the chat over its full width below it. The chat takes the
    /// rest of the window, so it is never cut off.
    private func belowStage(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let info = model.info {
                measuredHeader(info)
                    .frame(width: size.width, alignment: .leading)
            }
            stage()
                .frame(width: size.width, height: size.height)
            chatPanel
                // The width of the picture, but the height of the window:
                // the chat takes what is left.
                .frame(width: size.width)
                .frame(maxHeight: .infinity)
        }
        .padding(.vertical, Self.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The voting floating in the upper right corner of the picture. It folds into a small pill; on a short
    /// picture it scrolls instead of reaching over the controls.
    @ViewBuilder
    private func stagePoll(_ poll: LivePoll, stageHeight: CGFloat) -> some View {
        Group {
            if pollCollapsed {
                Button {
                    pollCollapsed = false
                } label: {
                    Label(poll.hasVoted ? "Abstimmung · abgestimmt" : "Abstimmung", systemImage: "chart.bar.fill")
                        .font(AppFont.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        .glassPlate(in: Capsule(), tint: .black.opacity(0.42), interactive: true)
                }
                .buttonStyle(.plain)
                .help("Abstimmung aufklappen")
            } else {
                let room = max(stageHeight - Space.m * 2 - 72, 160)
                ViewThatFits(in: .vertical) {
                    pollPanel(poll, collapsible: true)
                    ScrollView {
                        pollPanel(poll, collapsible: true)
                    }
                    .scrollIndicators(.automatic)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                }
                .frame(width: Self.pollWidth)
                .frame(maxHeight: room, alignment: .top)
            }
        }
        .padding(Space.m)
        .environment(\.colorScheme, .dark)
        .onChange(of: LivePollVotes.identity(of: poll)) { pollCollapsed = app.settings.livePolls == .collapsed }
    }

    /// The show above the picture; its height leaves the picture its room.
    private func measuredHeader(_ info: LivestreamInfo) -> some View {
        showHeader(info)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    /// What runs, above the picture. It is content, so it stands on the page
    /// without glass: the state and the format, the title, then the slot
    /// with its progress and the tags in one quiet line. The actions share
    /// one glass capsule at the right, like the buttons of the toolbar.
    private func showHeader(_ info: LivestreamInfo) -> some View {
        let subject = subject(info)
        let title = showTitle(subject)
        let format = formatName(subject)
        // The actions stand at the top, on the line of the upper edge of
        // the chat column beside the page.
        return HStack(alignment: .top, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    statusBadge(subject)
                    if !format.isEmpty, format != title {
                        Text(format)
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
                // Slot and tags share a line while it fits.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.l) {
                        slot(subject)
                        tags(subject, info: info)
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        slot(subject)
                        tags(subject, info: info)
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Space.l)
            showActions
        }
    }

    /// The time of the show: the progress of a running one, else its slot.
    @ViewBuilder
    private func slot(_ subject: Subject) -> some View {
        if case .live(let show) = subject, let show, show.begin > 0, show.end > show.begin {
            LiveShowProgress(begin: show.begin, end: show.end)
        } else {
            timeLine(subject)
        }
    }

    /// The description of the show, a note of the server and the programme.
    private func showBody(_ info: LivestreamInfo) -> some View {
        let subject = subject(info)
        return VStack(alignment: .leading, spacing: Space.l) {
            if let text = descriptionText(subject), !text.isEmpty {
                description(text)
            }
            if !info.message.isEmpty {
                Label(info.message, systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.warning)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warningSoft, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            }
            cards(subject, info: info)
        }
    }

    /// The actions of the show in one glass capsule: the chat, which a click
    /// shows or hides, and the size of the window.
    private var showActions: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { advanceChat() }
            } label: {
                Label("Chat", systemImage: nextChatStep.symbol)
            }
            .buttonStyle(LiveHeaderButtonStyle(active: showsChat))
            .help(nextChatStep.help)
            .accessibilityLabel(nextChatStep.help)
            Rectangle()
                .fill(Palette.divider)
                .frame(width: hairline, height: 16)
            sizeMenu
        }
        .padding(Space.xxs)
        .glassPlate(in: Capsule())
        .fixedSize()
    }

    /// The sizes of the Live window, and where the chat stands in it.
    private var sizeMenu: some View {
        Menu {
            if app.settings.liveChatPosition == .auto {
                Picker("Chat", selection: Binding(
                    get: { windowLayout },
                    set: { value in withAnimation(.snappy(duration: 0.25)) { windowLayout = value; chatHidden = false } })) {
                    Label("Rechts neben dem Bild", systemImage: "sidebar.trailing").tag(LiveWindowLayout.side)
                    Label("Unter dem Bild", systemImage: "rectangle.bottomhalf.inset.filled").tag(LiveWindowLayout.below)
                }
                .pickerStyle(.inline)
            }
            Picker("Größe", selection: $windowStep) {
                ForEach(LiveWindowStep.allCases, id: \.self) { step in
                    Text(step.title).tag(step)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(windowStep.title, systemImage: "macwindow")
        }
        .menuStyle(.button)
        .buttonStyle(LiveHeaderButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Größe des Fensters und Platz des Chats")
    }

    /// The page the Live window shows: the picture in the chosen size, the
    /// chat beside it or under it, so nothing around them stays empty.
    private var fixedPageSize: CGSize? {
        let fixed = Self.margin * 2 + (model.info == nil ? 0 : headerHeight + Space.l)
        let stage = stageHeight(for: windowStep, fixed: fixed)
        return pageSize(stage: stage, fixed: fixed).map { CGSize(width: $0.width.rounded(), height: $0.height.rounded()) }
    }

    /// The page for a picture of this height in the current layout.
    private func pageSize(stage: CGFloat, fixed: CGFloat) -> CGSize? {
        let width = stage * 16 / 9
        if showsSideChat {
            return CGSize(width: width + Self.sideGutters + Self.chatWidth, height: fixed + stage)
        }
        if showsBelowChat {
            return CGSize(width: width + Space.page * 2, height: fixed + stage + Self.belowChatHeight)
        }
        return CGSize(width: width + Space.page * 2, height: fixed + stage)
    }

    /// The height of the picture of a size; the largest fills the screen.
    private func stageHeight(for step: LiveWindowStep, fixed: CGFloat) -> CGFloat {
        let largest: CGFloat = {
            guard let visible = NSScreen.main?.visibleFrame.size else { return 760 }
            // The titlebar with the toolbar stands above the page.
            let height = visible.height - Self.titlebarRoom
            let side = showsSideChat
            let extraWidth = side ? Self.sideGutters + Self.chatWidth : Space.page * 2
            let extraHeight = fixed + (showsBelowChat ? Self.belowChatHeight : 0)
            return min((visible.width - extraWidth) * 9 / 16, height - extraHeight).rounded(.down)
        }()
        // Under the picture the window is as wide as the picture, so the
        // sizes start larger; the smallest still makes a window of 1000 pt.
        let below = showsBelowChat
        let wanted: CGFloat = switch step {
        case .small: below ? 550 : 450
        case .medium: below ? 650 : 600
        case .large: below ? 760 : 760
        case .largest: largest
        }
        return max(min(wanted, largest), 300)
    }

    // MARK: Pieces of the show

    /// The picture as a framed card.
    private func stage() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return LiveStage(model: model, playback: playback, banner: banner)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
            // The voting floats over the picture in every layout.
            .overlay(alignment: .topTrailing) {
                GeometryReader { geometry in
                    if let poll = activePoll {
                        stagePoll(poll, stageHeight: geometry.size.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.snappy(duration: 0.25), value: activePoll != nil)
            .animation(.snappy(duration: 0.25), value: pollCollapsed)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            .environment(\.colorScheme, .dark)
    }

    private func showTitle(_ subject: Subject) -> String {
        switch subject {
        case .live(let show): show.map { $0.title.isEmpty ? "Livesendung" : $0.title } ?? "Livesendung"
        case .next(let next): next.title
        case .replay(let replay): replay.title.isEmpty ? "Letzte Sendung" : replay.title
        case .none: "Gerade läuft keine Sendung"
        }
    }

    /// The time beside the state: the slot of the next show with its
    /// countdown, the slot of the replay. A running show has its progress.
    @ViewBuilder
    private func timeLine(_ subject: Subject) -> some View {
        switch subject {
        case .next(let next) where next.begin > 0:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Space.s) {
                    Text(Self.when(next.begin, end: next.end))
                        .foregroundStyle(Palette.textSecondary)
                    Text(LiveCountdown.text(until: Date(timeIntervalSince1970: TimeInterval(next.begin)),
                                            now: context.date))
                        .foregroundStyle(Palette.accentText)
                }
                .font(AppFont.digitsMedium)
                .lineLimit(1)
                .fixedSize()
            }
        case .replay(let replay) where replay.begin > 0:
            Text(Self.when(replay.begin, end: replay.end))
                .font(AppFont.digitsMedium)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func tags(_ subject: Subject, info: LivestreamInfo) -> some View {
        switch subject {
        case .live:
            HStack(spacing: Space.s) {
                tag(info.show?.chat == true ? "Chat an" : "Chat aus",
                    symbol: "bubble.left.and.bubble.right", active: info.show?.chat == true)
                tag(info.hasAccess ? "Im Abo" : "Kein Zugang",
                    symbol: info.hasAccess ? "checkmark.seal" : "lock", active: info.hasAccess)
            }
        case .next(let next) where next.chat:
            tag("Mit Chat", symbol: "bubble.left.and.bubble.right", active: true)
        case .none:
            Text("Sobald eine Sendung beginnt, erscheint sie hier.")
                .font(AppFont.body)
                .foregroundStyle(Palette.textSecondary)
        default:
            EmptyView()
        }
    }

    private func descriptionText(_ subject: Subject) -> String? {
        switch subject {
        case .live(let show): show?.description
        case .next(let next): next.description
        case .replay(let replay): replay.description
        case .none: nil
        }
    }

    private func statusBadge(_ subject: Subject) -> some View {
        let (text, color): (String, Color) = switch subject {
        case .live: ("LIVE", Palette.live)
        case .next: ("ALS NÄCHSTES", Palette.accent)
        case .replay: ("REPLAY", Palette.info)
        case .none: ("OFFLINE", Palette.textTertiary)
        }
        return HStack(spacing: Space.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(AppFont.captionMedium)
                .tracking(1.2)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func description(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body)
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(2)
            .frame(maxWidth: 680, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tag(_ text: String, symbol: String, active: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(AppFont.captionMedium)
            .foregroundStyle(active ? Palette.accentText : Palette.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }

    /// "Fr. 06.11. · 20:15 – 22:00"
    static func when(_ begin: Int64, end: Int64) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(begin))
        var text = AppFormat.dayMonth(start) + " · " + AppFormat.time(start)
        if end > begin {
            text += " – " + AppFormat.time(Date(timeIntervalSince1970: TimeInterval(end)))
        }
        return text
    }

    // MARK: The programme

    /// What else there is: the replay of the last show and the next show as
    /// wide rows with the banner of their format.
    @ViewBuilder
    private func cards(_ subject: Subject, info: LivestreamInfo) -> some View {
        let replay: LivestreamReplay? = {
            guard let replay = info.replay, replay.possible else { return nil }
            if case .replay = subject { return nil }
            return replay
        }()
        let next: LivestreamScheduled? = {
            guard let next = info.scheduled else { return nil }
            if case .next = subject { return nil }
            return next
        }()
        if replay != nil || next != nil {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionLabel(text: "Programm")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Space.m, alignment: .top)],
                          alignment: .leading, spacing: Space.m) {
                    if let next {
                        nextTile(next)
                    }
                    if let replay {
                        replayTile(replay)
                    }
                }
            }
            .padding(.top, Space.s)
        }
    }

    private func pollContent(_ poll: LivePoll) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(poll.question)
                .font(AppFont.heading)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s) {
                ForEach(Array(poll.answers.enumerated()), id: \.offset) { index, answer in
                    LivePollAnswer(answer: answer, index: index, poll: poll) {
                        model.vote(answer: index)
                    }
                }
            }
            if !poll.footer.isEmpty {
                Text(poll.footer)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func replayTile(_ replay: LivestreamReplay) -> some View {
        let playable = replay.canAccess && !replayPlays
        return LiveProgramTile(
            art: formatArt(pid: replay.pid),
            kicker: "REPLAY", kickerColor: Palette.info,
            title: replay.title.isEmpty ? "Letzte Sendung" : replay.title,
            format: formatTitle(pid: replay.pid, fallback: replay.projectTitle),
            action: playable ? { model.watchReplay() } : nil
        ) {
            if replay.begin > 0 {
                Text(Self.when(replay.begin, end: replay.end))
                    .font(AppFont.digits)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        } accessory: {
            if replayPlays {
                Label("Läuft", systemImage: "waveform")
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.accentText)
            } else if replay.canAccess {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.accent))
                    .help("Replay ansehen")
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Palette.textTertiary)
                    .help("Nicht in deinem Abo enthalten")
            }
        }
    }

    private func nextTile(_ next: LivestreamScheduled) -> some View {
        LiveProgramTile(
            art: formatArt(pid: next.pid),
            kicker: "NÄCHSTE SENDUNG", kickerColor: Palette.accent,
            title: next.title,
            format: formatTitle(pid: next.pid),
            action: nil
        ) {
            if next.begin > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let when = Text(Self.when(next.begin, end: next.end))
                        .foregroundStyle(Palette.textSecondary)
                    let countdown = Text(LiveCountdown.text(until: Date(timeIntervalSince1970: TimeInterval(next.begin)),
                                                            now: context.date))
                        .foregroundStyle(Palette.accentText)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Space.s) { when; countdown }
                        VStack(alignment: .leading, spacing: 2) { when; countdown }
                    }
                    .font(AppFont.digits)
                    .lineLimit(1)
                }
            }
        } accessory: {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: The chat

    /// What the next click of the chat button does.
    private var nextChatStep: (symbol: String, help: String) {
        if showsChat { return ("xmark", "Chat ausblenden") }
        return chatPlacement == .side
            ? ("sidebar.trailing", "Chat einblenden")
            : ("rectangle.bottomhalf.inset.filled", "Chat einblenden")
    }

    /// Shows or hides the chat; where it stands follows the settings.
    private func advanceChat() {
        chatHidden.toggle()
    }

    /// The chat as a floating Liquid Glass panel: header, the messages and
    /// the field. The voting stands in its own panel next to it. The placement around it decides where it
    /// stands.
    private var chatPanel: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        return VStack(spacing: 0) {
            chatHeader
                .snappedToPixels()
            divider
            if model.lines.isEmpty {
                emptyChat
                    .frame(maxHeight: .infinity)
            } else {
                // The messages give way first: the list takes only the room
                // the header and the field leave, at any text size.
                messageList
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .layoutPriority(-1)
            }
            if model.isChatConnected {
                divider
                LiveComposer(model: model)
                    .padding(Space.m)
                    .fixedSize(horizontal: false, vertical: true)
                    .snappedToPixels()
                    .layoutPriority(1)
            }
        }
        .frame(maxHeight: .infinity)
        .clipShape(shape)
        .glassPlate(in: shape)
    }

    /// The chat as a column at the right edge of the window. It keeps a
    /// margin to the edges, so no surface runs along its whole height.
    private var chatColumn: some View {
        chatPanel
            // Beside the page the column ends with the picture, so no empty
            // field opens under the picture.
            .frame(height: sideChatHeight)
            // The upper edge of the column stands on the line of the show
            // above the picture.
            .padding(.top, topInset)
            .padding(.bottom, Self.margin)
            .padding(.trailing, Space.page)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The height of the chat column: from the show above the picture down
    /// to the lower edge of the picture. Computed like the picture itself,
    /// so it never waits for a layout pass and does not move with a scroll.
    private var sideChatHeight: CGFloat? {
        guard pageSize.width > 0 else { return nil }
        return min(max(showAndStageHeight, 360), pageSize.height - Self.margin * 2)
    }

    /// The width of the chat column beside the page. A wider window first
    /// lets the picture grow until it fills the height; the width beyond
    /// that goes to the chat, so no empty field opens above and below the
    /// picture.
    private var sideChatWidth: CGFloat {
        guard pageSize.width > 0, pageSize.height > 0 else { return Self.chatWidth }
        let header = model.info == nil ? 0 : headerHeight + Space.l
        let fullHeight = max(pageSize.height - Self.margin * 2 - header, 220)
        let stageWidth = fullHeight * 16 / 9
        let rest = pageSize.width - Self.sideGutters - stageWidth
        return min(max(rest.rounded(.down), Self.chatWidth), Self.maxChatWidth)
    }

    /// The room left of the chat column, where the show and the picture stand.
    private var contentArea: CGSize {
        CGSize(width: pageSize.width - (showsSideChat ? sideChatWidth : 0), height: pageSize.height)
    }

    /// The show above the picture and the picture itself.
    private var showAndStageHeight: CGFloat {
        let header = model.info == nil ? 0 : headerHeight + Space.l
        return header + stageSize(in: contentArea).height
    }

    /// The upper margin of the page. When the window is taller than the
    /// picture needs (its width limits it to 16:9), the show, the picture and
    /// the chat beside it stand in the middle instead of leaving an empty
    /// field at the bottom. What lies under the picture counts too; when it
    /// does not fit, the page starts at the top and scrolls.
    private var topInset: CGFloat {
        guard pageSize.height > 0 else { return Self.margin }
        let below = bodyHeight > 1 && !showsSideChat ? Space.l + bodyHeight : 0
        let content = showAndStageHeight + below
        return max(Self.margin, ((pageSize.height - content) / 2).rounded())
    }

    /// A line between the parts of the panel; it stops short of the rounded
    /// edges.
    private var divider: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: hairline)
            .padding(.horizontal, Space.m)
    }

    /// The running voting, while it has answers and the settings show it.
    private var activePoll: LivePoll? {
        guard app.settings.livePolls != .hidden else { return nil }
        return model.poll.flatMap { $0.answers.isEmpty ? nil : $0 }
    }

    /// Opens the page the way the settings want it: the chat in its place,
    /// a voting folded or not. Without animation, so nothing slides in.
    private func applyStartSettings() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            chatHidden = !app.settings.liveChatOpen
            pollCollapsed = app.settings.livePolls == .collapsed
        }
    }

    /// How the chat reads, from the settings.
    private var chatStyle: LiveChatStyle {
        LiveChatStyle(scale: app.settings.liveChatTextSize.scale,
                      avatars: app.settings.liveChatAvatars,
                      times: app.settings.liveChatTimes)
    }

    /// The voting in its own glass panel, floating over the picture.
    private func pollPanel(_ poll: LivePoll, collapsible: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                SectionLabel(text: "Abstimmung", symbol: "chart.bar.fill")
                Spacer(minLength: Space.s)
                if collapsible {
                    Button {
                        pollCollapsed = true
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Abstimmung einklappen")
                }
            }
            pollContent(poll)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .snappedToPixels()
        .clipShape(shape)
        .glassPlate(in: shape)
    }

    /// The messages. A reader who scrolled up is not pulled back down; the
    /// button in the column jumps to the newest line.
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(Array(bubbles.enumerated()), id: \.offset) { _, bubble in
                        if bubble.count == 1, let line = bubble.first, line.isSystem {
                            systemNote(line)
                                .snappedToPixels()
                        } else {
                            LiveChatBubble(model: model, lines: bubble) { id in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .snappedToPixels()
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, Space.s)
                // Room above the first row for its floating action bar.
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)
            }
            .environment(\.liveChatStyle, chatStyle)
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if unreadBelow, !followLatest {
                    PillButton(title: "Neueste", symbol: "arrow.down", style: .glass) {
                        followLatest = true
                        unreadBelow = false
                        scrollToken += 1
                    }
                    .padding(.bottom, Space.s)
                }
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                guard geo.contentSize.height > geo.containerSize.height + 8 else { return true }
                return geo.visibleRect.maxY >= geo.contentSize.height - 64
            } action: { _, atBottom in
                if atBottom {
                    followLatest = true
                    unreadBelow = false
                } else if userScrolling {
                    followLatest = false
                }
            }
            .onChange(of: model.lines.count) { _, _ in
                if followLatest {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                } else {
                    unreadBelow = true
                }
            }
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
        }
    }

    /// A note of the program, centered, not a message.
    private func systemNote(_ line: LiveChatLine) -> some View {
        Text(line.text)
            .font(.system(size: 11 * chatStyle.scale))
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
    }

    /// The title of the chat, the state of the connection and the people in it.
    private var chatHeader: some View {
        HStack(spacing: Space.s) {
            Text("Chat")
                .font(AppFont.heading)
                .foregroundStyle(Palette.textPrimary)
            Circle()
                .fill(model.isChatConnected ? Palette.success : Palette.textTertiary)
                .frame(width: 7, height: 7)
                .help(model.isChatConnected ? "Verbunden" : "Nicht verbunden")
            if !model.chatStatus.isEmpty, model.chatStatus != model.chatPeople, model.chatStatus != "Chat verbunden" {
                Text(model.chatStatus)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !model.chatPeople.isEmpty {
                Label(model.chatPeople.replacingOccurrences(of: " im Chat", with: ""), systemImage: "person.2.fill")
                    .font(AppFont.digitsMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .help(model.chatPeople)
            }
            Button {
                chatHidden = true
            } label: {
                Image(systemName: showsSideChat ? "sidebar.trailing" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Chat ausblenden")
            .accessibilityLabel("Chat ausblenden")
        }
        .padding(.horizontal, Space.l)
        .frame(height: 52)
    }

    /// The state of the chat when no message arrived yet (Go `liveChatHint`).
    private var emptyChat: some View {
        EmptyState(symbol: "bubble.left.and.bubble.right", title: emptyChatText)
    }

    /// The line under the empty chat.
    private var emptyChatText: String {
        if replayPlays, model.info?.isLive != true {
            // The server keeps the chat of a replay with its clip; a fresh
            // replay has none yet.
            if playback.current?.identifier.isEmpty ?? true {
                return "Für dieses Replay gibt es noch keinen Chat-Mitschnitt."
            }
            return "Der Chat-Mitschnitt läuft mit dem Video mit; die Nachrichten erscheinen an ihrer Stelle."
        }
        guard model.info?.isLive == true else { return "Den Chat gibt es während einer Livesendung." }
        if model.info?.show?.chat == true {
            return model.isChatConnected ? "Noch keine Nachrichten." : "Verbinde mit dem Chat …"
        }
        return "Für diese Sendung ist kein Chat eingeschaltet."
    }

    /// The messages of the chat, grouped as in a messenger: the messages of
    /// one sender that follow each other share a bubble.
    private var bubbles: [[LiveChatLine]] {
        var runs: [[LiveChatLine]] = []
        var index = 0
        let lines = model.lines
        while index < lines.count {
            var run = [lines[index]]
            var next = index + 1
            while next < lines.count, LiveChatLogic.isGrouped(after: run.last, lines[next]) {
                run.append(lines[next])
                next += 1
            }
            runs.append(run)
            index = next
        }
        return runs
    }
}
