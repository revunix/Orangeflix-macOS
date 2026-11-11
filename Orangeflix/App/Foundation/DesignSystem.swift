import AppKit
import SwiftUI

// MARK: - Colors

extension NSColor {
    /// A color from a hex string ("F19100", "#f19100", "F19100FF").
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let alpha: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        switch cleaned.count {
        case 3:
            red = CGFloat((value >> 8) & 0xF) / 15
            green = CGFloat((value >> 4) & 0xF) / 15
            blue = CGFloat(value & 0xF) / 15
            alpha = 1
        case 6:
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
            alpha = CGFloat((value >> 8) & 0xFF) / 255
        default:
            red = 1
            green = 0
            blue = 0
            alpha = 1
        }
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Color {
    /// A color from a hex string.
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A color that follows the appearance of the system.
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// The colors of the app. The brand colors, surfaces, texts and lines come
/// from the active theme (`ThemeRuntime`); the defaults follow the palette of
/// orangeflix.de: a warm
/// orange on warm neutrals, the green of the leaves of the logo and quiet
/// semantic colors for the states.
enum Palette {
    // MARK: Accent

    /// The brand color of orangeflix (the orange of the closed iris).
    static let accent = Color(token: .accent)
    /// The accent as a quiet background (the selected row, a highlighted chip).
    static let accentSoft = Color(token: .accentSoft)
    /// The accent in a darker shade for text on a light background.
    static let accentText = Color(token: .accentText)
    /// The green of the leaves of the logo.
    static let leaf = Color(light: "00753A", dark: "35B36B")
    static let leafSoft = Color(light: "E4F3EA", dark: "16281D")

    // MARK: Surfaces

    /// The page behind everything.
    static let background = Color(token: .background)
    /// A card or a list row.
    static let surface = Color(token: .surface)
    /// A card that floats over the page.
    static let surfaceRaised = Color(token: .surfaceRaised)
    /// A quiet area (the log, an empty state).
    static let surfaceMuted = Color(token: .surfaceMuted)

    // MARK: Text

    static let textPrimary = Color(token: .textPrimary)
    static let textSecondary = Color(token: .textSecondary)
    static let textTertiary = Color(token: .textTertiary)
    /// The ink of the logo at rest (the open iris stands white on a dark page).
    static let ink = Color(token: .ink)

    // MARK: Lines

    static let divider = Color(token: .divider)
    static let border = Color(token: .border)

    // MARK: Semantics

    static let success = Color(light: "1F7A44", dark: "7FD69E")
    static let successSoft = Color(light: "E3F3E9", dark: "16281D")
    static let warning = Color(light: "9A6200", dark: "F5B04C")
    static let warningSoft = Color(light: "FBF0DC", dark: "2A1F10")
    static let danger = Color(light: "B3261E", dark: "F0A9A2")
    static let dangerSoft = Color(light: "FBE9E7", dark: "2E1A18")
    static let info = Color(light: "1F5FA8", dark: "8FBDE8")
    static let infoSoft = Color(light: "E7F0FA", dark: "17222E")
    /// The red dot of the live show and the frame of a running stream.
    static let live = Color(light: "D92D20", dark: "FF5A4E")
}

// MARK: - Typography

/// The type scale of the app. Everything uses San Francisco, the system
/// font. The digits of the counters stay in equal width (`monospacedDigit`),
/// so the columns of the lists stand still without another typeface.
enum AppFont {
    /// Screen titles.
    static let display = Font.system(size: 22, weight: .semibold)
    static let displaySmall = Font.system(size: 17, weight: .semibold)
    /// The title over the artwork of a series.
    static let hero = Font.system(size: 32, weight: .bold)
    /// Section titles.
    static let heading = Font.system(size: 15, weight: .semibold)
    /// Titles of rows and cards.
    static let subheading = Font.system(size: 13, weight: .semibold)
    /// The text itself.
    static let body = Font.system(size: 13, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)
    /// Labels, metadata, timestamps.
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    /// The smallest label of the app: a badge over a picture, a dot legend.
    static let micro = Font.system(size: 10, weight: .semibold)
    /// Digits that stand in a column: San Francisco with equal-width figures.
    static let digits = Font.system(size: 11, weight: .regular).monospacedDigit()
    static let digitsMedium = Font.system(size: 12, weight: .medium).monospacedDigit()
}

// MARK: - Spacing

/// The spacing grid: multiples of four.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// The margin of a page at the left and right edge of the window. Every
    /// screen uses it, so the content lines up from page to page.
    static let page: CGFloat = 24
    static let huge: CGFloat = 48
}

/// The corners of the surfaces. A card and everything inside it share one
/// curve: the inner radius is the outer one minus the padding between them.
enum Radius {
    static let s: CGFloat = 4
    static let m: CGFloat = 7
    static let l: CGFloat = 10
    /// A card of the content (an episode, a download).
    static let card: CGFloat = 14
    /// A big panel: the chat of a live show, the chrome of the player.
    static let panel: CGFloat = 20
    /// A control inside a card (a thumbnail in a row).
    static let inner: CGFloat = 10
}

/// The metrics of the window chrome. All values are points, so the layout is
/// independent of the display density; hairlines stay one physical pixel.
enum Chrome {
    /// Size of the round icon actions in page headers.
    static let actionSize: CGFloat = 34

