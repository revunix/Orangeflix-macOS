import AppKit
import SwiftUI

/// Remembers the size of the main window, so the app opens the way it was
/// left. Only the size is kept; the place belongs to the window server.
enum MainWindowSize {
    private static let widthKey = "mainWindowWidth"
    private static let heightKey = "mainWindowHeight"

    /// The size of the first start; the scene names the same numbers.
    static let fallback = NSSize(width: 1_240, height: 1_000)

    /// The smallest window frame on every page.
    static let minimumSize = NSSize(width: 1_000, height: 1_000)
    /// The smallest window frame on the Live page: the show, the picture and
    /// the chat need more height.
    static let liveMinimumSize = NSSize(width: 1_000, height: 1_000)

    /// The smallest frame for a page, never larger than the screen offers.
    static func minimum(live: Bool, on screen: NSScreen?) -> NSSize {
        let size = live ? liveMinimumSize : minimumSize
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

/// Applies the stored size to the window it lands in and writes the size
/// back when the user is done with it: after a live resize, when the window
/// closes and when the app quits. The resize that SwiftUI does while the
/// window is built is none of these, so it never becomes the stored size.
struct WindowSizeMemory: NSViewRepresentable {
    final class SizeView: NSView {
        private weak var watchedWindow: NSWindow?
        private var didRestore = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = window, watchedWindow !== window else { return }
            watchedWindow = window
            restore(in: window)
            didRestore = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(saveWindowSize(_:)),
                name: NSWindow.didEndLiveResizeNotification,
                object: window)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(saveWindowSize(_:)),
                name: NSWindow.willCloseNotification,
                object: window)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(saveWindowSize(_:)),
                name: NSApplication.willTerminateNotification,
                object: nil)
        }

        /// The stored size is a wish: the content asks for its minimum, so a
        /// too small value ends at the minimum of the window.
        private func restore(in window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen) else { return }
            var size = MainWindowSize.load(for: window.screen) ?? MainWindowSize.fallback
            // A size stored before the minimum existed grows to it.
            let minimum = MainWindowSize.minimum(live: false, on: window.screen)
            size.width = max(size.width, minimum.width)
            size.height = max(size.height, minimum.height)
            if let visible = window.screen?.visibleFrame.size {
                size.width = min(size.width, visible.width)
                size.height = min(size.height, visible.height)
            }
            var frame = window.frame
            guard abs(frame.width - size.width) > 1 || abs(frame.height - size.height) > 1 else { return }
            frame.size = size
            window.setFrame(frame, display: true)
        }

        @objc private func saveWindowSize(_ note: Notification) {
            guard didRestore else { return }
            let window = (note.object as? NSWindow) ?? watchedWindow
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            MainWindowSize.save(window.frame.size)
        }
    }

    func makeNSView(context: Context) -> SizeView { SizeView() }

    func updateNSView(_ view: SizeView, context: Context) {}
}

