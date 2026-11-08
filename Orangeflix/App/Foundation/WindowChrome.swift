import AppKit
import SwiftUI

/// Lets the window content draw underneath a transparent titlebar, so the
/// sidebar of a window reaches the top edge and no band stands above it.
struct TitlebarTransparency: NSViewRepresentable {
    /// Hides the title next to the traffic lights; a window whose content
    /// names itself needs no second heading in the bar.
    var hidesTitle = false

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.hidesTitle = hidesTitle
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.hidesTitle = hidesTitle
        view.applyWhenAttached()
    }

    final class ChromeView: NSView {
        var hidesTitle = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWhenAttached()
        }

        func applyWhenAttached() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.styleMask.insert(.fullSizeContentView)
                if self.hidesTitle {
                    window.titleVisibility = .hidden
                    window.title = ""
                }
            }
        }
    }
}

/// Sets the size of the content of a window. A `Settings` window does not
/// take the size of its view, so the size goes to the window itself; the
/// `defaultSize` of the scene gives it that size from the first frame on.
struct WindowContentSize: NSViewRepresentable {
    /// The width of the content in points.
    var width: CGFloat
    /// The height of the content in points.
    var height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = SizeView()
        view.onWindow = { window in
            window.setContentSize(NSSize(width: width, height: height))
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? SizeView)?.onWindow = { window in
            window.setContentSize(NSSize(width: width, height: height))
        }
    }

    /// Hands the window it lives in to the closure.
    final class SizeView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow?(window)
        }
    }
}

/// Widens the window to `minimum` while it is set: a narrower window grows
/// around its middle and stays on the screen. When the floor is gone and
/// `restoresWidth` is set, the window goes back to the width it had, unless
/// the user resized it in between. The SwiftUI frame of the content keeps
/// the user from making it narrower again.
struct WindowWidthFloor: NSViewRepresentable {
    /// The narrowest width of the window frame; 0 for none.
    var minimum: CGFloat
    /// Whether the window may return to its earlier width once the floor
    /// is gone.
    var restoresWidth: Bool

    func makeNSView(context: Context) -> FloorView { FloorView() }

    func updateNSView(_ view: FloorView, context: Context) {
        view.update(minimum: minimum, restoresWidth: restoresWidth)
    }

    final class FloorView: NSView {
        private var minimum: CGFloat = 0
        private var restoresWidth = true
        /// The width before the floor widened the window.
        private var widthBefore: CGFloat?
        /// The width the floor gave the window.
        private var widenedTo: CGFloat?

        func update(minimum: CGFloat, restoresWidth: Bool) {
            guard minimum != self.minimum || restoresWidth != self.restoresWidth else { return }
            self.minimum = minimum
            self.restoresWidth = restoresWidth
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let frame = window.frame
            if minimum > 0 {
                guard frame.width < minimum - 0.5 else { return }
                if widthBefore == nil { widthBefore = frame.width }
                setWidth(minimum, of: window)
                widenedTo = window.frame.width
            } else if restoresWidth, let before = widthBefore {
                // A width the user chose in the meantime stays.
                if let widenedTo, abs(frame.width - widenedTo) < 1 { setWidth(before, of: window) }
                widthBefore = nil
                widenedTo = nil
            }
        }

        /// Changes the width around the middle of the window and keeps it
        /// inside the visible part of its screen.
        private func setWidth(_ width: CGFloat, of window: NSWindow) {
            var frame = window.frame
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
            let target = min(width, visible.width)
            frame.origin.x -= (target - frame.width) / 2
            frame.size.width = target
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

/// Puts a SwiftUI view into the titlebar of the window, at a fixed distance
/// from the left edge and centred on the traffic lights. The titlebar lies
/// above the content and takes its clicks, so a button under it never
/// reacts; a view that is part of the titlebar does.
struct TitlebarContent<Content: View>: NSViewRepresentable {
    /// The distance of the content from the left edge of the window.
    var leading: CGFloat
    let content: Content

    init(leading: CGFloat, @ViewBuilder content: () -> Content) {
        self.leading = leading
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let root = content
        let leading = leading
        DispatchQueue.main.async {
            if let host = coordinator.host {
                host.rootView = root
                return
            }
            guard let window = view.window,
                  let close = window.standardWindowButton(.closeButton),
                  let bar = close.superview else { return }
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: leading),
                host.centerYAnchor.constraint(equalTo: close.centerYAnchor, constant: 6),
            ])
            coordinator.host = host
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.host?.removeFromSuperview()
        coordinator.host = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps the hosting view of the titlebar.
    final class Coordinator {
        var host: NSHostingView<Content>?
    }
}
