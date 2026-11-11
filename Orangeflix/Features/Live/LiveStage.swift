import AppKit
import SwiftUI

// MARK: - Stage

/// The picture of the Live screen. While the stream plays here it is the
/// video of mpv with its controls; otherwise the blurred banner of the show
/// with what can be started. The screen frames and clips it.
struct LiveStage: View {
    let model: LiveModel
    let playback: PlaybackCenter
    let banner: String

    @Environment(AppModel.self) private var app
    @Environment(NewEpisodeWatcher.self) private var watcher

    private var isLiveOrReplay: Bool {
        playback.current?.kind == .live || playback.current?.kind == .replay
    }

    private var playsHere: Bool {
        playback.isPlaying && playback.isInline && isLiveOrReplay && !playback.isInPiP
    }

    private var starting: Bool {
        playback.isInline && !playback.isPlaying && playback.preparingIdentifier == "live"
    }

    /// The stream or the replay runs in the player window.
    private var playsInWindow: Bool {
        playback.isPlaying && !playback.isInline && isLiveOrReplay
    }

    var body: some View {
        ZStack {
            Color.black
            if playsHere {
                MPVVideoView(player: playback.engine)
                LiveStageControls(playback: playback)
            } else {
                poster
            }
        }
    }

    private var poster: some View {
        ZStack {
            if !banner.isEmpty {
                // Blurred, so the lettering of the banner never fights the
                // countdown or the buttons in front of it.
                Color.clear
                    .overlay { RemoteArt(url: banner, symbol: "dot.radiowaves.left.and.right") }
                    .blur(radius: 28)
                    .clipped()
                    .opacity(0.7)
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            posterContent
                .padding(Space.xl)
        }
    }

    @ViewBuilder
    private var posterContent: some View {
        if starting {
            ProgressView()
                .controlSize(.large)
        } else if playback.isInPiP && isLiveOrReplay {
            stagePrompt(symbol: "pip", title: "Läuft im Bild-in-Bild",
                        button: "Hier weitersehen", buttonSymbol: "pip.exit") { playback.exitPiP() }
        } else if playsInWindow {
            stagePrompt(symbol: "macwindow", title: "Läuft im Player-Fenster",
                        button: "Hier ansehen", buttonSymbol: "rectangle.inset.filled") { playback.pullIn() }
        } else if let info = model.info {
            if info.isLive {
                if info.hasAccess {
                    LiveBigPlayButton(title: "Live ansehen") { model.watchLive() }
                } else {
                    stagePrompt(symbol: "lock.fill", title: "Diese Sendung ist nicht in deinem Abo enthalten.")
                }
            } else if let next = info.scheduled, next.begin > 0 {
                premiereCountdownCard(next: next, replay: info.replay)
            } else if let replay = info.replay, replay.possible, replay.canAccess {
                LiveBigPlayButton(title: "Replay ansehen") { model.watchReplay() }
            } else {
                stagePrompt(symbol: "tv", title: "Gerade läuft keine Sendung.")
            }
        } else if model.isLoading {
            ProgressView()
                .controlSize(.large)
        } else {
            stagePrompt(symbol: "wifi.exclamationmark", title: "Der Live-Stand konnte nicht geladen werden.",
                        button: "Erneut versuchen", buttonSymbol: "arrow.clockwise") {
                Task { await model.load(force: true) }
            }
        }
    }

    private func premiereCountdownCard(next: LivestreamScheduled, replay: LivestreamReplay?) -> some View {
        let startDate = Date(timeIntervalSince1970: TimeInterval(next.begin))
        let isToday = Calendar.current.isDateInToday(startDate)
        let startLabel = isToday
            ? "Heute um \(AppFormat.time(startDate)) Uhr"
            : "\(AppFormat.dayMonth(startDate)) · \(AppFormat.time(startDate)) Uhr"
        let notifyOn = app.settings.liveNotificationsOn
        let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(spacing: Space.m) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                Text("PREMIEREN-COUNTDOWN")
                    .font(AppFont.micro)
                    .tracking(1.2)
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())

            Text(startLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let parts = LiveCountdown.components(until: startDate, now: context.date)
                HStack(spacing: 10) {
                    if parts.days > 0 {
                        countdownDigitTile(value: parts.days, label: parts.days == 1 ? "Tag" : "Tage")
                    }
                    countdownDigitTile(value: parts.hours, label: "Std")
                    countdownDigitTile(value: parts.minutes, label: "Min")
                    countdownDigitTile(value: parts.seconds, label: "Sek")
                }
            }

            HStack(spacing: Space.s) {
                Button {
                    let nextState = !notifyOn
                    try? app.updateSettings { $0.liveNotificationsOn = nextState }
                    if nextState {
                        Task {
                            await watcher.refreshPermission()
                            await watcher.checkLive()
                        }
                    }
                } label: {
                    Label(
                        notifyOn ? "Erinnerung aktiv" : "Beim Start melden",
                        systemImage: notifyOn ? "bell.badge.fill" : "bell"
                    )
                    .font(AppFont.captionMedium)
                    .foregroundStyle(notifyOn ? Palette.accent : .white)
                    .padding(.horizontal, Space.m)
                    .frame(height: 32)
                    .background(.white.opacity(notifyOn ? 0.14 : 0.08), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(notifyOn ? Palette.accent.opacity(0.55) : .white.opacity(0.16), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                if let replay, replay.possible, replay.canAccess {
                    PillButton(title: "Letztes Replay", symbol: "play.fill", style: .accent) {
                        model.watchReplay()
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background {
            cardShape
                .fill(.black.opacity(0.52))
                .background(.ultraThinMaterial, in: cardShape)
        }
        .overlay {
            cardShape.strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 24, y: 10)
    }

    private func countdownDigitTile(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(width: 68)
        .padding(.vertical, 9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func stagePrompt(symbol: String, title: String, button: String? = nil, buttonSymbol: String = "",
                             action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(AppFont.heading)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let button {
                PillButton(title: button, symbol: buttonSymbol.isEmpty ? nil : buttonSymbol,
                           style: .onPicture, action: action)
            }
        }
    }
}

/// The round orange button in the middle of the stage.
struct LiveBigPlayButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.m) {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 2)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Palette.accent))
                    .shadow(color: Palette.accent.opacity(hovering ? 0.6 : 0.3), radius: hovering ? 22 : 12)
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(title)
                    .font(AppFont.heading)
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
    }
}

/// The controls over the picture on the stage. They show while the pointer
/// is over it or the playback holds; a click holds or resumes.
struct LiveStageControls: View {
    let playback: PlaybackCenter

    @State private var hovering = false
    @State private var scrub: Double?
    @State private var showsRemaining = true
    @State private var width: CGFloat = 800

    private var engine: MPVPlayer { playback.engine }
    private var isLive: Bool { playback.current?.kind == .live }
    private var visible: Bool { hovering || engine.isPaused || scrub != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { playback.togglePlayPause() }
            if engine.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            if visible {
                bar
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: visible)
    }

    private var bar: some View {
        let deckShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 8) {
            if isLive {
                if playback.duration > 1 {
                    HStack(spacing: 10) {
                        PlayerTimeline(position: playback.position, duration: playback.duration,
                                       bufferedAhead: engine.bufferedAhead, scrub: $scrub) { seconds, exact in
                            playback.seek(to: seconds, exact: exact)
                        }
                        PlayerGoLiveButton(playback: playback)
                    }
                }
            } else {
                let shown = scrub ?? playback.position
                HStack(spacing: 10) {
                    Text(AppFormat.position(shown))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(minWidth: 42, alignment: .leading)
                    PlayerTimeline(position: playback.position, duration: playback.duration,
                                   bufferedAhead: engine.bufferedAhead, scrub: $scrub) { seconds, exact in
                        playback.seek(to: seconds, exact: exact)
                    }
                    Button {
                        showsRemaining.toggle()
                    } label: {
                        Text(showsRemaining
                             ? "−" + AppFormat.position(max(playback.duration - shown, 0))
                             : AppFormat.position(playback.duration))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.84))
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 3-Zone Control Row synchronized with PlayerScene
            ZStack {
                HStack(spacing: 6) {
                    PlayerVolumeControl(engine: engine, showsSlider: width >= 520)
                    if isLive && playback.duration <= 1 {
                        PlayerGoLiveButton(playback: playback)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        if isLive {
                            PlayerIconButton(symbol: "gobackward.30", help: "30 Sekunden zurückspulen") {
                                playback.skip(by: -30)
                            }
                        }
                        PlayerIconButton(symbol: "gobackward.10", help: "10 Sekunden zurück", prominent: true) {
                            playback.skip(by: -10)
                        }
                    }
                    .frame(width: 72, alignment: .trailing)

                    PlayerPlayButton(isPaused: engine.isPaused) {
                        playback.togglePlayPause()
                    }

                    HStack(spacing: 4) {
                        if !isLive {
                            PlayerIconButton(symbol: "goforward.10", help: "10 Sekunden vor", prominent: true) {
                                playback.skip(by: 10)
                            }
                        }
                    }
                    .frame(width: 72, alignment: .leading)
                }

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if engine.audioTracks.count > 1 {
                        PlayerAudioMenu(engine: engine)
                    }
                    if !engine.subtitleTracks.isEmpty {
                        PlayerSubtitleButton(engine: engine, playback: playback)
                    }
                    if playback.canUsePiP {
                        PlayerIconButton(
                            symbol: playback.isInPiP ? "pip.exit" : "pip.enter",
                            help: playback.isInPiP ? "Bild-in-Bild beenden" : "Bild-in-Bild",
                            isActive: playback.isInPiP
                        ) {
                            playback.togglePiP()
                        }
                    }
                    PlayerIconButton(symbol: "macwindow.on.rectangle", help: "Im Player-Fenster öffnen") {
                        playback.popOut()
                    }
                    PlayerIconButton(symbol: "stop.fill", help: "Wiedergabe beenden") {
                        playback.stop()
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 940)
        .background {
            deckShape
                .fill(.black.opacity(0.46))
                .background(.ultraThinMaterial, in: deckShape)
        }
        .overlay {
            deckShape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 6)
        .padding(Space.m)
    }
}

// MARK: - Pieces

/// How far the running show is: a bar from its start to its end, the
/// times at both ends and what is left.
struct LiveShowProgress: View {
    let begin: Int64
    let end: Int64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date.timeIntervalSince1970
            let fraction = min(max((now - Double(begin)) / Double(end - begin), 0), 1)
            let endDate = Date(timeIntervalSince1970: TimeInterval(end))
            HStack(spacing: Space.s) {
                Text(AppFormat.time(Date(timeIntervalSince1970: TimeInterval(begin))))
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.border)
                    Capsule()
                        .fill(Palette.accent)
                        .scaleEffect(x: max(0.01, fraction), anchor: .leading)
                }
                .frame(width: 120, height: 4)
                Text(AppFormat.time(endDate))
                if endDate > context.date {
                    Text("· noch " + LiveCountdown.text(until: endDate, now: context.date)
                        .replacingOccurrences(of: "in ", with: ""))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .font(AppFont.digitsMedium)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }
}

/// A card below the stage: a small title with a symbol, then its content.
struct LiveCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionLabel(text: title, symbol: symbol)
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }
}

/// One row of the programme below the show: the banner of the format, a
/// small kicker, the title with its format and time, and an accessory at
/// the end (the play button, the countdown). With an action the whole row
/// is a button that brightens under the pointer.
struct LiveProgramTile<Detail: View, Accessory: View>: View {
    let art: String
    let kicker: String
    let kickerColor: Color
    let title: String
    let format: String
    let action: (() -> Void)?
    @ViewBuilder var detail: Detail
    @ViewBuilder var accessory: Accessory

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            row
        }
    }

    private var row: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return HStack(spacing: Space.m) {
            Color.clear
                .frame(width: 128, height: 72)
                .overlay { RemoteArt(url: art, symbol: "dot.radiowaves.left.and.right") }
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(AppFont.captionMedium)
                    .tracking(0.8)
                    .foregroundStyle(kickerColor)
                Text(title)
                    .font(AppFont.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if !format.isEmpty, format != title {
                    Text(format)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .padding(.trailing, Space.s)
        }
        .padding(Space.s)
        .contentCard()
        .overlay {
            if hovering {
                shape.fill(Palette.textPrimary.opacity(0.04)).allowsHitTesting(false)
            }
        }
        .contentShape(shape)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// One answer of the voting: a row that fills with the share of the votes
/// once the results show.
struct LivePollAnswer: View {
    let answer: String
    let index: Int
    let poll: LivePoll
    let vote: () -> Void

    @State private var hovering = false

    private var chosen: Bool { poll.choice == index }
    /// A vote is final and an ended voting takes none.
    private var locked: Bool { poll.closed || poll.hasVoted }
    private var share: Double { Double(max(0, min(100, poll.percent(of: index)))) / 100 }

    var body: some View {
        Button(action: vote) {
            HStack(spacing: Space.s) {
                Image(systemName: chosen ? "checkmark.circle.fill" : locked ? "circle.dashed" : "circle")
                    .foregroundStyle(chosen ? Palette.accent : Palette.textTertiary)
                Text(answer)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Space.s)
                if poll.showsResults {
                    Text(AppFormat.percent(poll.percent(of: index)))
                        .font(AppFont.digitsMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .fill(Palette.accent.opacity(chosen ? 0.22 : 0.12))
                        .frame(width: poll.showsResults ? geometry.size.width * share : 0)
                }
            }
            .background(hovering && !locked ? Palette.surfaceMuted : Palette.background,
                        in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(chosen ? Palette.accent.opacity(0.6) : Palette.divider, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `disabled`: that would grey out the chosen answer too.
        .allowsHitTesting(!locked)
        .opacity(locked && !chosen && !poll.showsResults ? 0.6 : 1)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.3), value: share)
    }
}
