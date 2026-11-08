import AppKit
import Foundation
import SwiftUI

// MARK: - Colors

/// An sRGB color with components from 0 to 1, for mixing the colors of a theme.
struct ThemeRGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Reads "F19100", "#f19100" or "f90"; nil for anything else.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        switch cleaned.count {
        case 3:
            self.init(red: Double((value >> 8) & 0xF) / 15, green: Double((value >> 4) & 0xF) / 15,
                      blue: Double(value & 0xF) / 15)
        case 6, 8:
            let shift: UInt64 = cleaned.count == 8 ? 8 : 0
            self.init(red: Double((value >> (16 + shift)) & 0xFF) / 255,
                      green: Double((value >> (8 + shift)) & 0xFF) / 255,
                      blue: Double((value >> shift) & 0xFF) / 255)
        default:
            return nil
        }
    }

    /// The color of an AppKit color; nil when it has no sRGB form.
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                  blue: Double(rgb.blueComponent))
    }

    var hex: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The relative luminance (WCAG).
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// `self` moved by `amount` (0...1) towards `other`.
    func mixed(with other: ThemeRGB, _ amount: Double) -> ThemeRGB {
        ThemeRGB(red: red + (other.red - red) * amount,
                 green: green + (other.green - green) * amount,
                 blue: blue + (other.blue - blue) * amount)
    }

    static let white = ThemeRGB(red: 1, green: 1, blue: 1)
    static let black = ThemeRGB(red: 0, green: 0, blue: 0)

    /// A color from hue (degrees), saturation and lightness.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> ThemeRGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) / 60)
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return ThemeRGB(red: r + m, green: g + m, blue: b + m)
    }
}

/// The colors a theme decides. Hex strings, so a theme is plain JSON.
struct ThemeColors: Codable, Hashable, Sendable {
    var accent: String
    var accentSoft: String
    var accentText: String
    var background: String
    var surface: String
    var surfaceRaised: String
    var surfaceMuted: String
    var textPrimary: String
    var textSecondary: String
    var textTertiary: String
    var ink: String
    var divider: String
    var border: String

    func hex(_ token: ThemeToken) -> String {
        switch token {
        case .accent: accent
        case .accentSoft: accentSoft
        case .accentText: accentText
        case .background: background
        case .surface: surface
        case .surfaceRaised: surfaceRaised
        case .surfaceMuted: surfaceMuted
        case .textPrimary: textPrimary
        case .textSecondary: textSecondary
        case .textTertiary: textTertiary
        case .ink: ink
        case .divider: divider
        case .border: border
        }
    }
}

/// The colors of `Palette` a theme replaces.
enum ThemeToken: Sendable {
    case accent, accentSoft, accentText
    case background, surface, surfaceRaised, surfaceMuted
    case textPrimary, textSecondary, textTertiary, ink
    case divider, border

    /// The brand colors; they follow the theme even when its palette is not
    /// extended.
    var isAccent: Bool {
        switch self {
        case .accent, .accentSoft, .accentText: true
        default: false
        }
    }
}

// MARK: - Theme

