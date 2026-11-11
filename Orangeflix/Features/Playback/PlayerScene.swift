import AppKit
import SwiftUI

/// The player window and inline video stage. `mpv` fills the frame while a
/// floating dark-glass control deck sits along the bottom edge, fading out
/// when idle and leaving a thin orange progress hairline behind.
struct PlayerScreen: View {
    /// The playback that runs.
    let playback: PlaybackCenter
    /// Whether the player sits in a page instead of its own window.
    var inline = false

    @State private var chromeVisible = true
    /// Follows the window, so the full-screen button shows the way back.
    @State private var isFullScreen = false
    @State private var activity = PlayerActivity()
    @State private var pointerOverPanel = false
    @State private var scrub: Double?
    @State private var flash: PlayerFlash?
    /// The pictures of the timeline of the running episode.
    @State private var thumbnails = TimelineThumbnailStore()
    @FocusState private var focused: Bool

    private var engine: MPVPlayer { playback.engine }
    private var isLive: Bool { playback.current?.kind == .live }

    var body: some View {
        stack
            .ignoresSafeArea(edges: safeAreaEdges)
            .environment(\.colorScheme, .dark)
            .animation(.easeOut(duration: 0.22), value: chromeVisible)
            .animation(.easeOut(duration: 0.18), value: flash)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: upNext?.id)
            .onContinuousHover { phase in
                if case .active = phase { wake() }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press) }
            .onAppear {
                focused = true
                wake()
            }
            .onAppear { thumbnails.load(track: playback.current?.thumbnailTrack) }
            .onChange(of: playback.current?.thumbnailTrack) { _, track in
                thumbnails.load(track: track)
            }
            .task { await hideWhenIdle() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
                if note.object as? NSWindow === PlayerWindows.current { isFullScreen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
                if note.object as? NSWindow === PlayerWindows.current { isFullScreen = false }
            }
            .onChange(of: chromeVisible, initial: true) { _, visible in
                engine.setSubtitleMargin(visible ? 160 : 48)
            }
            .background {
                if !inline {
                    PlayerWindowBridge(playback: playback, chromeVisible: chromeVisible || !playback.isPlaying,
                                       videoSize: engine.videoSize)
                }
            }
            .navigationTitle("")
    }

    /// The window draws under its titlebar; a page keeps its layout.
    private var safeAreaEdges: Edge.Set { inline ? [] : .all }

    private var stack: some View {
        ZStack {
            Color.black
            if playback.isInPiP {
                pipPlaceholder
            } else {
                MPVVideoView(player: engine)
            }
            inputLayer
            if playback.isPlaying && engine.isBuffering && !playback.isInPiP {
                ProgressView()
                    .controlSize(.large)
                    .allowsHitTesting(false)
            }
            if let flash {
                PlayerFlashView(flash: flash)
                    .id(flash.id)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
            if !inline {
                // Gentle top shade only for the standalone window's traffic lights.
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 82)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
            controls
            if !chromeVisible && !isLive && !playback.isInPiP {
                PlayerHairline(fraction: fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
    }

    private var pipPlaceholder: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "pip")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
            Text("Läuft im Bild-in-Bild")
                .font(AppFont.heading)
                .foregroundStyle(.white)
            PillButton(title: "Hier weitersehen", symbol: "pip.exit", style: .onPicture) {
                playback.exitPiP()
            }
        }
    }

    /// The next episode card and the floating control deck along the bottom.
    private var controls: some View {
        VStack(spacing: Space.m) {
            Spacer(minLength: 0)
            if let next = upNext {
                HStack {
                    Spacer(minLength: 0)
                    PlayerUpNextCard(entry: next) { playback.playNext() }
                }
                .padding(.horizontal, inline ? Space.l : Space.xl)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            PlayerControlPanel(playback: playback, isFullScreen: isFullScreen, inline: inline,
                               queueLabel: queueLabel, scrub: $scrub, thumbnails: thumbnails, flash: show)
                .onHover { pointerOverPanel = $0 }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
    }

    /// A click holds or resumes, a double click toggles full screen (or pops out inline).
    private var inputLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2).onEnded { enlarge() }
                    .exclusively(before: TapGesture().onEnded { togglePause() }))
    }

    private func enlarge() {
        if inline { playback.popOut() } else { PlayerWindows.toggleFullScreen() }
    }

    private var fraction: Double {
        guard playback.duration > 0 else { return 0 }
        return min(max(playback.position / playback.duration, 0), 1)
    }

    /// "2 / 5" while a queue of episodes plays.
    private var queueLabel: String? {
        guard playback.queue.count > 1, let current = playback.current,
              let index = playback.queue.firstIndex(where: { $0.id == current.id }) else { return nil }
        return "\(index + 1) / \(playback.queue.count)"
    }

    /// The next episode, shown in the last half minute of the running one.
    private var upNext: PlaybackEntry? {
        guard let next = playback.nextEntry, playback.duration > 0, playback.position > 0,
              playback.duration - playback.position < 30 else { return nil }
        return next
    }

    // MARK: Showing and hiding

    private func wake() {
        activity.last = Date()
        if !chromeVisible { chromeVisible = true }
    }

    private func hideWhenIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            let idle = Date().timeIntervalSince(activity.last) > 2.5
            let holds = engine.isPaused || !playback.isPlaying || pointerOverPanel || scrub != nil || playback.isInPiP
            if chromeVisible && idle && !holds {
                chromeVisible = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private func show(_ symbol: String, _ text: String? = nil) {
        flash = PlayerFlash(symbol: symbol, text: text)
        let id = flash?.id
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if flash?.id == id { flash = nil }
        }
    }

    // MARK: Input

    private func togglePause() {
        guard playback.isPlaying else { return }
        show(engine.isPaused ? "play.fill" : "pause.fill")
        playback.togglePlayPause()
        wake()
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        switch press.key {
        case .space:
            togglePause()
            return .handled
        case .leftArrow:
            skip(-5)
        case .rightArrow:
            skip(5)
        case .upArrow:
            changeVolume(by: 5)
        case .downArrow:
            changeVolume(by: -5)
        case .escape:
            guard isFullScreen else { return .ignored }
            PlayerWindows.toggleFullScreen()
        default:
            switch press.characters.lowercased() {
            case "k": togglePause()
            case "j": skip(-10)
            case "l": skip(10)
            case "f": enlarge()
            case "p":
                guard playback.canUsePiP else { return .ignored }
                playback.togglePiP()
            case "m":
                engine.toggleMute()
                show(engine.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            case "c": toggleSubtitles()
            case "n":
                guard playback.nextEntry != nil else { return .ignored }
                playback.playNext()
            default:
                return .ignored
            }
        }
        wake()
        return .handled
    }

    private func skip(_ seconds: Double) {
        if isLive, seconds > 0, !playback.isAtLiveEdge, playback.secondsBehindLive(at: Date()) <= seconds {
            playback.goLive()
            show("dot.radiowaves.left.and.right", "Live")
            return
        }
        playback.skip(by: seconds)
        let symbol = seconds < 0 ? "gobackward" : "goforward"
        let text = seconds < 0 ? "−\(Int(-seconds)) s" : "+\(Int(seconds)) s"
        show(symbol, text)
    }

    private func changeVolume(by step: Double) {
        let value = min(max(engine.volume + step, 0), 100)
        engine.setVolume(value)
        show(value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", "\(Int(value)) %")
    }

    private func toggleSubtitles() {
        guard !engine.subtitleTracks.isEmpty else { return }
        let on = !engine.showsSubtitles
        playback.setSubtitlesOn(on)
        show(on ? "captions.bubble.fill" : "captions.bubble", on ? "Untertitel an" : "Untertitel aus")
    }
}

private final class PlayerActivity {
    var last = Date()
}

// MARK: - Floating Control Deck

/// Modern 3-zone floating dark-glass control deck:
/// - Row 1: Timeline flanked by elapsed and clickable remaining/total time
/// - Row 2: Volume on the left, dead-center hero transport in the middle,
///   grouped media & window/PiP controls on the right.
private struct PlayerControlPanel: View {
    let playback: PlaybackCenter
    let isFullScreen: Bool
    let inline: Bool
    let queueLabel: String?
    @Binding var scrub: Double?
    let thumbnails: TimelineThumbnailStore
    let flash: (String, String?) -> Void

    @State private var width: CGFloat = 900
    /// Click on the right timestamp switches between total duration and remaining time.
    @State private var showsRemaining = true

    private var engine: MPVPlayer { playback.engine }
    private var isLive: Bool { playback.current?.kind == .live }
    private var chapters: [PlaybackChapter] { isLive ? [] : playback.current?.chapters ?? [] }
    private static let deckMaxWidth: CGFloat = 940

    var body: some View {
        VStack(spacing: Space.m) {
            if !inline {
                titleHeader
                    .frame(maxWidth: Self.deckMaxWidth, alignment: .leading)
            }
            deck
                .frame(maxWidth: Self.deckMaxWidth)
        }
        .padding(.horizontal, inline ? Space.l : Space.xl)
        .padding(.bottom, inline ? Space.l : Space.xl)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) { shade }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var shade: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(0.32), location: 0.48),
            .init(color: .black.opacity(0.72), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: inline ? 150 : 210)
        .allowsHitTesting(false)
    }

    private var deck: some View {
        let deckShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 8) {
            if !isLive || playback.duration > 1 {
                timelineRow
            }
            controlRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            deckShape
                .fill(.black.opacity(0.46))
                .background(.ultraThinMaterial, in: deckShape)
        }
        .overlay {
            deckShape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 20, y: 8)
    }

    /// Format eyebrow, episode title and active chapter above the deck in the player window.
    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let detail = playback.current?.detail, !detail.isEmpty {
                Text(detail.uppercased())
                    .font(AppFont.captionMedium)
                    .tracking(1.1)
                    .foregroundStyle(Palette.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(playback.current?.title ?? "")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let queueLabel {
                    Text(queueLabel)
                        .font(AppFont.digitsMedium)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            }
            if let chapter = PlaybackChapter.current(chapters, at: scrub ?? playback.position),
               !chapter.title.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text(chapter.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }
            }
        }
        .playerOutline()
        .allowsHitTesting(false)
    }

    // MARK: Row 1 — Timeline + Flanking Timecodes

    private var timelineRow: some View {
        let shown = scrub ?? playback.position
        return HStack(spacing: 10) {
            if !isLive {
                Text(AppFormat.position(shown))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(minWidth: 42, alignment: .leading)
            }

            PlayerTimeline(
                position: playback.position,
                duration: playback.duration,
                bufferedAhead: engine.bufferedAhead,
                scrub: $scrub,
                seek: { seconds, exact in
                    playback.seek(to: seconds, exact: exact)
                },
                chapters: chapters,
                thumbnails: isLive ? nil : thumbnails
            )

            if isLive {
                PlayerGoLiveButton(playback: playback)
            } else {
                durationButton(shown: shown)
            }
        }
    }

    private func durationButton(shown: Double) -> some View {
        let label = showsRemaining
            ? "−" + AppFormat.position(max(playback.duration - shown, 0))
            : AppFormat.position(playback.duration)
        return Button {
            showsRemaining.toggle()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.84))
                .frame(minWidth: 48, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsRemaining ? "Gesamtlänge zeigen" : "Restzeit zeigen")
    }

    // MARK: Row 2 — 3-Zone Control Bar

    private var controlRow: some View {
        ZStack {
            HStack(spacing: 6) {
                leadingZone
                Spacer(minLength: 0)
            }
            transportZone
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                trailingZone
            }
        }
        .frame(height: 44)
    }

    /// Left zone: Audio volume (and Live badge when no timeline is shown).
    private var leadingZone: some View {
        HStack(spacing: 6) {
            PlayerVolumeControl(engine: engine, showsSlider: width >= 540)
            if isLive && playback.duration <= 1 {
                PlayerGoLiveButton(playback: playback)
            }
        }
    }

    /// Center zone: Symmetrical transport anchored on the hero Play/Pause circle.
    private var transportZone: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if isLive {
                    PlayerIconButton(symbol: "gobackward.30", help: "30 Sekunden zurückspulen") {
                        playback.skip(by: -30)
                    }
                }
                PlayerIconButton(symbol: "gobackward.10", help: "10 Sekunden zurück (J)", prominent: true) {
                    playback.skip(by: -10)
                }
            }
            .frame(width: 76, alignment: .trailing)

            PlayerPlayButton(isPaused: engine.isPaused) {
                flash(engine.isPaused ? "play.fill" : "pause.fill", nil)
                playback.togglePlayPause()
            }

            HStack(spacing: 4) {
                if !isLive {
                    PlayerIconButton(symbol: "goforward.10", help: "10 Sekunden vor (L)", prominent: true) {
                        playback.skip(by: 10)
                    }
                }
                if let next = playback.nextEntry {
                    PlayerIconButton(symbol: "forward.end.fill", help: "Nächste Folge: \(next.title) (N)") {
                        playback.playNext()
                    }
                }
            }
            .frame(width: 76, alignment: .leading)
        }
    }

    /// Right zone: Chapters · Subtitles · Audio · Speed  |  PiP · Window / Fullscreen.
    private var trailingZone: some View {
        let hasMediaGroup = (!chapters.isEmpty && width >= 660)
            || (!engine.subtitleTracks.isEmpty && width >= 560)
            || (engine.audioTracks.count > 1 && width >= 620)
            || (!isLive && width >= 600)

        return HStack(spacing: 4) {
            if width >= 660, !chapters.isEmpty {
                PlayerChapterMenu(chapters: chapters, playback: playback)
            }
            if width >= 560, !engine.subtitleTracks.isEmpty {
                PlayerSubtitleButton(engine: engine, playback: playback)
            }
            if width >= 620, engine.audioTracks.count > 1 {
                PlayerAudioMenu(engine: engine)
            }
            if width >= 600, !isLive {
                PlayerSpeedMenu(engine: engine)
            }

            if hasMediaGroup {
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 4)
            }

            if playback.canUsePiP {
                PlayerIconButton(
                    symbol: playback.isInPiP ? "pip.exit" : "pip.enter",
                    help: playback.isInPiP ? "Bild-in-Bild beenden (P)" : "Bild-in-Bild (P)",
                    isActive: playback.isInPiP
                ) {
                    playback.togglePiP()
                }
            }

            if inline {
                PlayerIconButton(symbol: "macwindow.on.rectangle", help: "Im eigenen Fenster abspielen (F)") {
                    playback.popOut()
                }
            } else {
                if width >= 760 {
                    PlayerSizeMenu()
                }
                PlayerIconButton(
                    symbol: isFullScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    help: isFullScreen ? "Vollbild beenden (F, Esc)" : "Vollbild (F)"
                ) {
                    PlayerWindows.toggleFullScreen()
                }
            }
        }
    }
}