    /// The height of the banner over the Mediathek and above a format.
    static let heroHeight: CGFloat = 440
    /// The padding inside a pill button.
    static let pillPadH: CGFloat = Space.m
    static let pillPadV: CGFloat = 9

    /// One physical pixel on Retina and on 1x displays.
    static func hairline(_ displayScale: CGFloat) -> CGFloat {
        1 / max(displayScale, 1)
    }
}

// MARK: - Shared shapes

/// A small colored label (the status of an episode, the state of a format).
struct BrandPill: View {
    let text: String
    var color: Color = Palette.textSecondary
    var background: Color = Palette.surfaceMuted
    var font: Font = AppFont.captionMedium

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

/// A heading above a group of rows: small, quiet, in capitals.
struct SectionLabel: View {
    let text: String
    /// An optional symbol in front of the words.
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                Label(text.uppercased(), systemImage: symbol)
            } else {
                Text(text.uppercased())
            }
        }
        .font(AppFont.captionMedium)
        .tracking(0.8)
        .foregroundStyle(Palette.textTertiary)
    }
}

/// The heading of a section: the title in the small display size, the count
/// of its rows on the right.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title)
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            if let detail {
                Text(detail)
                    .font(AppFont.digits)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A line between two areas: one physical pixel of the divider color.
struct Hairline: View {
    var vertical = false
    /// The color of the line; the accent under a banner, the divider between
    /// two rows.
    var color: Color = Palette.divider
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = Chrome.hairline(displayScale)
        Rectangle()
            .fill(color)
            .frame(width: vertical ? thickness : nil, height: vertical ? nil : thickness)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
    }
}

/// The button of the app: a capsule with a title and an optional symbol. On
/// macOS 26 it is the Liquid Glass button of the system, so it follows the
/// light and the dark appearance by itself.
struct PillButton: View {
    enum Style {
        /// The main action: glass tinted in the accent, white ink.
        case accent
        /// An action on the page: clear glass with the ink of the appearance.
        case glass
        /// An action over a picture: dark glass
        /// with white ink in either appearance.
        case onPicture
    }

    let title: String
    var symbol: String?
    var style: Style = .accent
    let action: () -> Void

    var body: some View {
        if #available(macOS 26, *), interfaceStyle == .glass, glassPanels {
            glassButton
        } else {
            fallbackButton
        }
    }

    @available(macOS 26, *)
    @ViewBuilder private var glassButton: some View {
        let button = Button(action: action) {
            label
                .font(AppFont.subheading)
                .padding(.horizontal, Space.xxs)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        switch style {
        case .accent:
            button.buttonStyle(.glassProminent).tint(Palette.accent)
        case .glass:
            button.buttonStyle(.glass).foregroundStyle(Palette.textPrimary)
        case .onPicture:
            button.buttonStyle(.glass).foregroundStyle(.white).environment(\.colorScheme, .dark)
        }
    }

    /// Before macOS 26: the accent or a material capsule.
    private var fallbackButton: some View {
        Button(action: action) {
            label
                .font(AppFont.subheading)
                .foregroundStyle(style == .glass ? Palette.textPrimary : .white)
                .padding(.horizontal, Chrome.pillPadH)
                .padding(.vertical, Chrome.pillPadV)
                .background {
                    if style == .accent {
                        Capsule().fill(Palette.accent)
                    } else if style == .onPicture {
                        Capsule().fill(Color.black.opacity(0.45))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
                    } else if interfaceStyle == .glass, glassPanels {
                        Capsule().fill(.regularMaterial)
                    } else {
                        Capsule().fill(Palette.surfaceRaised)
                            .overlay(Capsule().strokeBorder(Palette.border))
                    }
                }
                .environment(\.colorScheme, style == .onPicture ? .dark : colorScheme)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.interfaceStyle) private var interfaceStyle
    @Environment(\.glassPanels) private var glassPanels

    @ViewBuilder private var label: some View {
        if let symbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }
}

extension View {
    /// The Liquid Glass button of the system for a button or a menu; a
    /// bordered capsule before macOS 26 and in the classic style.
    func glassButtonStyle() -> some View {
        modifier(GlassButtons())
    }
}

private struct GlassButtons: ViewModifier {
    @Environment(\.interfaceStyle) private var interfaceStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), interfaceStyle == .glass {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// An empty page: a quiet symbol, the reason and an optional explanation.
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textPrimary)
            if let message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }
}

