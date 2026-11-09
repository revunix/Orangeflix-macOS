import AppKit
import SwiftUI

/// How the Live page grows with its picture: a picture of height `s` at 16:9
/// needs a page of `s · 16/9 + extraWidth` by `s + extraHeight`. The extras
/// are what stands around the picture: the margins, the show above it and
/// the chat beside or under it.
struct LivePageGeometry: Equatable {
    var extraWidth: CGFloat
    var extraHeight: CGFloat
    /// The lowest picture; the window never gets smaller than its page.
    var minStage: CGFloat

    /// The room above the page for the titlebar with the toolbar, until the
    /// window says how much it really is.
    static let titlebarRoom: CGFloat = 60

    func pageSize(stage: CGFloat) -> CGSize {
        CGSize(width: (stage * 16 / 9 + extraWidth).rounded(), height: (stage + extraHeight).rounded())
    }

    /// The picture a page holds.
    func stage(fitting page: CGSize) -> CGFloat {
        min((page.width - extraWidth) * 9 / 16, page.height - extraHeight)
    }

    /// The highest picture the visible part of a screen holds.
    func maxStage(in visible: CGSize, chrome: CGFloat = titlebarRoom) -> CGFloat {
        max(stage(fitting: CGSize(width: visible.width, height: visible.height - chrome)).rounded(.down), minStage)
    }

    var minPage: CGSize { pageSize(stage: minStage) }
}

/// The geometry the Live page asks of the window; nil on every other page.
struct LivePageGeometryKey: PreferenceKey {
    static var defaultValue: LivePageGeometry? { nil }
    static func reduce(value: inout LivePageGeometry?, nextValue: () -> LivePageGeometry?) {
        value = nextValue() ?? value
    }
}

/// Makes the window of the Live page grow like a video player: dragging an
/// edge or a corner scales the picture, and the page around it follows, so
/// nothing empty opens beside it. The height of the picture is kept for the
/// next visit.
struct LiveWindowSizing: NSViewRepresentable {
    let geometry: LivePageGeometry?

    /// The key of the picture height kept for the next visit.
    static let stageKey = "liveStageHeight"
    /// Posted when the standard size is asked for again.
    static let resetNotification = Notification.Name("LiveWindowSizing.reset")

    /// Gives the Live window its standard picture again: the stored height
    /// goes, and the window takes the default on its next pass.
    static func resetStage() {
        UserDefaults.standard.removeObject(forKey: stageKey)
        NotificationCenter.default.post(name: resetNotification, object: nil)
    }

    func makeNSView(context: Context) -> SizerView { SizerView() }

    func updateNSView(_ view: SizerView, context: Context) {
        view.update(geometry)
    }

    final class SizerView: NSView {
        /// The picture of the first visit, before the reader has sized the window.
        private static let defaultStage: CGFloat = 600

        private var geometry: LivePageGeometry?
        /// The geometry the window was last sized for.
        private var applied: LivePageGeometry?
        private weak var observed: NSWindow?
        private var listensForReset = false