// MARK: - Timeline

/// Scrubber timeline with chapter notches, hover height expansion and a
/// glassmorphic thumbnail preview card.
struct PlayerTimeline: View {
    let position: Double
    let duration: Double
    let bufferedAhead: Double
    @Binding var scrub: Double?
    let seek: (Double, Bool) -> Void
    var chapters: [PlaybackChapter] = []
    var thumbnails: TimelineThumbnailStore?

    @State private var hoverX: CGFloat?

    private static let handleSize: CGFloat = 13
    private static let previewWidth: CGFloat = 236

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let played = fraction(scrub ?? position)
            let buffered = fraction(position + bufferedAhead)
            let active = hoverX != nil || scrub != nil
            let barHeight: CGFloat = active ? 6 : 4
            let accent = Palette.accent
            let gaps = chapterFractions

            Canvas { context, size in
                let bar = CGRect(origin: .zero, size: size)
                context.clip(to: Path(roundedRect: bar, cornerRadius: size.height / 2))
                context.fill(Path(bar), with: .color(.white.opacity(0.22)))
                let playedX = size.width * played
                let bufferedX = size.width * buffered
                if bufferedX > playedX {
                    context.fill(
                        Path(CGRect(x: playedX, y: 0, width: bufferedX - playedX, height: size.height)),
                        with: .color(.white.opacity(0.34))
                    )
                }
                context.fill(Path(CGRect(x: 0, y: 0, width: playedX, height: size.height)), with: .color(accent))
                context.blendMode = .clear
                for gap in gaps {
                    context.fill(
                        Path(CGRect(x: size.width * gap - 1, y: 0, width: 2, height: size.height)),
                        with: .color(.black)
                    )
                }
            }
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .scaleEffect(active ? 1 : 0.01)
                    .opacity(active ? 1 : 0)
                    .offset(x: width * played - Self.handleSize / 2)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                if let x = scrub.map({ CGFloat(fraction($0)) * width }) ?? hoverX, duration > 0 {
                    scrubPreview(at: Double(x / width) * duration)
                        .frame(width: Self.previewWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(
                            x: min(max(x - Self.previewWidth / 2, -8), max(width - Self.previewWidth + 8, -8)),
                            y: -(geometry.size.height + 8)
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { hoverX = min(max(point.x, 0), width) } else { hoverX = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard duration > 0 else { return }
                    let seconds = seconds(at: value.location.x, width: width)
                    scrub = seconds
                    seek(seconds, false)
                }
                .onEnded { value in
                    guard duration > 0 else { return }
                    seek(seconds(at: value.location.x, width: width), true)
                    scrub = nil
                })
            .animation(.easeOut(duration: 0.14), value: active)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(AppFormat.position(scrub ?? position))
        .accessibilityAdjustableAction { direction in
            let value = scrub ?? position
            switch direction {
            case .increment: seek(min(value + 10, duration), true)
            case .decrement: seek(max(value - 10, 0), true)
            @unknown default: break
            }
        }
    }

    private func fraction(_ seconds: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1)
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        Double(min(max(x, 0), width) / width) * duration
    }

