import AppKit
import Darwin
import Foundation
import ObjectiveC

@objc private protocol PIPMutablePlaybackStateBridge: NSObjectProtocol {
    var contentDuration: TimeInterval { get set }
    var contentType: Int { get set }
    @objc(setPlaybackRate:elapsedTime:timeControlStatus:)
    func setPlaybackRate(_ rate: Double, elapsedTime: TimeInterval, timeControlStatus: Int)
}

@objc private protocol PIPViewControllerBridge: NSObjectProtocol {
    var delegate: AnyObject? { get set }
    var playing: Bool { get set }
    var aspectRatio: NSSize { get set }
    var userCanResize: Bool { get set }
    var replacementWindow: NSWindow? { get set }
    var replacementRect: NSRect { get set }
    var panel: NSPanel? { get }
    @objc(presentViewControllerAsPictureInPicture:)
    func presentAsPictureInPicture(_ viewController: NSViewController)
    @objc(updatePlaybackStateUsingBlock:)
    optional func updatePlaybackState(_ block: @convention(block) (AnyObject) -> Void)
}

/// Drives macOS's native system Picture-in-Picture panel (`PIP.framework`)
/// using an `MPVVideoSlot`, so the shared OpenGL layer moves into and out of
/// the floating PiP window without rebuilding `libmpv`'s video output.
@MainActor final class NativePiPController: NSObject {
    private(set) var isActive = false

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    /// Invoked when the user closes PiP via its `×` button.
    var onCloseStop: (() -> Void)?
    /// Invoked when the user clicks the "Return to window" button inside PiP.
    var onReturnToSource: (() -> Void)?
    /// Always invoked once PiP has torn down its view controller.
    var onDidExit: (() -> Void)?

    private var pipViewController: NSViewController?
    private var contentViewController: NSViewController?
    private var closingProgrammatically = false
    private var stoppedByCloseButton = false
    private var didTriggerReturn = false

    private static let pipClass: NSViewController.Type? = {
        _ = dlopen("/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP", RTLD_LAZY)
        return NSClassFromString("PIPViewController") as? NSViewController.Type
    }()

    var isSupported: Bool { Self.pipClass != nil }

    func enter(
        player: MPVPlayer,
        videoSize: CGSize?,
        isPlaying: Bool,
        position: Double,
        duration: Double,
        speed: Double,
        isLive: Bool
    ) -> Bool {
        guard !isActive, let cls = Self.pipClass else { return isActive }

        closingProgrammatically = false
        stoppedByCloseButton = false
        didTriggerReturn = false

        let pipVC = cls.init()
        let bridge = unsafeBitCast(pipVC, to: PIPViewControllerBridge.self)
        bridge.delegate = self
        bridge.userCanResize = true
        bridge.playing = isPlaying
        bridge.aspectRatio = Self.sanitizedRatio(videoSize)

        if let hostWindow = Self.anchorWindow() {
            bridge.replacementWindow = hostWindow
            bridge.replacementRect = Self.anchorRect(in: hostWindow)
        }

        let slot = MPVVideoSlot(player: player)
        slot.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        slot.autoresizingMask = [.width, .height]

        let contentVC = NSViewController()
        contentVC.view = slot
        // Never set `preferredContentSize` here: `PIPViewController` translates
        // a fixed `preferredContentSize` into fixed width/height constraints on
        // `slot`, which clips the video to 640×360 when the user enlarges PiP.

        pipViewController = pipVC
        contentViewController = contentVC
        isActive = true

        bridge.presentAsPictureInPicture(contentVC)
        syncState(isPlaying: isPlaying, position: position, duration: duration, speed: speed, isLive: isLive)
        return bridge.panel != nil
    }