/// A label and its value, the way the inspector of the TUI shows them.
struct BrandDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Palette.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(AppFont.bodySmall)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A line of the Protokoll: the time in monospaced digits, the text next to
/// it. Errors carry the danger color.
struct BrandLogLine: View {
    let entry: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(AppFormat.clock(entry.time))
                .font(AppFont.digits)
                .foregroundStyle(Palette.textTertiary)
            Text(entry.text)
                .font(AppFont.bodySmall)
                .foregroundStyle(entry.isError ? Palette.danger : Palette.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Interface style

private struct InterfaceStyleKey: EnvironmentKey {
    static let defaultValue: AppSettings.InterfaceStyle = .glass
}

private struct GlassPanelsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the app draws the chrome it owns in glass or on a plain
    /// surface.
    var interfaceStyle: AppSettings.InterfaceStyle {
        get { self[InterfaceStyleKey.self] }
        set { self[InterfaceStyleKey.self] = newValue }
    }

    /// Whether the plates of the app are glass. Only the glass style has the
    /// choice; the classic style ignores it.
    var glassPanels: Bool {
        get { self[GlassPanelsKey.self] }
        set { self[GlassPanelsKey.self] = newValue }
    }
}

// MARK: - Glass

extension View {
    /// A plate of the app: Liquid glass on macOS 26, a thin material before;
    /// the classic style draws a plain surface with one hairline instead. A
    /// tint colours the own chat bubbles; interactive glass brightens under
    /// the pointer.
    func glassPlate<S: Shape>(
        in shape: S, tint: Color? = nil, interactive: Bool = false, quietAppear: Bool = false
    ) -> some View {
        modifier(GlassPlate(shape: shape, tint: tint, interactive: interactive, quietAppear: quietAppear))
    }

    /// The scroll edge of macOS 26: content fades under the toolbar instead
    /// of ending at a hard line. Older systems keep the plain edge.
    @ViewBuilder
    func softScrollEdge(_ edges: Edge.Set = .top) -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    /// Suppresses macOS 26's top scroll-edge shadow on screens where a video
    /// stage sits right beneath the toolbar.
    @ViewBuilder
    func hiddenScrollEdge(_ edges: Edge.Set = .top) -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }

    /// A card of the content: a calm surface with one hairline. The glass
    /// belongs to the chrome above it, so rows never stack glass on glass.
    @ViewBuilder
    func contentCard(radius: CGFloat = Radius.card, selected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        self
            .background(selected ? Palette.accentSoft : Palette.surface, in: shape)
            .overlay {
                shape.strokeBorder(selected ? Palette.accent.opacity(0.45) : Palette.divider, lineWidth: 1)
            }
    }
}

/// The plate itself; it reads the style from the environment, so every
/// plate of the app follows the setting without knowing it.
private struct GlassPlate<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    /// Skips the scale-in Liquid Glass plays the first time a plate appears.
    var quietAppear = false

    @Environment(\.interfaceStyle) private var interfaceStyle
    @Environment(\.glassPanels) private var glassPanels

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsGlass {
            if #available(macOS 26, *) {
                macOS26Glass(content)
            } else {
                content
                    .background {
                        if let tint {
                            shape.fill(tint.opacity(0.28))
                        }
                    }
                    .background(.ultraThinMaterial, in: shape)
            }
        } else {
            content
                .background {
                    shape.fill(tint.map { $0.opacity(0.42) } ?? Palette.surfaceRaised)
                }
                .overlay {
                    shape.stroke(tint == nil ? Palette.border : .clear, lineWidth: 1)
                }
        }
    }

    private var showsGlass: Bool {
        interfaceStyle == .glass && glassPanels
    }

    /// The default glass transition scales the plate up from nothing. A field
    /// that is already part of the page, such as the search field, should be
    /// there at once.
    @available(macOS 26, *)
    @ViewBuilder
    private func macOS26Glass(_ content: Content) -> some View {
        if quietAppear {
            content
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
                .glassEffectTransition(.identity)
        } else {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        }
    }
}

/// Lays its views out in rows and starts a new row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Rounds the size of its content up to whole pixels of the display. Text has
/// line heights like 15.5 pt; stacked up, they push everything below onto
/// half pixels, and on a display without Retina the letters turn soft. A
/// list of snapped rows stays on the pixel grid.
struct PixelSnapped: Layout {
    let scale: CGFloat

    private func snap(_ value: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return (value * scale).rounded(.up) / scale
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(proposal)
        return CGSize(width: snap(size.width), height: snap(size.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let origin = CGPoint(x: (bounds.minX * scale).rounded() / max(scale, 1),
                             y: (bounds.minY * scale).rounded() / max(scale, 1))
        view.place(at: origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct PixelSnapModifier: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        PixelSnapped(scale: displayScale) { content }
    }
}

extension View {
    /// Keeps the view on whole pixels of the display, so its text stays sharp
    /// without Retina too.
    func snappedToPixels() -> some View {
        modifier(PixelSnapModifier())
    }
}

/// True while an inline video stage (`EpisodeDetailScreen` or `LiveScreen`) is
/// currently mounted and showing the running playback, so the floating
/// NowPlaying mini-bar stays tucked away.
struct InlineStageVisibleKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
