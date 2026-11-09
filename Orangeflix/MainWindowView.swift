import AppKit
import Foundation
import Observation
import SwiftUI

/// The main window. The brand, section navigation and global actions live in
/// the native macOS toolbar; the selected screen fills the content area.
struct MainWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var browse
    @Environment(AccountModel.self) private var account
    @Environment(LiveModel.self) private var live
    @Environment(NewEpisodeWatcher.self) private var watcher
    @Environment(AnnouncementsModel.self) private var announcements
    @Environment(CalendarModel.self) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    /// Set once the stored credentials are read; until then the window
    /// stays empty, so neither the login nor the app flashes up.
    @State private var started = false
    /// True while a banner picture lies under the titlebar, so its ink turns
    /// white over the dark photograph.
    @State private var heroUnderTitlebar = false
    /// True while content runs under the toolbar after scrolling, so a
    /// fading scrim keeps the bar and the logo readable.
    @State private var titlebarScrolled = false
    /// True while the reload runs, so the button shows it.
    @State private var reloading = false
    /// The width of the navigation pill in the middle of the toolbar.
    @State private var pillWidth: CGFloat = 0
    /// The motion of the capsule in the pill. It lives here and not in the
    /// pill: the toolbar builds its items anew when the screen changes, and
    /// the slide must go on in the new one.
    @State private var pillMotion = PillMotion()
    /// The width of a column the screen keeps at the right edge, under the
    /// toolbar (the chat of the Live screen); 0 when there is none.
    @State private var trailingColumn: CGFloat = 0
    /// How the Live page grows with its picture; nil on every other page.
    @State private var livePage: LivePageGeometry?
    /// Outlives the screen views, including their AppKit bridges.
    @State private var windowMemory = MainWindowFrameMemory()

    var body: some View {
        content
            .environment(\.interfaceStyle, app.settings.interfaceStyle)
            .environment(\.glassPanels, app.settings.glassPanels)
            .id(app.settings.themeSignature)
    }

    private var content: some View {
        screen
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background.ignoresSafeArea())
            .background { TitlebarTransparency() }
            .background { WindowAppearance(theme: app.settings.theme) }
            .background { WindowSizeMemory(memory: windowMemory, isLive: { [app] in app.selection == .live }) }
            // The smallest window of the open page, and wide enough for the
            // navigation pill. One frame: a second, outer one would cap it.
            .modifier(PageSizing(live: app.selection == .live ? livePage : nil, floor: windowFloor,
                                 minWidth: max(windowFloor, pageMinimum.width), minHeight: pageMinimum.height))
            // The Live window scales like a video player.
            .background { LiveWindowSizing(geometry: app.selection == .live ? livePage : nil) }
            .background {
                WindowWidthFloor(minimum: windowFloor, restoresWidth: app.selection != .live)
            }
            // The picture of a screen runs under the toolbar; once it is
            // scrolled, a fade keeps the bar, the logo and the words
            // readable over any color. In the dark it goes darker than the
            // page, in the light it takes the color of the page so the dark
            // ink of the bar stays readable.
            .overlay(alignment: .top) {
                titlebarScrim
                    .opacity(titlebarScrolled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: titlebarScrolled)
                    .allowsHitTesting(false)
            }
            // Marking many episodes holds the window until the server has
            // processed all of them.
            .overlay { WatchedBatchOverlay() }
            .tint(Palette.accent)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    BrandChip()
                }
                .flatInTitlebar()
                ToolbarItem(placement: .principal) {
                    NavPill(items: sections,
                            current: app.selection,
                            motion: pillMotion,
                            showsLiveDot: { $0 == .live && live.info?.isLive == true },
                            onSelect: { app.selection = $0 })
                    // The pill keeps the width its words need. Otherwise the
                    // toolbar squeezes it, the measured width shrinks with
                    // it, and the window grows too little to give it back.
                    .fixedSize(horizontal: true, vertical: false)
                    // The first and the last word need room before the
                    // rounded end of the pill.
                    .padding(.horizontal, 2)
                    .modifier(ToolbarPill())
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pillWidth = $0 }
                }
                // No flat item here: from macOS 26 on the pill sits in the
                // same glass of the toolbar as the buttons on the right, so
                // both have the same height.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if reloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(titlebarInk)
                        }
                    }
                    .disabled(reloading)
                    .help("Neu laden")
                    .accessibilityLabel("Neu laden")

                    SettingsLink {
                        Image(systemName: "gearshape")
                            .foregroundStyle(titlebarInk)
                    }
                    .help("Einstellungen")
                    .accessibilityLabel("Einstellungen")

                    Menu {
                        Button("Weiterschauen") { app.selection = .recents }
                        Button("Kalender") { app.selection = .calendar }
                        Button("Ankündigungen") { app.selection = .announcements }
                        Divider()
                        Button("Abmelden …") { account.confirmSignOut() }
                            .disabled(account.isSigningOut)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(titlebarInk)
                    }
                    .menuIndicator(.hidden)
                    .help("Weitere Bereiche")
                    .accessibilityLabel("Weitere Bereiche")
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbarVisibility(!showsApp ? .hidden : .automatic, for: .windowToolbar)
            .navigationTitle("")
            .onPreferenceChange(TitlebarBackdropKey.self) { heroUnderTitlebar = $0 }
            .onPreferenceChange(TitlebarScrimKey.self) { titlebarScrolled = $0 }
            .onPreferenceChange(TrailingColumnKey.self) { trailingColumn = $0 }
            .onPreferenceChange(LivePageGeometryKey.self) { livePage = $0 }

            .task {
                // Notifications reopen the window through this after it closed.
                app.openMainWindow = { [openWindow] in openWindow(id: MainWindowSize.sceneID) }
                await app.start()
                started = true
            }
            .task(id: SessionKey(started: started, signedIn: app.hasCredentials, generation: app.accountGeneration)) {
                // Without a login nothing is loaded and nothing runs in the
                // background.
                guard started, app.hasCredentials else {
                    // Only a sign-out stops the checks; the window opening
                    // before the start is read must not end the background ones.
                    if started { watcher.stop() }
                    return
                }
                await account.load()
                // The watcher needs the session, so it starts after the login.
                watcher.start()
            }
            .task(id: started && app.hasCredentials) {
                // Keeps the red dot of the Live section current on every screen.
                guard started, app.hasCredentials else { return }
                while !Task.isCancelled {
                    await live.checkStatus()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    /// The narrowest window in which the centred navigation pill and a
    /// column at the right edge do not meet, capped by the screen; 0 when no
    /// column is there.
    private var windowFloor: CGFloat {
        guard pillWidth > 0 else { return 0 }
        // The pill stands in the middle of the toolbar; the brand button and
        // the three buttons on the right need their room beside it. Without
        // it the toolbar squeezes the pill and its words break apart.
        let toolbar = pillWidth + 260
        guard app.selection == .live, trailingColumn > 0 else { return toolbar }
        let needed = max(toolbar, (2 * (trailingColumn + Space.l) + pillWidth).rounded(.up))
        let screen = NSScreen.main?.visibleFrame.width ?? needed
        return min(needed, screen)
    }

    /// The smallest window of the open page.
    private var pageMinimum: NSSize {
        MainWindowSize.minimum(on: nil)
    }

    /// Whether the app itself shows: started, and an account signed in.
    private var showsApp: Bool { started && !account.needsLogin }

    private var titlebarInk: Color { heroUnderTitlebar ? .white : Palette.textPrimary }

    /// The fade behind the toolbar while content runs under it. In the dark
    /// it is darker than the page; in the light it takes the page color, so
    /// the dark ink of the bar stays readable.
    private var titlebarScrim: some View {
        let dark = colorScheme == .dark
        let color: Color = dark ? .black : Palette.background
        return LinearGradient(
            stops: [
                .init(color: color.opacity(dark ? 0.97 : 0.94), location: 0),
                .init(color: color.opacity(dark ? 0.86 : 0.72), location: 0.34),
                .init(color: color.opacity(dark ? 0.42 : 0.28), location: 0.70),
                .init(color: color.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
            .frame(height: 98)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
    }

    /// Reloads what the open screen shows: the catalog and, when a format is
    /// open, its episodes; the other areas read their own data. The forced
    /// calls skip the stored answers, so the button really refreshes.
    private func reload() async {
        guard !reloading else { return }
        reloading = true
        defer { reloading = false }
        switch app.selection {
        case .live:
            await live.load(force: true)
        case .announcements:
            await announcements.load(force: true)
        case .calendar:
            await calendar.load(force: true)
        case .downloads:
            // Downloads report their progress by themselves.
            break
        default:
            await browse.reloadFormats(force: true)
            await browse.loadPremium(force: true)
            if case .episodes(let pid) = routeSelection(), let format = browse.formats.first(where: { $0.pid == pid }) {
                let year = browse.yearFilter
                await browse.openFormat(format, force: true)
                browse.yearFilter = year
            }
            switch app.selection {
            case .recents: await browse.loadRecents(force: true)
            case .bookmarks: await browse.loadBookmarks(force: true)
            default: break
            }
        }
        app.show("Aktualisiert")
    }

    /// The format that is open below the catalog, when the Mediathek shows
    /// one.
    private func routeSelection() -> BrowseRoute? {
        browse.formatsPath.last
    }

    private let sections: [(SidebarItem, String)] = [
        (.formats, "Mediathek"),
        (.live, "Live"),
        (.bookmarks, "Merkliste"),
        (.downloads, "Downloads"),
        (.search, "Suche"),
    ]

    @ViewBuilder
    private var screen: some View {
        if !started {
            Color.clear
        } else if account.needsLogin {
            LoginScreen()
        } else {
            switch app.selection {
            case .recents: ClipListScreen(kind: .recents)
            case .bookmarks: ClipListScreen(kind: .bookmarks)
            case .calendar: CalendarScreen()
            case .live: LiveScreen()
            case .downloads: DownloadsScreen()
            case .announcements: AnnouncementsScreen()
            case .search: SearchScreen()
            default: FormatsScreen()
            }
        }
    }
}

/// What decides whether the account is loaded: the start, the login and the
/// account itself.
private struct SessionKey: Hashable {
    let started: Bool
    let signedIn: Bool
    let generation: Int
}

/// The app name in the leading slot of the window toolbar.
private struct BrandChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.selection = .formats
        } label: {
            IrisColorMark()
                .frame(width: 26, height: 26)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Zur Mediathek")
        .accessibilityLabel("Orangeflix, zur Mediathek")
    }
}

/// Where the capsule of the navigation pill stands: its left edge and its
/// width.
struct PillPlace: Equatable {
    var x: CGFloat = 0
    var width: CGFloat = 0
}

/// The motion of the capsule in the navigation pill.
///
/// The toolbar of macOS builds its items anew when the screen changes, so the
/// pill loses its state right after a click and an implicit animation dies
/// with it. This object outlives the pill: it keeps the measured widths and
/// where and when the last slide began, and the pill draws the slide from it
/// frame by frame, whichever copy of the pill is on screen.
@MainActor @Observable
final class PillMotion {
    /// The widths of the sections, measured in the pill.
    var widths: [SidebarItem: CGFloat] = [:]
    /// Where the capsule stood when the slide began.
    @ObservationIgnored var from = PillPlace()
    /// When the slide began.
    @ObservationIgnored var start = Date.distantPast
    /// True while the capsule slides; the pill draws frames only then.
    var isSliding = false

    /// The spring of the slide: it runs a little over the target and
    /// settles back, so the change is felt and not just seen.
    static let spring = Spring(response: 0.38, dampingRatio: 0.74)

    /// Where the capsule stands at a moment, sliding from where it was
    /// towards the target.
    func place(at date: Date, target: PillPlace) -> PillPlace {
        guard isSliding, from.width > 0 else { return target }
        let time = date.timeIntervalSince(start)
        guard time < Self.spring.settlingDuration else { return target }
        let progress = CGFloat(Self.spring.value(target: 1.0, time: max(time, 0)))
        return PillPlace(x: from.x + (target.x - from.x) * progress,
                         width: max(0, from.width + (target.width - from.width) * progress))
    }
}

/// The navigation pill of the toolbar: the sections as buttons and the
/// chosen one as a capsule that slides from one to the other. The Live
/// section carries a blinking red dot while a show runs.
private struct NavPill: View {
    /// The sections of the pill and their names.
    let items: [(SidebarItem, String)]
    /// The section that is chosen.
    let current: SidebarItem
    /// The widths and the slide; they outlive this view.
    let motion: PillMotion
    /// Whether a section shows the red dot of a running show.
    let showsLiveDot: (SidebarItem) -> Bool
    /// Called with the section that was clicked.
    let onSelect: (SidebarItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The height of the sliding capsule. The toolbar glass is 36 high, so
    /// the capsule keeps an even rim of 3 around it.
    private static let capsuleHeight: CGFloat = 30
    /// How far the capsule stays inside its section on either side. It
    /// never reaches into the neighbour, so it does not run into the
    /// pointer's capsule there or into the rounded end of the glass.
    static let capsuleInset: CGFloat = 1

    var body: some View {
        ZStack(alignment: .leading) {
            TimelineView(.animation(paused: !motion.isSliding)) { context in
                capsule(at: motion.place(at: context.date, target: target))
            }
            .allowsHitTesting(false)
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { item, title in
                    ToolbarSection(title: title, isCurrent: item == current,
                                   showsLiveDot: showsLiveDot(item)) {
                        select(item)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        if motion.widths[item] != width { motion.widths[item] = width }
                    }
                }
            }
        }
        .task(id: motion.start) {
            // Ends the slide when the spring has settled, so the timeline
            // stops drawing. A new copy of the pill picks up the rest.
            guard motion.isSliding else { return }
            let left = PillMotion.spring.settlingDuration - Date.now.timeIntervalSince(motion.start)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled else { return }
            motion.isSliding = false
        }
    }

    /// Starts the slide from where the capsule stands now, then chooses the
    /// section.
    private func select(_ item: SidebarItem) {
        guard item != current else { return }
        if !reduceMotion {
            let now = Date.now
            motion.from = motion.place(at: now, target: target)
            motion.start = now
            motion.isSliding = true
        }
        onSelect(item)
    }

    /// The chosen section as a capsule.
    private func capsule(at place: PillPlace) -> some View {
        Capsule()
            .fill(Palette.surface)
            .overlay {
                // A soft edge: in the light theme the surface and the glass
                // are the same white, and without the edge the chosen
                // section would vanish.
                Capsule().strokeBorder(Palette.textPrimary.opacity(0.14), lineWidth: 1)
            }
            .frame(width: place.width, height: Self.capsuleHeight)
            .offset(x: place.x)
            .opacity(place.width > 0 ? 1 : 0)
    }

    /// Where the capsule belongs: on the chosen section.
    private var target: PillPlace {
        var x: CGFloat = 0
        for (item, _) in items {
            let width = motion.widths[item] ?? 0
            if item == current {
                guard width > 0 else { return PillPlace() }
                return PillPlace(x: x + Self.capsuleInset,
                                 width: width - 2 * Self.capsuleInset)
            }
            x += width
        }
        return PillPlace()
    }
}

/// One section of the navigation pill.
private struct ToolbarSection: View {
    let title: String
    let isCurrent: Bool
    var showsLiveDot = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsLiveDot {
                    BlinkingLiveDot()
                        .transition(.scale.combined(with: .opacity))
                }
                // The bold word holds the room, so a section is as wide
                // chosen as not; otherwise the words beside it would jump
                // while the capsule slides.
                Text(title)
                    .font(AppFont.subheading)
                    .hidden()
                    .overlay {
                        Text(title)
                            .font(isCurrent ? AppFont.subheading : AppFont.body)
                            .foregroundStyle(Palette.textPrimary.opacity(isCurrent ? 1 : 0.85))
                    }
                    // The word never breaks into two lines under a clipped
                    // title.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            // Room enough that the word sits well inside the capsule,
            // which now stays within the section.
            .padding(.horizontal, 15)
            .frame(height: 30)
            .background {
                // The pointer shows its own capsule; the chosen section
                // already has the sliding one.
                if hovering && !isCurrent {
                    Capsule()
                        .fill(Palette.surface.opacity(0.5))
                        .frame(height: 30)
                        .padding(.horizontal, NavPill.capsuleInset)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: showsLiveDot)
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .help(showsLiveDot ? "Gerade live" : "")
    }
}

/// The red mark of a running show. It pulses slowly; with reduced motion it
/// stays lit.
private struct BlinkingLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Palette.live)
            .frame(width: 7, height: 7)
            .opacity(dimmed ? 0.25 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityLabel("Live")
    }
}