/// A look of the app for one appearance: the colors and the dots that show
/// the character of the theme in the picker.
struct AppTheme: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    /// True for a theme of the dark appearance.
    var isDark: Bool
    var colors: ThemeColors
    /// Eight hex colors for the dots of the preview.
    var swatches: [String]

    /// A theme built from a few base colors; the surfaces, lines and the
    /// quieter texts follow from them.
    init(id: String, name: String, isDark: Bool, background: ThemeRGB, foreground: ThemeRGB,
         accent: ThemeRGB, palette: [ThemeRGB]? = nil) {
        self.id = id
        self.name = name
        self.isDark = isDark
        let mix = { (amount: Double) in background.mixed(with: foreground, amount) }
        let surface = isDark ? mix(0.06) : background.mixed(with: .white, 0.7)
        let raised = isDark ? mix(0.09) : background.mixed(with: .white, 0.85)
        colors = ThemeColors(
            accent: accent.hex,
            accentSoft: background.mixed(with: accent, isDark ? 0.16 : 0.14).hex,
            accentText: (isDark ? accent.mixed(with: .white, 0.12) : accent.mixed(with: .black, 0.28)).hex,
            background: background.hex,
            surface: surface.hex,
            surfaceRaised: raised.hex,
            surfaceMuted: (isDark ? mix(0.03) : mix(0.05)).hex,
            textPrimary: foreground.hex,
            textSecondary: foreground.mixed(with: background, 0.32).hex,
            textTertiary: foreground.mixed(with: background, 0.52).hex,
            ink: foreground.hex,
            divider: (isDark ? mix(0.12) : mix(0.1)).hex,
            border: (isDark ? mix(0.2) : mix(0.17)).hex)
        if let palette, palette.count >= 7 {
            swatches = (palette.prefix(7).map(\.hex)) + [accent.hex]
        } else {
            let saturation = isDark ? 0.62 : 0.58
            let lightness = isDark ? 0.64 : 0.46
            let hues: [Double] = [2, 32, 52, 140, 212, 282]
            swatches = [mix(0.4).hex] + hues.map { ThemeRGB.hsl($0, saturation, lightness).hex } + [accent.hex]
        }
    }

    /// A theme with every color given.
    init(id: String, name: String, isDark: Bool, colors: ThemeColors, swatches: [String]) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.colors = colors
        self.swatches = swatches
    }

    private static func rgb(_ hex: String) -> ThemeRGB { ThemeRGB(hex: hex) ?? .black }

    private static func built(_ id: String, _ name: String, dark: Bool, _ background: String,
                              _ foreground: String, _ accent: String) -> AppTheme {
        AppTheme(id: id, name: name, isDark: dark, background: rgb(background),
                 foreground: rgb(foreground), accent: rgb(accent))
    }

    // MARK: Built-in

    /// The look the app had before themes: the default of the light mode.
    static let orangeflixLight = AppTheme(
        id: "orangeflix-light", name: "Orangeflix Hell", isDark: false,
        colors: ThemeColors(
            accent: "C27400", accentSoft: "FBF0DC", accentText: "8A5200",
            background: "F7F5F0", surface: "FFFFFF", surfaceRaised: "FFFFFF", surfaceMuted: "EFECE5",
            textPrimary: "1A1815", textSecondary: "6B6660", textTertiary: "928C83", ink: "3A352E",
            divider: "E4E0D8", border: "D8D3C8"),
        swatches: ["6B6660", "B3261E", "C27400", "9A6200", "1F7A44", "1F5FA8", "7A4FB0", "C27400"])

    /// The default of the dark mode.
    static let orangeflixDark = AppTheme(
        id: "orangeflix-dark", name: "Orangeflix Dunkel", isDark: true,
        colors: ThemeColors(
            accent: "F19100", accentSoft: "2A1F10", accentText: "F5A019",
            background: "131210", surface: "1C1A17", surfaceRaised: "232019", surfaceMuted: "191714",
            textPrimary: "F4F1EA", textSecondary: "A8A196", textTertiary: "7C766C", ink: "F4F4F5",
            divider: "2C2823", border: "3A352E"),
        swatches: ["7C766C", "F0A9A2", "F19100", "F5B04C", "7FD69E", "8FBDE8", "B79AE0", "F19100"])

    static let builtInLight: [AppTheme] = [
        built("alpine-milk", "Alpenmilch", dark: false, "EEF2F6", "1E2A36", "3A7BD5"),
        built("buttercream-diner", "Butterkeks", dark: false, "FBF1D6", "3B2F20", "D9622B"),
        built("coastal-linen", "Küstenleinen", dark: false, "E7F0EF", "1D3335", "2A8C9E"),
        built("lavender-dusk", "Lavendeldämmerung", dark: false, "F1EDF7", "2B2340", "7C4DDB"),
        built("sage-field", "Salbeifeld", dark: false, "F1F4EA", "242B1E", "5F8C4E"),
        built("rose-paper", "Rosenpapier", dark: false, "FBF0F1", "3A2428", "C2557A"),
        built("dandelion", "Löwenzahn", dark: false, "F8F4E2", "33301B", "8F6F00"),
        built("coral-reef", "Korallenriff", dark: false, "FAEFE9", "3A261F", "C25C3A"),
    ]

    static let builtInDark: [AppTheme] = [
        built("abyssal-trench", "Tiefseegraben", dark: true, "0B1622", "D6E4F0", "2BD4B4"),
        built("basalt-shore", "Basaltküste", dark: true, "1A1D1E", "D5D9D6", "8FBF8F"),
        built("cathode-amber", "Kathodenbernstein", dark: true, "14100A", "F2D9A6", "FFB000"),
        built("midnight-plum", "Mitternachtspflaume", dark: true, "17121F", "E6DDF3", "C78BFF"),
        built("fir-night", "Tannennacht", dark: true, "0D1A13", "D6E8DC", "4FC98A"),
        built("cobalt-night", "Kobaltnacht", dark: true, "111529", "DCE1F5", "6B7CFF"),
        built("evening-ember", "Abendglut", dark: true, "1A1210", "F0DAD2", "E0734F"),
        built("blackberry", "Brombeere", dark: true, "1E1119", "F0D9E6", "D96BA0"),
    ]

    /// The default of an appearance.
    static func standard(dark: Bool) -> AppTheme { dark ? orangeflixDark : orangeflixLight }

    /// The built-in themes of an appearance, without the default.
    static func builtIn(dark: Bool) -> [AppTheme] { dark ? builtInDark : builtInLight }

    /// The theme with `id` among the built-in and the imported ones; the
    /// default of the appearance when it is gone.
    static func resolve(id: String, dark: Bool, imported: [AppTheme]) -> AppTheme {
        let all = [standard(dark: dark)] + builtIn(dark: dark) + imported.filter { $0.isDark == dark }
        return all.first { $0.id == id } ?? standard(dark: dark)
    }
}

