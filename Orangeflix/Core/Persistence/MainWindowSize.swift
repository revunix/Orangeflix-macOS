import AppKit
import SwiftUI

/// Remembers the size of the main window, so the app opens the way it was
/// left. Only the size is kept; the place belongs to the window server.
enum MainWindowSize {
    /// The id of the main window scene; its windows carry it in their
    /// identifier.
    static let sceneID = "main"
    private static let widthKey = "mainWindowWidth"
    private static let heightKey = "mainWindowHeight"

    /// The size of the first start; the scene names the same numbers.
    static let fallback = NSSize(width: 1_240, height: 1_000)

    /// The smallest window frame. The Live page sizes itself from its picture
    /// (`LiveWindowSizing`).
    static let minimumSize = NSSize(width: 1_000, height: 1_000)

    /// The smallest frame, never larger than the screen offers.
    static func minimum(on screen: NSScreen?) -> NSSize {
        let size = minimumSize
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame.size else { return size }
        return NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
    }

    /// The size of the last session, when one was stored and still fits the
    /// screen.
    static func load(for screen: NSScreen? = nil) -> NSSize? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: widthKey) != nil else { return nil }
        var size = NSSize(width: defaults.double(forKey: widthKey),
                          height: defaults.double(forKey: heightKey))
        guard size.width >= 320, size.height >= 240 else { return nil }
        if let visible = (screen ?? NSScreen.main)?.visibleFrame.size {
            size.width = min(size.width, visible.width - 16)
            size.height = min(size.height, visible.height - 16)
        }
        return size
    }

    static func save(_ size: NSSize) {
        guard size.width >= 320, size.height >= 240 else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(size.width), forKey: widthKey)
        defaults.set(Double(size.height), forKey: heightKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: widthKey)
        defaults.removeObject(forKey: heightKey)
    }
}

/// Lives in MainWindowView, not in the bridge that SwiftUI rebuilds when
/// switching screens. The regular window frame is independent of Live's
/// temporary size and position.
@MainActor final class MainWindowFrameMemory: NSObject {
    private weak var window: NSWindow?
    private var normalFrame: NSRect?
    private var wasLive = false
    private var restoring = false
    private var restoreScheduled = false
    private var isLive: () -> Bool = { false }

    func attach(to window: NSWindow, isLive: @escaping () -> Bool) {
        self.isLive = isLive
        if self.window !== window {
            NotificationCenter.default.removeObserver(self)
            self.window = window
            restoreInitialSize(in: window)
            normalFrame = window.styleMask.contains(.fullScreen) ? nil : window.frame
            wasLive = isLive()
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                center.addObserver(self, selector: #selector(frameChanged(_:)), name: name, object: window)
            }
            center.addObserver(self, selector: #selector(didExitFullScreen(_:)), name: NSWindow.didExitFullScreenNotification, object: window)
            for name in [NSWindow.didEndLiveResizeNotification, NSWindow.willCloseNotification] {
                center.addObserver(self, selector: #selector(saveWindowSize(_:)), name: name, object: window)
            }
            center.addObserver(self, selector: #selector(saveWindowSize(_:)), name: NSApplication.willTerminateNotification, object: nil)
        }
        pageChanged()
    }

    private func pageChanged() {
        if isLive() {
            wasLive = true
        } else if wasLive, !restoreScheduled,
                  let window, !window.styleMask.contains(.fullScreen) {
            restoreScheduled = true
            // Let SwiftUI release Live's fixed-size constraint first. Read
            // the current page again so a rapid return to Live cancels this.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreScheduled = false
                guard !self.isLive(), let window = self.window,
                      !window.styleMask.contains(.fullScreen),
                      let saved = self.normalFrame else { return }
                let frame = MainWindowFrameLogic.fitting(saved, in: window.screen?.visibleFrame)
                self.restoring = true
                window.setFrame(frame, display: true, animate: false)
                self.restoring = false
                self.wasLive = false
                self.normalFrame = window.frame
            }
        }
    }

    @objc private func didExitFullScreen(_ note: Notification) {
        pageChanged()
    }

    @objc private func frameChanged(_ note: Notification) {
        // Read the selection directly: resize notifications may precede the
        // bridge's update during a page switch. Never record Live's frame.
        guard !restoring, !wasLive, !isLive(),
              let window, !window.styleMask.contains(.fullScreen) else { return }
        normalFrame = window.frame
    }

    private func restoreInitialSize(in window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        var size = MainWindowSize.load(for: window.screen) ?? MainWindowSize.fallback
        let minimum = MainWindowSize.minimum(on: window.screen)
        size.width = max(size.width, minimum.width)
        size.height = max(size.height, minimum.height)
        let frame = MainWindowFrameLogic.resizing(window.frame, to: size, in: window.screen?.visibleFrame)
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    @objc private func saveWindowSize(_ note: Notification) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        // Closing or quitting from Live must not replace the normal size.
        MainWindowSize.save(normalFrame?.size ?? window.frame.size)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

struct WindowSizeMemory: NSViewRepresentable {
    let memory: MainWindowFrameMemory
    let isLive: () -> Bool

    final class SizeView: NSView {
        var memory: MainWindowFrameMemory?
        var isLive: () -> Bool = { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            memory?.attach(to: window, isLive: isLive)
        }
    }

    func makeNSView(context: Context) -> SizeView {
        let view = SizeView()
        view.memory = memory
        view.isLive = isLive
        return view
    }

    func updateNSView(_ view: SizeView, context: Context) {
        view.memory = memory
        view.isLive = isLive
        view.apply()
    }
}