        func update(_ geometry: LivePageGeometry?) {
            guard geometry != self.geometry else { return }
            self.geometry = geometry
            // SwiftUI changes the limits of the window in the same pass;
            // the frame follows after it.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func viewDidMoveToWindow() {
            if !listensForReset {
                listensForReset = true
                NotificationCenter.default.addObserver(self, selector: #selector(resetRequested(_:)),
                                                       name: LiveWindowSizing.resetNotification, object: nil)
            }
            super.viewDidMoveToWindow()
            observe(window)
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func observe(_ window: NSWindow?) {
            guard observed !== window else { return }
            let center = NotificationCenter.default
            if let observed {
                center.removeObserver(self, name: nil, object: observed)
            }
            observed = window
            guard let window else { return }
            center.addObserver(self, selector: #selector(didResize(_:)),
                               name: NSWindow.didResizeNotification, object: window)
            center.addObserver(self, selector: #selector(didEndLiveResize(_:)),
                               name: NSWindow.didEndLiveResizeNotification, object: window)
        }

        /// The height of the titlebar with the toolbar above the page.
        private func chrome(of window: NSWindow) -> CGFloat {
            let chrome = window.frame.height - window.contentLayoutRect.height
            return chrome > 0 ? chrome : LivePageGeometry.titlebarRoom
        }

        /// The size of the page in the window now.
        private func page(of window: NSWindow) -> CGSize {
            CGSize(width: window.frame.width, height: window.frame.height - chrome(of: window))
        }

        /// The picture clamped between the smallest one and the screen.
        private func clamped(_ stage: CGFloat, _ geometry: LivePageGeometry, in window: NSWindow) -> CGFloat {
            var upper = CGFloat.greatestFiniteMagnitude
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size {
                upper = geometry.maxStage(in: visible, chrome: chrome(of: window))
            }
            return min(max(stage, geometry.minStage), upper).rounded()
        }

        private func frameSize(_ stage: CGFloat, _ geometry: LivePageGeometry, in window: NSWindow) -> NSSize {
            let page = geometry.pageSize(stage: stage)
            return NSSize(width: page.width, height: page.height + chrome(of: window))
        }

        /// Sizes the window for the page: on the first visit to the picture
        /// of the last one, after a change of the layout to the picture it
        /// has now.
        private func apply() {
            guard let window else { return }
            observe(window)
            guard let geometry else {
                if applied != nil {
                    // Every other page resizes freely again, and keeps no
                    // ratio of the picture.
                    window.resizeIncrements = NSSize(width: 1, height: 1)
                    window.aspectRatio = .zero
                    applied = nil
                }
                return
            }
            guard !window.styleMask.contains(.fullScreen) else { return }
            if window.inLiveResize, applied != nil {
                // The page changed under the pointer; the end of the drag
                // settles the frame.
                applied = geometry
                return
            }
            let stage: CGFloat
            if let applied {
                stage = applied.stage(fitting: page(of: window))
            } else {
                let stored = UserDefaults.standard.double(forKey: LiveWindowSizing.stageKey)
                stage = stored > 0 ? stored : Self.defaultStage
            }
            applied = geometry
            setStage(clamped(stage, geometry, in: window), geometry, in: window)
        }

        private func setStage(_ stage: CGFloat, _ geometry: LivePageGeometry, in window: NSWindow) {
            let size = frameSize(stage, geometry, in: window)
            window.aspectRatio = size
            guard abs(window.frame.width - size.width) > 0.5 || abs(window.frame.height - size.height) > 0.5 else { return }
            let frame = MainWindowFrameLogic.resizing(window.frame, to: size, in: window.screen?.visibleFrame)
            window.setFrame(frame, display: true, animate: false)
        }

        /// The standard size was asked for: the window takes the default
        /// picture, as on the first visit.
        @objc private func resetRequested(_ note: Notification) {
            applied = nil
            apply()
        }

        /// While the reader drags, the ratio follows the picture, since the
        /// room around it does not grow with it.
        @objc private func didResize(_ note: Notification) {
            guard let window, window.inLiveResize, let geometry,
                  !window.styleMask.contains(.fullScreen) else { return }
            let stage = geometry.stage(fitting: page(of: window))
            window.aspectRatio = frameSize(stage, geometry, in: window)
        }

        /// After the drag the window takes the exact page of its picture,
        /// which the next visit keeps.
        @objc private func didEndLiveResize(_ note: Notification) {
            guard let window, let geometry, !window.styleMask.contains(.fullScreen) else { return }
            let stage = clamped(geometry.stage(fitting: page(of: window)), geometry, in: window)
            UserDefaults.standard.set(Double(stage), forKey: LiveWindowSizing.stageKey)
            setStage(stage, geometry, in: window)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
