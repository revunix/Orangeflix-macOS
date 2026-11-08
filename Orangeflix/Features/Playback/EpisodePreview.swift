import Foundation
import Observation
import SwiftUI

/// One short preview at a time, independent of the main playback and its
/// watch history. It lives only while its originating control is hovered.
/// Every episode picture in the app shares this one preview (the player
/// page itself has none).
@MainActor @Observable final class EpisodePreviewModel {
    enum Mode { case hover, selected }
    /// Scrolling often crosses several thumbnails quickly. Wait long enough
    /// to avoid requesting a stream unless the pointer settles on one.
    private static let hoverDelay: Duration = .milliseconds(1_200)

    private(set) var identifier: String?
    private(set) var mode: Mode?
    private(set) var positions: [Int] = []
    private(set) var segment = 0
    private(set) var position: Double = 0
    private(set) var isLoading = false
    private(set) var canRender = false
    private(set) var failureIdentifier: String?
    private(set) var failureMessage: String?
    private var deniedUntil: [String: Date] = [:]

    @ObservationIgnored private var player: MPVPlayer?
    @ObservationIgnored private weak var activePlayback: PlaybackCenter?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var startPosition = 0
    @ObservationIgnored private var waitingForSeek = false
    @ObservationIgnored private var needsDuration = false
    @ObservationIgnored private var fileLoaded = false
    @ObservationIgnored private var pendingProgressRestore: (identifier: String, wasWatched: Bool, duration: Int)?
    @ObservationIgnored private var progressRestoreTask: Task<Void, Never>?
    private(set) var origin: UUID?

    func isDenied(_ identifier: String) -> Bool {
        (deniedUntil[identifier] ?? .distantPast) > Date()
    }

    func resetAccess() {
        stop()
        deniedUntil = [:]
        failureIdentifier = nil
        failureMessage = nil
    }

    func hover(_ episode: Episode, origin: UUID, using playback: PlaybackCenter) {
        guard self.origin != origin else { return }
        start(episode, mode: .hover, seconds: 0, origin: origin, muted: false, using: playback)
    }

    func leave(_ origin: UUID) {
        if self.origin == origin { stop() }
    }

    func play(_ episode: Episode, from seconds: Int, origin: UUID, muted: Bool, using playback: PlaybackCenter) {
        start(episode, mode: .selected, seconds: max(seconds, 0), origin: origin, muted: muted, using: playback)
    }

    func selectSegment(_ index: Int) {
        guard mode == .hover, positions.indices.contains(index), !isLoading else { return }
        segment = index
        seek(to: positions[index])
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        let progressRestore = pendingProgressRestore
        pendingProgressRestore = nil
        generation += 1
        preparation?.cancel()
        preparation = nil
        player?.onPosition = nil
        player?.onEnd = nil
        player?.onFileLoaded = nil
        player?.stop()
        player = nil
        identifier = nil
        mode = nil
        positions = []
        segment = 0
        isLoading = false
        canRender = false
        waitingForSeek = false
        needsDuration = false
        fileLoaded = false
        origin = nil
        let playback = activePlayback
        activePlayback = nil
        if let progressRestore, let playback {
            progressRestoreTask = Task { [weak playback] in
                await playback?.restorePreviewProgress(progressRestore.identifier,
                                                       wasWatched: progressRestore.wasWatched,
                                                       duration: progressRestore.duration)
            }
        }
        return progressRestoreTask
    }