    private var chapterFractions: [Double] {
        guard duration > 0 else { return [] }
        return chapters.filter { $0.start > 1 }.map { min(max($0.start / duration, 0), 1) }
    }

    private func scrubPreview(at seconds: Double) -> some View {
        let frameShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 6) {
            if let chapter = PlaybackChapter.current(chapters, at: seconds), !chapter.title.isEmpty {
                pill(chapter.title, isAccent: false)
            }
            if let picture = thumbnails?.image(at: seconds) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 224, height: 126)
                    .clipShape(frameShape)
                    .overlay {
                        frameShape.strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 14, y: 5)
            }
            pill(AppFormat.position(seconds), isAccent: true)
        }
    }

    private func pill(_ text: String, isAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.black.opacity(0.75), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isAccent ? Palette.accent.opacity(0.45) : .white.opacity(0.16), lineWidth: 1)
            }
            .frame(maxWidth: Self.previewWidth)
    }
}

// MARK: - Controls & Hover Styles

/// Hero center transport button: crisp white circle with dark glyph.
struct PlayerPlayButton: View {
    let isPaused: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(white: 0.08))
                .offset(x: isPaused ? 1.5 : 0)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.white.opacity(hovering ? 1.0 : 0.92))
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlayerPressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(isPaused ? "Abspielen (Leertaste)" : "Anhalten (Leertaste)")
    }
}

