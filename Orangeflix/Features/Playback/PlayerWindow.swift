import AppKit
import SwiftUI

extension Notification.Name {
    /// A playback started; the window of the player comes to the front.
    static let orangeflixPlaybackStarted = Notification.Name("com.revunix.orangeflix.playbackStarted")
    /// The playback ended.
    static let orangeflixPlaybackStopped = Notification.Name("com.revunix.orangeflix.playbackStopped")
    /// The settings window should show the page "Über" (menu command).
    static let openAboutPane = Notification.Name("com.revunix.orangeflix.openAboutPane")
}

/// The window of the player; the app shows one at a time.
@MainActor
enum PlayerWindows {
    /// The window of the player; nil while there is none. The view inside
    /// the window sets it on every update, because SwiftUI reuses the window
    /// after it was closed and a reference taken once goes stale.
    static weak var current: NSWindow?

    /// Brings the window of the player to the front; false when there is
    /// none yet.
    @discardableResult
    static func front() -> Bool {
        guard let window = current else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Puts the window of the player into the full screen, or takes it out
    /// of it.
    static func toggleFullScreen() {
        current?.toggleFullScreen(nil)
    }

    /// Whether the window of the player fills the screen.
    static var isFullScreen: Bool {
        current?.styleMask.contains(.fullScreen) ?? false
    }

    /// A content width the window can take. The height follows the picture.
    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large, cinema

        var id: String { rawValue }

        /// The width of the picture, in points.
        var contentWidth: CGFloat {
            switch self {
            case .small: 720
            case .medium: 1_120
            case .large: 1_440
            case .cinema: 1_920
            }
        }

        var title: String {
            switch self {
            case .small: "Klein"
            case .medium: "Mittel"
            case .large: "Groß"
            case .cinema: "Kino"
            }
        }
    }

    /// The size chosen last. A new window opens in it.
    static var preferredSize: Size = .medium
    /// A size that waits until the window has left the full screen.
    static var pendingSize: Size?

    /// Gives the window the chosen picture width. In full screen the change
    /// waits until the window has left it.
    static func resize(to size: Size) {
        preferredSize = size
        guard let window = current else { return }
        if window.styleMask.contains(.fullScreen) {
            pendingSize = size
            window.toggleFullScreen(nil)
            return
        }
        apply(size, to: window, animate: true)
    }

    /// Applies a size that was asked for while the window filled the screen.
    static func applyPendingSize(to window: NSWindow) {
        guard let size = pendingSize else { return }
        pendingSize = nil
        apply(size, to: window, animate: true)
    }

    /// Opens the window in the size chosen last.
    static func applyPreferred(to window: NSWindow) {
        apply(preferredSize, to: window, animate: false)
    }

    /// Sets the content size and keeps the top edge where it is. The picture
    /// keeps its aspect ratio; a size that does not fit the screen shrinks.
    private static func apply(_ size: Size, to window: NSWindow, animate: Bool) {
        if window.contentAspectRatio.width <= 1 || window.contentAspectRatio.height <= 1 {
            window.contentAspectRatio = CGSize(width: 16, height: 9)
        }
        let aspect = window.contentAspectRatio
        let ratio = aspect.height / aspect.width
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        var width = size.contentWidth
        var height = (width * ratio).rounded()
        let maxWidth = max(480, screen.width - 48)
        let maxHeight = max(270, screen.height - 48)
        if width > maxWidth {
            width = maxWidth
            height = (width * ratio).rounded()
        }
        if height > maxHeight {
            height = maxHeight
            width = (height / ratio).rounded()
        }
        let frameSize = window.frameRect(forContentRect: CGRect(x: 0, y: 0, width: width, height: height)).size
        var frame = CGRect(origin: window.frame.origin, size: frameSize)
        frame.origin.y -= frameSize.height - window.frame.height
        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        window.setFrame(frame, display: true, animate: animate)
    }

    /// Closes the window of the player after the last episode; like mpv in
    /// the Go app, the window goes away when nothing is left to play.
    static func close() {
        current?.close()
    }
}

/// A view that hands the window it lives in to the app.
final class PlayerWindowView: NSView {
    /// Called when the view got a window.
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onWindow?(window)
    }
}