// MARK: - Import

/// Reads the color files of terminals: Ghostty (`key = value` lines) and
/// iTerm (`.itermcolors`, a property list).
enum ThemeImporter {
    enum Failure: LocalizedError {
        case unreadable
        case missingColors

        var errorDescription: String? {
            switch self {
            case .unreadable: "Die Datei ist weder eine Ghostty- noch eine iTerm-Themedatei."
            case .missingColors: "Der Datei fehlen Hintergrund- und Textfarbe."
            }
        }
    }

    /// The theme in `data`; `name` is the name of the file without its extension.
    static func theme(from data: Data, name: String) throws -> AppTheme {
        let colors: Colors
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            colors = itermColors(plist)
        } else if let text = String(data: data, encoding: .utf8) {
            colors = ghosttyColors(text)
        } else {
            throw Failure.unreadable
        }
        guard let background = colors.background, let foreground = colors.foreground else {
            throw Failure.missingColors
        }
        let isDark = background.luminance < 0.4
        let accent = colors.accent ?? colors.palette[4] ?? foreground
        let palette = (0..<7).compactMap { index -> ThemeRGB? in
            index == 0 ? (colors.palette[0] ?? background.mixed(with: foreground, 0.4)) : colors.palette[index]
        }
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return AppTheme(id: "import-\(slug)-\(isDark ? "d" : "l")", name: name, isDark: isDark,
                        background: background, foreground: foreground, accent: accent,
                        palette: palette.count == 7 ? palette : nil)
    }

    private struct Colors {
        var background: ThemeRGB?
        var foreground: ThemeRGB?
        var accent: ThemeRGB?
        var palette: [Int: ThemeRGB] = [:]
    }

    private static func ghosttyColors(_ text: String) -> Colors {
        var colors = Colors()
        var selection: ThemeRGB?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "background": colors.background = ThemeRGB(hex: value)
            case "foreground": colors.foreground = ThemeRGB(hex: value)
            case "cursor-color": colors.accent = ThemeRGB(hex: value)
            case "selection-background": selection = ThemeRGB(hex: value)
            case "palette":
                let parts = value.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let index = Int(parts[0]), let color = ThemeRGB(hex: parts[1]) {
                    colors.palette[index] = color
                }
            default: break
            }
        }
        if colors.accent == nil { colors.accent = colors.palette[4] ?? selection }
        return colors
    }

    private static func itermColors(_ plist: [String: Any]) -> Colors {
        func color(_ key: String) -> ThemeRGB? {
            guard let entry = plist[key] as? [String: Any],
                  let red = entry["Red Component"] as? Double,
                  let green = entry["Green Component"] as? Double,
                  let blue = entry["Blue Component"] as? Double else { return nil }
            return ThemeRGB(red: red, green: green, blue: blue)
        }
        var colors = Colors()
        colors.background = color("Background Color")
        colors.foreground = color("Foreground Color")
        colors.accent = color("Cursor Color")
        for index in 0..<16 { colors.palette[index] = color("Ansi \(index) Color") }
        return colors
    }
}