private struct PlayerPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Round icon control with calm circular glass hover highlight.
struct PlayerIconButton: View {
    let symbol: String
    var help = ""
    var isDisabled = false
    var prominent = false
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlayerGlyph(symbol: symbol, prominent: prominent)
        }
        .buttonStyle(PlayerChromeButtonStyle(isActive: isActive))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Menu trigger label sharing the same circular/capsule hover treatment.
struct PlayerIconLabel: View {
    let symbol: String?
    var text: String?
    var isActive = false

    var body: some View {
        PlayerChrome(isPill: text != nil, isActive: isActive) {
            PlayerGlyph(symbol: symbol, text: text)
        }
    }
}

private struct PlayerGlyph: View {
    let symbol: String?
    var text: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 17 : 15, weight: .medium))
            }
            if let text {
                Text(text)
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            }
        }
        .padding(.horizontal, text == nil ? 0 : 10)
    }
}

private struct PlayerChromeButtonStyle: ButtonStyle {
    var isPill = false
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        PlayerChrome(isPressed: configuration.isPressed, isPill: isPill, isActive: isActive) {
            configuration.label
        }
    }
}

/// Clean translucent circular/capsule hover highlight — no square box, no 1.15x
/// ballooning, no neon shadow.
private struct PlayerChrome<Content: View>: View {
    var isPressed = false
    var isPill = false
    var isActive = false
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        content
            .foregroundStyle(foregroundColor)
            .frame(minWidth: isPill ? 0 : 34, minHeight: 34)
            .background {
                Capsule()
                    .fill(backgroundFill)
            }
            .scaleEffect(isPressed ? 0.93 : 1)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }

    private var foregroundColor: Color {
        if isActive { return Palette.accent }
        return hovering ? .white : .white.opacity(0.86)
    }

    private var backgroundFill: Color {
        if isPressed {
            return isActive ? Palette.accent.opacity(0.30) : .white.opacity(0.22)
        }
        if hovering {
            return isActive ? Palette.accent.opacity(0.24) : .white.opacity(0.14)
        }
        return isActive ? Palette.accent.opacity(0.16) : .clear
    }
}