/// Connects the window of the player with the playback: the title shows the
/// name of the episode, the window takes the shape of the picture, the
/// window buttons fade with the controls, and closing the window ends the
/// playback (Go `StopPlayback`; the app itself shuts the playback down when
/// it quits).
struct PlayerWindowBridge: NSViewRepresentable {
    /// The playback the window belongs to.
    var playback: PlaybackCenter?
    /// Whether the controls are shown; the window buttons follow them.
    var chromeVisible = true
    /// The size of the picture; the window keeps its aspect ratio.
    var videoSize: CGSize?

    func makeNSView(context: Context) -> NSView {
        let view = PlayerWindowView()
        view.onWindow = { window in
            context.coordinator.attach(window, playback: playback)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { PlayerWindows.current = window }
        context.coordinator.playback = playback
        context.coordinator.updateTitle()
        context.coordinator.showButtons(chromeVisible)
        context.coordinator.fit(videoSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps the window and the playback together.
    @MainActor
    final class Coordinator {
        /// The playback of the window.
        var playback: PlaybackCenter?
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var buttonsVisible = true
        private var fittedSize: CGSize?

        func attach(_ window: NSWindow, playback: PlaybackCenter?) {
            self.window = window
            self.playback = playback
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .black
            window.collectionBehavior.insert(.fullScreenPrimary)
            PlayerWindows.current = window
            observers.forEach(NotificationCenter.default.removeObserver)
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    // Closing the window ends the playback; the app may
                    // start a new one later. A playback that moved into the
                    // Live screen keeps running.
                    MainActor.assumeIsolated {
                        if PlayerWindows.current === window { PlayerWindows.current = nil }
                        guard self?.playback?.isInline != true else { return }
                        self?.playback?.stop()
                    }
                },
                // The full screen shows the window buttons in the bar that
                // slides in at the top; they must not stay faded there.
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setButtonAlpha(1) }
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        PlayerWindows.applyPendingSize(to: window)
                    }
                },
            ]
            updateTitle()
            // A window without a playback (restored after a restart), or one
            // whose playback runs in the Live screen, has nothing to show.
            if playback?.isPlaying != true || playback?.isInline == true {
                DispatchQueue.main.async { window.close() }
            } else {
                PlayerWindows.applyPreferred(to: window)
            }
        }

        /// The title of the window shows the name of the running episode.
        func updateTitle() {
            guard let window else { return }
            let title = playback?.nowPlayingTitle ?? ""
            if !title.isEmpty, window.title != title {
                window.title = title
            }
        }

        /// Fades the close, minimize and zoom buttons with the controls. In
        /// the full screen they stay: the system bar at the top hides them.
        func showButtons(_ visible: Bool) {
            guard let window, visible != buttonsVisible, !window.styleMask.contains(.fullScreen) else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                setButtonAlpha(visible ? 1 : 0, animated: true)
            }
        }

        private func setButtonAlpha(_ alpha: CGFloat, animated: Bool = false) {
            guard let window else { return }
            buttonsVisible = alpha > 0
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                if animated { button.animator().alphaValue = alpha } else { button.alphaValue = alpha }
            }
        }

        /// Gives the window the aspect ratio of the picture, so that no black
        /// bars remain. The width stays; the top edge stays in place.
        func fit(_ size: CGSize?) {
            guard let window, let size, size.width > 0, size.height > 0, size != fittedSize else { return }
            fittedSize = size
            window.contentAspectRatio = size
            guard !window.styleMask.contains(.fullScreen) else { return }
            var frame = window.frame
            let content = window.contentRect(forFrameRect: frame)
            let height = (content.width * size.height / size.width).rounded()
            let delta = height - content.height
            frame.size.height += delta
            frame.origin.y -= delta
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

extension View {
    /// Opens the window of the player when a playback starts and brings it
    /// to the front (the Go app lets the player open its own window).
    func opensPlayerWindow() -> some View {
        modifier(OpenPlayerWindowModifier())
    }
}

/// Watches the playback and opens the window of the player; a playback
/// inside the Live screen needs none.
private struct OpenPlayerWindowModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(PlaybackCenter.self) private var playback

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .orangeflixPlaybackStarted)) { _ in
                if !playback.isInline { showPlayer() }
            }
            .onAppear {
                if playback.isPlaying, !playback.isInline { showPlayer() }
            }
    }

    private func showPlayer() {
        if PlayerWindows.front() { return }
        openWindow(id: "player")
    }
}