/// The toolbar glass can sit over a bright or busy hero image, regardless of
/// the window's appearance. A translucent theme-colored backing keeps the
/// navigation readable without losing the glass around it.
private struct ToolbarPill: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .frame(height: 36)
                .background(Palette.background.opacity(reduceTransparency ? 1 : 0.90), in: Capsule())
        } else {
            content
                .frame(height: 36)
                .background(Palette.background.opacity(reduceTransparency ? 1 : 0.90), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// The round icon button used in the headers of screens.
struct IconAction: View {
    let icon: String
    /// The word of the tooltip; it is also the accessibility label.
    let help: String
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Chrome.actionSize, height: Chrome.actionSize)
                .glassPlate(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The "…" menu that carries the actions of a screen.
struct MoreMenu<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Chrome.actionSize, height: Chrome.actionSize)
                .glassPlate(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Aktionen")
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder
    func flatInTitlebar() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// The Live page lies between its smallest picture and the screen; the
/// window keeps its proportions there (`LiveWindowSizing`). Every other
/// screen has its minimum and grows freely.
private struct PageSizing: ViewModifier {
    let live: LivePageGeometry?
    /// The width the toolbar needs; a fixed size keeps it too.
    let floor: CGFloat
    let minWidth: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        if let live {
            // The screen is the upper bound; `LiveWindowSizing` keeps it.
            let lower = live.minPage
            content.frame(minWidth: max(lower.width, floor), maxWidth: .infinity,
                          minHeight: lower.height, maxHeight: .infinity)
        } else {
            content.frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
        }
    }
}

/// The width of a column a screen keeps at the right edge of the window,
/// under the toolbar; the window grows so the navigation pill stays clear
/// of it.
struct TrailingColumnKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// True while a screen's content is scrolled under the toolbar, so the
/// window draws a scrim behind the bar.
struct TitlebarScrimKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct TitlebarBackdropKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