private extension View {
    func playerOutline() -> some View {
        shadow(color: .black.opacity(0.65), radius: 2, y: 1)
    }
}

/// Speaker mute button paired with a smooth capsule volume slider.
struct PlayerVolumeControl: View {
    let engine: MPVPlayer
    var showsSlider = true

    var body: some View {
        HStack(spacing: 4) {
            PlayerIconButton(
                symbol: symbol,
                help: engine.isMuted ? "Ton an (M)" : "Stumm (M)",
                isActive: engine.isMuted
            ) {
                engine.toggleMute()
            }
            if showsSlider {
                PlayerMiniSlider(value: engine.isMuted ? 0 : engine.volume / 100) { engine.setVolume($0 * 100) }
                    .frame(width: 72)
                    .help("Lautstärke")
            }
        }
    }

    private var symbol: String {
        if engine.isMuted || engine.volume == 0 { return "speaker.slash.fill" }
        if engine.volume < 34 { return "speaker.wave.1.fill" }
        if engine.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct PlayerMiniSlider: View {
    let value: Double
    let change: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(hovering ? 1 : 0.88)).frame(width: width * clamped)
            }
            .frame(height: hovering ? 5.5 : 4)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: width * clamped - 5.5)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                change(Double(min(max(drag.location.x, 0), width) / width))
            })
        }
        .frame(height: 22)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PlayerSpeedMenu: View {
    let engine: MPVPlayer

    private static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        Menu {
            Picker("Tempo", selection: Binding(get: { engine.speed }, set: { engine.setSpeed($0) })) {
                ForEach(Self.speeds, id: \.self) { speed in
                    Text(Self.label(speed)).tag(speed)
                }
            }
            .pickerStyle(.inline)
        } label: {
            PlayerIconLabel(symbol: nil, text: Self.label(engine.speed), isActive: abs(engine.speed - 1) > 0.01)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Wiedergabetempo")
    }

    private static func label(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed).replacingOccurrences(of: ".", with: ",")
    }
}