    func exit() {
        guard isActive else { return }
        closingProgrammatically = true
        if let pipVC = pipViewController {
            let bridge = unsafeBitCast(pipVC, to: PIPViewControllerBridge.self)
            if let hostWindow = Self.anchorWindow() {
                bridge.replacementWindow = hostWindow
                bridge.replacementRect = Self.anchorRect(in: hostWindow)
            }
            if let contentVC = contentViewController, contentVC.presentingViewController != nil {
                pipVC.dismiss(contentVC)
            } else {
                finishClose()
                return
            }
        }
        // Fallback cleanup if the animation delegate does not report back.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, self.isActive, self.closingProgrammatically else { return }
            self.finishClose()
        }
    }

    func updateAspectRatio(_ size: CGSize?) {
        guard isActive, let pipVC = pipViewController else { return }
        let bridge = unsafeBitCast(pipVC, to: PIPViewControllerBridge.self)
        bridge.aspectRatio = Self.sanitizedRatio(size)
    }

    func syncState(isPlaying: Bool, position: Double, duration: Double, speed: Double, isLive: Bool) {
        guard isActive, let pipVC = pipViewController else { return }
        let bridge = unsafeBitCast(pipVC, to: PIPViewControllerBridge.self)
        bridge.playing = isPlaying
        guard pipVC.responds(to: NSSelectorFromString("updatePlaybackStateUsingBlock:")) else { return }
        bridge.updatePlaybackState? { rawState in
            let state = unsafeBitCast(rawState, to: PIPMutablePlaybackStateBridge.self)
            // 1 = VOD with scrubber/skip, 2 = live broadcast
            state.contentType = isLive ? 2 : 1
            if !isLive, duration > 0 {
                state.contentDuration = duration
            }
            state.setPlaybackRate(
                isPlaying ? max(speed, 0.25) : 0,
                elapsedTime: max(position, 0),
                timeControlStatus: isPlaying ? 2 : 0
            )
        }
    }

    // MARK: PIPViewControllerDelegate

    @objc(pipActionPlay:)
    func pipActionPlay(_ pip: AnyObject) {
        onPlay?()
    }

    @objc(pipActionPause:)
    func pipActionPause(_ pip: AnyObject) {
        onPause?()
    }

    @objc(pipActionStop:)
    func pipActionStop(_ pip: AnyObject) {
        stoppedByCloseButton = true
    }

    @objc(pipAction:skipInterval:)
    func pipAction(_ pip: AnyObject, skipInterval interval: TimeInterval) {
        onSkip?(interval)
    }

    @objc(pipShouldClose:)
    func pipShouldClose(_ pip: AnyObject) -> Bool {
        prepareInteractiveReturnIfNeeded()
        if let pipVC = pipViewController, let hostWindow = Self.anchorWindow() {
            let bridge = unsafeBitCast(pipVC, to: PIPViewControllerBridge.self)
            bridge.replacementWindow = hostWindow
            bridge.replacementRect = Self.anchorRect(in: hostWindow)
        }
        return true
    }

    @objc(pipWillClose:)
    func pipWillClose(_ pip: AnyObject) {
        prepareInteractiveReturnIfNeeded()
    }

    @objc(pipDidClose:)
    func pipDidClose(_ pip: AnyObject) {
        finishClose()
    }

    // MARK: Helpers

    private func prepareInteractiveReturnIfNeeded() {
        guard !closingProgrammatically, !stoppedByCloseButton, !didTriggerReturn else { return }
        didTriggerReturn = true
        if let window = Self.anchorWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        onReturnToSource?()
    }

    private func finishClose() {
        guard isActive || pipViewController != nil || contentViewController != nil else { return }
        let wasStoppedByCloseButton = stoppedByCloseButton
        contentViewController?.view.removeFromSuperview()
        contentViewController = nil
        pipViewController = nil
        isActive = false
        closingProgrammatically = false
        stoppedByCloseButton = false
        didTriggerReturn = false

        if wasStoppedByCloseButton {
            onCloseStop?()
        }
        onDidExit?()
    }

    private static func sanitizedRatio(_ size: CGSize?) -> NSSize {
        if let size, size.width > 1, size.height > 1 {
            return NSSize(width: size.width, height: size.height)
        }
        return NSSize(width: 16, height: 9)
    }

    private static func anchorWindow() -> NSWindow? {
        if let playerWindow = PlayerWindows.current, playerWindow.isVisible {
            return playerWindow
        }
        return NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private static func anchorRect(in window: NSWindow) -> NSRect {
        let bounds = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 960, height: 540)
        let width = min(bounds.width * 0.75, 760)
        let height = width * 9 / 16
        return NSRect(
            x: bounds.midX - width / 2,
            y: max(bounds.maxY - height - 72, bounds.midY - height / 2),
            width: width,
            height: height
        )
    }
}
