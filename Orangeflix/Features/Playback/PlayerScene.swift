import AppKit
import SwiftUI

/// The player window. The picture of mpv fills it; the title floats at the
/// top and the controls in a glass panel at the bottom. Both fade out after
/// a moment without the pointer and leave a thin orange line behind.
/// `inline` shows the same player inside the page of an episode: without
/// the title, and the way to full size leads into the player window.
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
            engine.setSubtitleMargin(visible ? 150 : 48)
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
            MPVVideoView(player: engine)
            inputLayer
            if playback.isPlaying && engine.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .allowsHitTesting(false)
            }
            if let flash {
                PlayerFlashView(flash: flash)
                    .id(flash.id)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if !inline {
                // Only a shade, so the window buttons stand out; the title
                // sits at the bottom, above the timeline.
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
            controls
            if !chromeVisible && !isLive {
                PlayerHairline(fraction: fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
    }

    /// The next episode and the bar along the bottom edge.
    private var controls: some View {
        VStack(alignment: .trailing, spacing: Space.m) {
            Spacer(minLength: 0)
            if let next = upNext {
                PlayerUpNextCard(entry: next) { playback.playNext() }
                    .padding(.trailing, inline ? Space.m : Space.xl)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            PlayerControlPanel(playback: playback, isFullScreen: isFullScreen, inline: inline,
                               queueLabel: queueLabel, scrub: $scrub, thumbnails: thumbnails, flash: show)
                .onHover { pointerOverPanel = $0 }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
    }

    /// A click holds or resumes, a double click toggles the full screen; in
    /// a page it moves the playback into the player window.
    private var inputLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2).onEnded { enlarge() }
                    .exclusively(before: TapGesture().onEnded { togglePause() }))
    }

    /// The full screen of the window, or the window itself for a page.
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

    /// Hides the controls and the pointer after 2.5 seconds without input,
    /// unless the playback holds or the pointer rests on the panel.
    private func hideWhenIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            let idle = Date().timeIntervalSince(activity.last) > 2.5
            let holds = engine.isPaused || !playback.isPlaying || pointerOverPanel || scrub != nil
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

/// When the pointer or a key last moved. Kept out of the view state, so a
/// moving pointer does not redraw the window.
private final class PlayerActivity {
    var last = Date()
}

// MARK: - Bar

/// The bar along the bottom edge, after the look of ModernZ: a black shade
/// that fades upwards, in it the title, the timeline over the full width
/// and one row of buttons. The tracks, the volume and the time sit on the
/// left, the transport in the middle, chapters, speed and the window on the
/// right. What does not fit a narrow window drops out.
private struct PlayerControlPanel: View {
    let playback: PlaybackCenter
    let isFullScreen: Bool
    /// In a page the bar offers the player window instead of its size and
    /// the full screen, and leaves the title to the page.
    let inline: Bool
    /// "2 / 5" while a queue plays.
    let queueLabel: String?
    @Binding var scrub: Double?
    let thumbnails: TimelineThumbnailStore
    let flash: (String, String?) -> Void

    @State private var width: CGFloat = 1000
    /// The time counts down to the end instead of up from the start.
    @State private var showsRemaining = false

    private var engine: MPVPlayer { playback.engine }
    private var isLive: Bool { playback.current?.kind == .live }
    private var chapters: [PlaybackChapter] { isLive ? [] : playback.current?.chapters ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !inline {
                title
                    .padding(.horizontal, 25)
                    .padding(.bottom, Space.s)
            }
            if !isLive || playback.duration > 1 {
                PlayerTimeline(position: playback.position, duration: playback.duration,
                               bufferedAhead: engine.bufferedAhead, scrub: $scrub,
                               seek: { seconds, exact in
                                   playback.seek(to: seconds, exact: exact)
                               },
                               chapters: chapters,
                               thumbnails: isLive ? nil : thumbnails)
                    .padding(.horizontal, 15)
            }
            buttons
                .frame(height: 56)
                .padding(.horizontal, 15)
        }
        .padding(.top, Space.xxl)
        .background { shade }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Black at the bottom edge, clear well above the title.
    private var shade: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(0.45), location: 0.45),
            .init(color: .black.opacity(0.85), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.top, -80)
        .allowsHitTesting(false)
    }

    /// The format, the episode and below it the chapter that runs.
    private var title: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let detail = playback.current?.detail, !detail.isEmpty {
                Text(detail.uppercased())
                    .font(AppFont.captionMedium)
                    .tracking(1.2)
                    .foregroundStyle(Palette.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(playback.current?.title ?? "")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let queueLabel {
                    Text(queueLabel)
                        .font(AppFont.digitsMedium)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if let chapter = PlaybackChapter.current(chapters, at: scrub ?? playback.position),
               !chapter.title.isEmpty {
                Text(chapter.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .playerOutline()
        .allowsHitTesting(false)
    }

    private var buttons: some View {
        ZStack {
            HStack(spacing: Space.xs) {
                leading
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.xs) {
                Spacer(minLength: 0)
                trailing
            }
            transport
        }
    }

    @ViewBuilder
    private var leading: some View {
        if width >= 640, engine.audioTracks.count > 1 {
            PlayerAudioMenu(engine: engine)
        }
        if width >= 560, !engine.subtitleTracks.isEmpty {
            PlayerSubtitleButton(engine: engine, playback: playback)
        }
        PlayerVolumeControl(engine: engine, showsSlider: width >= 860)
        if isLive {
            PlayerGoLiveButton(playback: playback)
                .padding(.leading, Space.s)
        } else if width >= 480 {
            timeButton
                .padding(.leading, Space.xs)
        }
    }

    /// "12:34 / 45:00"; a click shows what is left instead.
    private var timeButton: some View {
        let shown = scrub ?? playback.position
        let current = showsRemaining
            ? "−" + AppFormat.position(max(playback.duration - shown, 0))
            : AppFormat.position(shown)
        return Button {
            showsRemaining.toggle()
        } label: {
            Text("\(current) / \(AppFormat.position(playback.duration))")
                .font(.system(size: 14, weight: .medium).monospacedDigit())
        }
        .buttonStyle(PlayerChromeButtonStyle(isText: true))
        .help(showsRemaining ? "Verstrichene Zeit zeigen" : "Restzeit zeigen")
    }

    /// Play in the exact middle, the jumps and the next episode on its sides.
    private var transport: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.m) {
                if isLive {
                    PlayerIconButton(symbol: "gobackward.30", help: "30 Sekunden zurückspulen", prominent: true) {
                        playback.skip(by: -30)
                    }
                }
                PlayerIconButton(symbol: "gobackward.10", help: "10 Sekunden zurück (J)", prominent: true) {
                    playback.skip(by: -10)
                }
            }
            .frame(width: Self.transportSide, alignment: .trailing)
            PlayerPlayButton(isPaused: engine.isPaused) {
                flash(engine.isPaused ? "play.fill" : "pause.fill", nil)
                playback.togglePlayPause()
            }
            HStack(spacing: Space.m) {
                if !isLive {
                    PlayerIconButton(symbol: "goforward.10", help: "10 Sekunden vor (L)", prominent: true) {
                        playback.skip(by: 10)
                    }
                }
                if let next = playback.nextEntry {
                    PlayerIconButton(symbol: "forward.end.fill", help: "Nächste Folge: \(next.title) (N)",
                                     prominent: true) {
                        playback.playNext()
                    }
                }
            }
            .frame(width: Self.transportSide, alignment: .leading)
        }
    }

    /// Room for two buttons on each side of play.
    private static let transportSide: CGFloat = 36 * 2 + Space.m

    @ViewBuilder
    private var trailing: some View {
        if width >= 760, !chapters.isEmpty {
            PlayerChapterMenu(chapters: chapters, playback: playback)
        }
        if width >= 680, !isLive {
            PlayerSpeedMenu(engine: engine)
        }
        if inline {
            PlayerIconButton(symbol: "macwindow.on.rectangle", help: "Im eigenen Fenster abspielen (F)") {
                playback.popOut()
            }
        } else {
            if width >= 820 {
                PlayerSizeMenu()
            }
            PlayerIconButton(symbol: isFullScreen
                                 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             help: isFullScreen ? "Vollbild beenden (F, Esc)" : "Vollbild (F)") {
                PlayerWindows.toggleFullScreen()
            }
        }
    }
}

/// The timeline: a thin bar over the full width. Played in the accent, what
/// was read ahead in a light band after it, a gap where a chapter begins and
/// an accent ring as the handle. Over it the pointer shows the picture and
/// the time it points at; a drag seeks.
struct PlayerTimeline: View {
    let position: Double
    let duration: Double
    let bufferedAhead: Double
    @Binding var scrub: Double?
    let seek: (Double, Bool) -> Void
    /// The chapters of the episode: a gap in the bar at every start.
    var chapters: [PlaybackChapter] = []
    /// The pictures of the timeline; nil while the file has none.
    var thumbnails: TimelineThumbnailStore?

    @State private var hoverX: CGFloat?

    private static let handle: CGFloat = 14.4
    private static let previewWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let played = fraction(scrub ?? position)
            let buffered = fraction(position + bufferedAhead)
            let active = hoverX != nil || scrub != nil
            let accent = Palette.accent
            let gaps = chapterFractions
            Canvas { context, size in
                let bar = CGRect(origin: .zero, size: size)
                context.clip(to: Path(roundedRect: bar, cornerRadius: size.height / 2))
                context.fill(Path(bar), with: .color(Color(white: 0.6).opacity(0.5)))
                let playedX = size.width * played
                let bufferedX = size.width * buffered
                if bufferedX > playedX {
                    context.fill(Path(CGRect(x: playedX, y: 0, width: bufferedX - playedX, height: size.height)),
                                 with: .color(Color(white: 0.69).opacity(0.41)))
                }
                context.fill(Path(CGRect(x: 0, y: 0, width: playedX, height: size.height)), with: .color(accent))
                context.blendMode = .clear
                for gap in gaps {
                    context.fill(Path(CGRect(x: size.width * gap - 1.5, y: 0, width: 3, height: size.height)),
                                 with: .color(.black))
                }
            }
            .frame(height: 4)
            .overlay(alignment: .leading) {
                // A ring: the accent around a darker core that widens under
                // the pointer.
                Circle()
                    .fill(accent)
                    .overlay {
                        Circle()
                            .fill(accent)
                            .overlay(Circle().fill(.black.opacity(0.3)))
                            .padding(active ? 2.2 : 3)
                    }
                    .frame(width: Self.handle, height: Self.handle)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: width * played - Self.handle / 2)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                if let x = scrub.map({ CGFloat(fraction($0)) * width }) ?? hoverX, duration > 0 {
                    scrubPreview(at: Double(x / width) * duration)
                        .frame(width: Self.previewWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: min(max(x - Self.previewWidth / 2, -8), max(width - Self.previewWidth + 8, -8)),
                                y: -(geometry.size.height + 5))
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
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 22)
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

    /// Where the chapters begin, without the one at 0.
    private var chapterFractions: [Double] {
        guard duration > 0 else { return [] }
        return chapters.filter { $0.start > 1 }.map { min(max($0.start / duration, 0), 1) }
    }

    /// The chapter, the picture in a dark frame and the time, stacked over
    /// the pointer.
    private func scrubPreview(at seconds: Double) -> some View {
        VStack(spacing: 5) {
            if let chapter = PlaybackChapter.current(chapters, at: seconds), !chapter.title.isEmpty {
                pill(chapter.title)
            }
            if let picture = thumbnails?.image(at: seconds) {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 224, height: 126)
                    .clipped()
                    .padding(4.5)
                    .background(Color(white: 0.067), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            }
            pill(AppFormat.position(seconds))
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.7), in: Capsule())
            .frame(maxWidth: Self.previewWidth)
    }
}

