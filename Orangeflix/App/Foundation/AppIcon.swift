import AppKit
import SwiftUI

/// The art of an app symbol: the open iris of the brand on the rounded
/// square of a Mac app. It is the mark the app shows at the upper left and
/// the art of the original app icon, not a variation of it; only the
/// background changes from symbol to symbol.
///
/// The square follows the icon grid of macOS: a 1024 canvas with the tile
/// 824 points wide, centred and with 185 points corners.
struct AppIconArt: View {
    let style: AppSettings.AppIcon
    /// The appearance the symbol stands on. The standard symbol follows it;
    /// the two others keep their background in either appearance.
    let dark: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let inset = side * 0.098
            let tile = side - inset * 2
            let corner = tile * 0.224
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            let palette = palette
            // The box of the open mark inside its drawing; centring this
            // box centres the mark, and the size keeps the weight the mark
            // has in the original symbol.
            let markBox = CGRect(x: 0, y: 0.02734, width: 0.97266, height: 0.96094)
            let markSide = side * 0.7217 / markBox.width
            ZStack {
                shape.fill(LinearGradient(colors: [palette.top, palette.bottom],
                                          startPoint: .top, endPoint: .bottom))
                IrisColorMark(blade: palette.blade, leaf: palette.leaf)
                    .frame(width: markSide, height: markSide)
                    .offset(x: (0.5 - markBox.midX) * markSide,
                            y: (0.5 - markBox.midY) * markSide)
            }
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(palette.rim), lineWidth: max(1, side * 0.002))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var palette: IconPalette {
        switch style {
        case .standard:
            // The original symbol in the dark: the open iris in the brand
            // colors on the near-black of the app. In the light it lies on
            // the quiet paper of the light appearance.
            dark
                ? IconPalette(top: Color(hex: "080808"), bottom: Color(hex: "080808"),
                              blade: Color(hex: "F09000"), leaf: Color(hex: "009040"),
                              rim: 0)
                : IconPalette(top: Color(hex: "F8F7F3"), bottom: Color(hex: "E9E6DE"),
                              blade: Color(hex: "F09000"), leaf: Color(hex: "009040"),
                              rim: 0)
        case .bright:
            IconPalette(top: Color(hex: "FFFDF6"), bottom: Color(hex: "F2E2C4"),
                        blade: Color(hex: "F09000"), leaf: Color(hex: "009040"),
                        rim: 0.25)
        case .twilight:
            IconPalette(top: Color(hex: "3A3470"), bottom: Color(hex: "12112A"),
                        blade: Color(hex: "F09000"), leaf: Color(hex: "2FB86B"),
                        rim: 0.12)
        }
    }

    private struct IconPalette {
        let top: Color
        let bottom: Color
        let blade: Color
        let leaf: Color
        let rim: Double
    }
}

/// Paints the chosen symbol on the Dock. macOS switches only the icon of the
/// running app; the Finder keeps the symbol in the bundle. The standard
/// symbol follows the light and the dark appearance of the app.
@MainActor
final class AppIconController: NSObject {
    static let shared = AppIconController()

    private var style: AppSettings.AppIcon = .standard
    private var theme: AppSettings.Theme = .auto
    /// The rendered symbols by style and appearance; rendering 1024 points
    /// takes a moment, so each one is kept.
    private var images: [String: NSImage] = [:]
    private var observes = false

    /// Uses `style` for the Dock, follows `theme`, and paints the icon.
    func apply(style: AppSettings.AppIcon, theme: AppSettings.Theme) {
        self.style = style
        self.theme = theme
        observe()
        paint()
    }

    private func observe() {
        guard !observes else { return }
        observes = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        // The system switched between light and dark; in the automatic mode
        // the standard symbol changes with it.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func refresh() {
        paint()
    }

    private func paint() {
        let dark: Bool = switch theme {
        case .dark: true
        case .light: false
        case .auto: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        let key = "\(style.rawValue)-\(dark)"
        let image = images[key] ?? AppIconRenderer.image(for: style, dark: dark)
        images[key] = image
        NSApp.applicationIconImage = image
    }
}

/// Draws a symbol at the size of the icon of a Mac app; the Dock uses the
/// same drawing as the asset of the bundle.
@MainActor
enum AppIconRenderer {
    static func image(for style: AppSettings.AppIcon, dark: Bool) -> NSImage {
        let content = AppIconArt(style: style, dark: dark)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: NSSize(width: 1024, height: 1024))
    }
}