    private func start(_ episode: Episode, mode: Mode, seconds: Int, origin: UUID, muted: Bool, using playback: PlaybackCenter) {
        let previousRestore = stop()
        failureIdentifier = nil
        failureMessage = nil
        let token = generation
        identifier = episode.identifier
        self.mode = mode
        self.origin = origin
        isLoading = true
        var random = SystemRandomNumberGenerator()
        positions = mode == .hover ? PlaybackLogic.previewPositions(duration: episode.durationSeconds, using: &random) : []
        needsDuration = mode == .hover && positions.isEmpty
        startPosition = positions.first ?? seconds
        position = Double(startPosition)

        let engine = playback.previewEngine
        activePlayback = playback
        player = engine
        // Never talk over a running main playback.
        engine.setMuted(muted || (playback.isPlaying && !playback.isPaused))
        engine.setSubtitlesOn(false)
        preparation = Task { [weak self] in
            do {
                await previousRestore?.value
                try Task.checkCancellation()
                if mode == .hover { try await Task.sleep(for: Self.hoverDelay) }
                try Task.checkCancellation()
                let (url, headers, wasWatched, duration) = try await playback.previewFile(for: episode)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.pendingProgressRestore = (episode.identifier, wasWatched, duration)
                self.deniedUntil.removeValue(forKey: episode.identifier)
                engine.onPosition = { [weak self] value in self?.positionChanged(value) }
                engine.onFileLoaded = { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.fileLoaded = true
                }
                engine.onEnd = { [weak self, weak playback] reason in
                    guard let self, self.generation == token else { return }
                    if case .failed = reason {
                        self.failureIdentifier = episode.identifier
                        self.failureMessage = "Die Vorschau konnte nicht abgespielt werden."
                        if self.mode == .selected { playback?.app.show(self.failureMessage ?? "", error: true) }
                    }
                    if reason != .stopped { self.stop() }
                }
                self.waitingForSeek = true
                self.canRender = true
                engine.load(url, start: self.startPosition, headers: headers,
                            userAgent: APIDefaults.userAgent, subtitles: [])
            } catch is CancellationError {
                return
            } catch PlaybackCenter.PreviewError.noAccess {
                guard let self, self.generation == token else { return }
                self.deniedUntil[episode.identifier] = Date().addingTimeInterval(60)
                self.stop()
            } catch {
                guard let self, self.generation == token else { return }
                self.failureIdentifier = episode.identifier
                self.failureMessage = error.localizedDescription
                if mode == .selected { playback.app.show(error) }
                self.stop()
            }
        }
    }

    private func seek(to seconds: Int) {
        startPosition = seconds
        position = Double(seconds)
        waitingForSeek = true
        player?.seek(to: Double(seconds))
    }

    private func positionChanged(_ value: Double) {
        guard let player, identifier != nil, fileLoaded else { return }
        if needsDuration, player.duration > 0, player.duration.isFinite,
           player.duration < Double(Int.max) {
            var random = SystemRandomNumberGenerator()
            positions = PlaybackLogic.previewPositions(duration: Int(player.duration), using: &random)
            needsDuration = false
            if let first = positions.first {
                seek(to: first)
                return
            }
        }
        // Ignore position notifications from the old place while seeking.
        if waitingForSeek {
            guard value >= Double(startPosition) - 0.5, value <= Double(startPosition) + 2 else { return }
            waitingForSeek = false
        }
        isLoading = false
        position = value
        let length = mode == .hover ? 5.0 : 20.0
        let end = player.duration > 0 ? min(Double(startPosition) + length, max(player.duration - 0.1, 0))
                                      : Double(startPosition) + length
        guard value >= end else { return }
        if mode == .hover, segment + 1 < positions.count {
            segment += 1
            seek(to: positions[segment])
        } else {
            stop()
        }
    }
}

/// The picture of an episode, or the running preview when it belongs to it.
struct EpisodePreviewSurface: View {
    let episode: Episode
    let preview: EpisodePreviewModel
    let playback: PlaybackCenter

    var body: some View {
        if preview.identifier == episode.identifier && preview.canRender {
            MPVVideoView(player: playback.previewEngine)
                .background(.black)
        } else {
            RemoteArt(url: episode.thumb)
        }
    }
}

/// The five places of a hover preview; a click jumps to one of them.
struct EpisodePreviewSegments: View {
    let preview: EpisodePreviewModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(preview.positions.enumerated()), id: \.offset) { index, seconds in
                Button { preview.selectSegment(index) } label: {
                    Capsule()
                        .fill(index == preview.segment ? Color.white : Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(preview.isLoading)
                .accessibilityLabel("Vorschau \(index + 1) ab \(AppFormat.position(Double(seconds)))")
            }
        }
        .padding(.horizontal, Space.xs)
        .background(.black.opacity(0.4))
    }
}

/// The current position of a running preview.
struct EpisodePreviewClock: View {
    let position: Double

    var body: some View {
        Text(AppFormat.position(position))
            .font(AppFont.digitsMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 2)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(Space.xs)
    }
}