/// Play or pause: the largest symbol of the bar, in the middle.
struct PlayerPlayButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 28, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 40)
        }
        .buttonStyle(PlayerChromeButtonStyle())
        .help(isPaused ? "Abspielen (Leertaste)" : "Anhalten (Leertaste)")
    }
}

/// A white symbol on the bar.
struct PlayerIconButton: View {
    let symbol: String
    var help = ""
    var isDisabled = false
    /// The larger, filled symbols of the transport.
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlayerGlyph(symbol: symbol, prominent: prominent)
        }
        .buttonStyle(PlayerChromeButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The face of the menus of the bar.
struct PlayerIconLabel: View {
    let symbol: String?
    var text: String?

    var body: some View {
        PlayerChrome(isText: false) {
            PlayerGlyph(symbol: symbol, text: text)
        }
    }
}

/// A symbol, a short text or both.
private struct PlayerGlyph: View {
    let symbol: String?
    var text: String?
    var prominent = false

    var body: some View {
        HStack(spacing: Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 21 : 17, weight: prominent ? .medium : .regular))
            }
            if let text {
                Text(text)
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
            }
        }
        .padding(.horizontal, text == nil ? 0 : Space.s)
    }
}

/// The buttons of the bar: white, under the pointer in the accent, a little
/// larger, with a glow and a faint box behind; grey while pressed. Text
/// only changes its colour.
private struct PlayerChromeButtonStyle: ButtonStyle {
    var isText = false