struct PlayerChapterMenu: View {
    let chapters: [PlaybackChapter]
    let playback: PlaybackCenter

    var body: some View {
        Menu {
            ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                Button {
                    playback.seek(to: chapter.start, exact: true)
                } label: {
                    Text("\(AppFormat.position(chapter.start))  \(chapter.title)")
                    if chapter.id == current?.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            PlayerIconLabel(symbol: "list.bullet")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(current.map { "Kapitel · \($0.title)" } ?? "Kapitel")
    }

    private var current: PlaybackChapter? {
        PlaybackChapter.current(chapters, at: playback.position)
    }
}

struct PlayerSubtitleButton: View {
    let engine: MPVPlayer
    let playback: PlaybackCenter

    var body: some View {
        PlayerIconButton(
            symbol: engine.showsSubtitles ? "captions.bubble.fill" : "captions.bubble",
            help: engine.showsSubtitles ? "Untertitel ausblenden (C)" : "Untertitel einblenden (C)",
            isActive: engine.showsSubtitles
        ) {
            playback.setSubtitlesOn(!engine.showsSubtitles)
        }
    }
}

struct PlayerAudioMenu: View {
    let engine: MPVPlayer

    var body: some View {
        Menu {
            Picker("Ton", selection: Binding(
                get: { engine.audioTracks.first(where: \.isSelected)?.id ?? 0 },
                set: { engine.selectAudio($0) })) {
                ForEach(engine.audioTracks) { track in
                    Text(track.label).tag(track.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            PlayerIconLabel(symbol: "waveform")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tonspur")
    }
}

struct PlayerLivePill: View {
    var body: some View {
        HStack(spacing: Space.xs) {
            Circle().fill(Palette.live).frame(width: 7, height: 7)
            Text("LIVE")
                .font(AppFont.captionMedium)
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(.white.opacity(0.14), in: Capsule())
    }
}

struct PlayerGoLiveButton: View {
    let playback: PlaybackCenter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let behind = playback.secondsBehindLive(at: context.date)
            let atEdge = playback.isAtLiveEdge
            Button {
                playback.goLive()
            } label: {
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(atEdge ? Palette.live : Color.white.opacity(0.9))
                        .frame(width: 7, height: 7)
                    Text(atEdge || behind < 1 ? "LIVE" : "−" + AppFormat.position(behind))
                        .font(AppFont.captionMedium)
                        .tracking(atEdge ? 1.2 : 0)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(atEdge ? Palette.live.opacity(0.28) : Color.white.opacity(0.16), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(atEdge ? Palette.live.opacity(0.45) : .white.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(atEdge)
            .help(atEdge ? "Am Live-Rand" : "Zum Live-Rand springen")
        }
    }
}

private struct PlayerSizeMenu: View {
    @State private var size = PlayerWindows.preferredSize

    var body: some View {
        Menu {
            Picker("Größe", selection: $size) {
                ForEach(PlayerWindows.Size.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.inline)
            .onChange(of: size) { _, new in
                PlayerWindows.resize(to: new)
            }
        } label: {
            PlayerIconLabel(symbol: "rectangle.on.rectangle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Fenstergröße")
    }
}

// MARK: - Overlays

private struct PlayerUpNextCard: View {
    let entry: PlaybackEntry
    let play: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("ALS NÄCHSTES")
                    .font(AppFont.captionMedium)
                    .tracking(1.2)
                    .foregroundStyle(Palette.accent)
                Text(entry.title)
                    .font(AppFont.subheading)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Button(action: play) {
                Label("Ansehen", systemImage: "play.fill")
                    .font(AppFont.subheading)
                    .foregroundStyle(Color(white: 0.08))
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.m)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}

struct PlayerFlash: Equatable {
    let id = UUID()
    let symbol: String
    var text: String?
}

private struct PlayerFlashView: View {
    let flash: PlayerFlash

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: flash.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            if let text = flash.text {
                Text(text)
                    .font(AppFont.subheading)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
        .allowsHitTesting(false)
    }
}

private struct PlayerHairline: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Palette.accent)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}
