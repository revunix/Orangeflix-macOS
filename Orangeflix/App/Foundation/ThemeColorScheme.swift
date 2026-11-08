import AppKit
import SwiftUI

extension AppSettings.Theme {
    /// The German name of the appearance (the settings and the Go TUI).
    var label: String {
        switch self {
        case .auto: "automatisch"
        case .dark: "dunkel"
        case .light: "hell"
        }
    }

    /// The appearance of the app; nil for "automatisch", so AppKit follows
    /// the look of the Mac, also when it changes while the app runs.
    var appAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// Applies the appearance of the settings to every window of the app. The
/// view applies it again when it reaches a window.
struct WindowAppearance: NSViewRepresentable {
    let theme: AppSettings.Theme

    final class AppearanceView: NSView {
        var theme: AppSettings.Theme = .auto {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            let appearance = theme.appAppearance
            DispatchQueue.main.async {
                NSApp.appearance = appearance
                // A window with an own appearance would ignore the app's;
                // every window inherits it.
                for window in NSApp.windows where window.appearance != nil {
                    window.appearance = nil
                }
            }
        }
    }

    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.theme = theme
        return view
    }

    func updateNSView(_ view: AppearanceView, context: Context) {
        view.theme = theme
    }
}