    func makeBody(configuration: Configuration) -> some View {
        PlayerChrome(isPressed: configuration.isPressed, isText: isText) {
            configuration.label
        }
    }
}

private struct PlayerChrome<Content: View>: View {
    var isPressed = false
    var isText = false
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        content
            .foregroundStyle(isPressed ? Color(white: 0.6) : hovering ? Palette.accent : .white)
            .scaleEffect(hovering && !isPressed && !isText ? 1.15 : 1)
            .shadow(color: Palette.accent.opacity(hovering && !isText ? 0.55 : 0), radius: 5)
            .playerOutline()
            .frame(minWidth: isText ? 0 : 36, minHeight: 36)
            .background {
                if !isText {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Palette.accent.opacity(isPressed ? 0.18 : hovering ? 0.10 : 0))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private extension View {
    /// A thin dark edge, so white reads on a bright picture.
    func playerOutline() -> some View {
        shadow(color: .black.opacity(0.7), radius: 1)
    }
}

/// The speaker (mute) and a short slider for the volume.
struct PlayerVolumeControl: View {
    let engine: MPVPlayer
    var showsSlider = true

    var body: some View {
        HStack(spacing: Space.xxs) {
            PlayerIconButton(symbol: symbol, help: engine.isMuted ? "Ton an (M)" : "Stumm (M)") {
                engine.toggleMute()
            }
            if showsSlider {
                PlayerMiniSlider(value: engine.isMuted ? 0 : engine.volume / 100) { engine.setVolume($0 * 100) }
                    .frame(width: 64)
                    .help("Lautstärke")
            }
        }
    }

    private var symbol: String {
        if engine.isMuted || engine.volume == 0 { return "speaker.slash" }
        if engine.volume < 34 { return "speaker.wave.1" }
        if engine.volume < 67 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }
}

/// A thin white slider from 0 to 1.
struct PlayerMiniSlider: View {
    let value: Double
    let change: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.6).opacity(0.5))
                Capsule().fill(.white).frame(width: width * value)
            }
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Circle().fill(.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: width * value - 5.5)
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