// MARK: - Runtime

/// The themes that are active right now. `Palette` reads them whenever a
/// color is drawn, from any thread.
final class ThemeRuntime: @unchecked Sendable {
    static let shared = ThemeRuntime()

    private let lock = NSLock()
    private var light = AppTheme.orangeflixLight
    private var dark = AppTheme.orangeflixDark
    private var lightExtended = true
    private var darkExtended = true
    /// Whether the accent comes from the theme; off uses the accent of the
    /// Mac for the accents of the app.
    private var tintWithTheme = true
    /// The accent of the Mac, as an sRGB color.
    private var neutralAccent = ThemeRGB(hex: "C27400") ?? .black

    /// Takes the themes the settings name.
    func apply(_ settings: AppSettings) {
        let light = AppTheme.resolve(id: settings.lightThemeID, dark: false, imported: settings.importedThemes)
        let dark = AppTheme.resolve(id: settings.darkThemeID, dark: true, imported: settings.importedThemes)
        let neutral = ThemeRGB(NSColor.controlAccentColor) ?? ThemeRGB(hex: light.colors.accent) ?? .black
        lock.lock()
        defer { lock.unlock() }
        self.light = light
        self.dark = dark
        lightExtended = settings.lightExtendedPalette
        darkExtended = settings.darkExtendedPalette
        tintWithTheme = settings.tintWithTheme
        neutralAccent = neutral
    }

    /// The hex color of `token` in the appearance. Without the extended
    /// palette only the accent comes from the theme.
    func hex(_ token: ThemeToken, dark isDark: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        let theme = isDark ? dark : light
        let extended = isDark ? darkExtended : lightExtended
        if token.isAccent, !tintWithTheme {
            return untinted(token, theme: theme, dark: isDark).hex
        }
        if token.isAccent || extended { return theme.colors.hex(token) }
        return AppTheme.standard(dark: isDark).colors.hex(token)
    }

    /// The accent colors when the accent of the Mac is in charge: the
    /// background of the theme decides the quiet shade, so the accent stays
    /// readable in either appearance.
    private func untinted(_ token: ThemeToken, theme: AppTheme, dark: Bool) -> ThemeRGB {
        switch token {
        case .accent:
            neutralAccent
        case .accentSoft:
            (ThemeRGB(hex: theme.colors.background) ?? .black)
                .mixed(with: neutralAccent, dark ? 0.16 : 0.14)
        case .accentText:
            dark ? neutralAccent.mixed(with: .white, 0.12) : neutralAccent.mixed(with: .black, 0.28)
        default:
            neutralAccent
        }
    }
}

extension Color {
    /// A color of the active theme; it follows the appearance of the window.
    init(token: ThemeToken) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: ThemeRuntime.shared.hex(token, dark: isDark))
        })
    }
}

extension AppSettings {
    /// Changes whenever a setting that alters the colors changes, so a view
    /// can start over with `.id`.
    var themeSignature: String {
        var hasher = Hasher()
        hasher.combine(importedThemes)
        return "\(lightThemeID)|\(darkThemeID)|\(lightExtendedPalette)|\(darkExtendedPalette)|\(tintWithTheme)|\(interfaceStyle.rawValue)|\(glassPanels)|\(hasher.finalize())"
    }
}