/// The speed of the playback.
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
            PlayerIconLabel(symbol: nil, text: Self.label(engine.speed))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tempo")
    }

    private static func label(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed).replacingOccurrences(of: ".", with: ",")
    }
}

/// The chapters of the episode: a list with the times, the running one
/// marked. A click jumps there.
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

/// The subtitles: one click switches them on or off. The choice sticks for
/// the next file. An episode carries a single subtitle file, so there is no
/// list to pick from.
struct PlayerSubtitleButton: View {
    let engine: MPVPlayer
    let playback: PlaybackCenter

    var body: some View {
        PlayerIconButton(symbol: engine.showsSubtitles ? "captions.bubble.fill" : "captions.bubble",
                         help: engine.showsSubtitles ? "Untertitel ausblenden (C)" : "Untertitel einblenden (C)") {
            playback.setSubtitlesOn(!engine.showsSubtitles)
        }
    }
}

/// The audio track, when the file has more than one.
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

/// The red dot of a running stream.
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
        .background(.white.opacity(0.12), in: Capsule())
    }
}

/// Jumps a rewound or paused live stream back to its newest moment.
/// On the edge it is only the red mark.
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
                        .fill(atEdge ? Color.red : Color.white.opacity(0.9))
                        .frame(width: 7, height: 7)
                    Text(atEdge || behind < 1 ? "LIVE" : "−" + AppFormat.position(behind))
                        .font(AppFont.captionMedium)
                        .tracking(atEdge ? 1.2 : 0)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(atEdge ? Color.red.opacity(0.32) : Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(atEdge)
            .help(atEdge ? "Am Live-Rand" : "Zum Live-Rand springen")
        }
    }
}

/// Klein, Mittel, Groß or Kino. The check mark follows the last choice.
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

/// The next episode in the last half minute of the running one.
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
                    .foregroundStyle(.black)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.m)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.white.opacity(0.09)))
    }
}

/// A short sign in the middle of the picture after a key or a click.
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
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(.black.opacity(0.5), in: Circle())
            if let text = flash.text {
                Text(text)
                    .font(AppFont.subheading)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(.black.opacity(0.5), in: Capsule())
            }
        }
        .allowsHitTesting(false)
    }
}

/// The progress while the controls are hidden.
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
