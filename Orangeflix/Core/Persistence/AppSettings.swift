import CoreGraphics
import Foundation

/// The persistent preferences of the app: the GUI-relevant part of the Go
/// options/settings file. Validation matches the Go command line and
/// `Resolve` checks.
struct AppSettings: Codable, Sendable, Hashable {
    /// Download quality names (Go `config.ValidateQuality`).
    enum Quality: String, Codable, Sendable, Hashable, CaseIterable {
        case best, hd, sd, mobile, audio

        /// Accepts the names case-insensitively with surrounding white space;
        /// "" means `best`. Throws for anything else.
        init(validating name: String) throws {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty {
                self = .best
                return
            }
            guard let quality = Quality(rawValue: key) else {
                throw PersistenceError.invalidSetting(
                    "Ungültige Qualität: \(name) (erlaubt: best, hd, sd, mobile, audio)")
            }
            self = quality
        }
    }

    /// Directory layouts of the downloads (Go `media.ParseLayout`).
    enum Layout: String, Codable, Sendable, Hashable, CaseIterable {
        /// The structure of the JavaScript downloader.
        case compat
        /// The episodes directly in the series folder.
        case flat

        /// Case-insensitive, trimmed; "" means `compat`.
        init(validating name: String) throws {
            switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "", "compat": self = .compat
            case "flat": self = .flat
            default:
                throw PersistenceError.invalidSetting("Unbekanntes Layout: \(name) (erlaubt: compat, flat)")
            }
        }
    }

    /// Color scheme; the values match the Go TUI's stored theme names.
    enum Theme: String, Codable, Sendable, Hashable, CaseIterable {
        /// Follows the system appearance.
        case auto, dark, light
    }

    /// How the app draws the chrome it owns itself.
    enum InterfaceStyle: String, Codable, Sendable, Hashable, CaseIterable {
        /// Solid surfaces and bordered buttons, without glass.
        case classic
        /// Liquid Glass on macOS 26, materials before.
        case glass
    }

    /// The symbol of the app in the Dock.
    enum AppIcon: String, Codable, Sendable, Hashable, CaseIterable {
        /// The iris on the warm neutral of the theme; follows the appearance.
        case standard
        /// The iris on a bright orange.
        case bright
        /// The iris on a deep blue.
        case twilight
    }

    /// Where the chat of the Live page stands while it shows.
    enum LiveChatPosition: String, Codable, Sendable, Hashable, CaseIterable {
        /// Wherever the picture grows larger, by the size of the window.
        case auto
        /// Always the column at the right edge.
        case side
        /// Always under the picture.
        case below
    }

    /// How a voting of the live show shows over the picture.
    enum LivePolls: String, Codable, Sendable, Hashable, CaseIterable {
        case expanded, collapsed, hidden
    }

    /// The size of the text of the live chat.
    enum LiveChatTextSize: String, Codable, Sendable, Hashable, CaseIterable {
        case small, normal, large, larger

        /// The factor on the sizes of the chat.
        var scale: CGFloat {
            switch self {
            case .small: 0.9
            case .normal: 1
            case .large: 1.15
            case .larger: 1.3
            }
        }
    }

    static let parallelRange = 1...8
    static let delayRange = 0.0...3600.0
    static let limitRange = 1...1_000_000

    var quality: Quality = .best
    /// The quality the player asks for; downloads keep `quality`.
    var streamQuality: Quality = .best
    var layout: Layout = .compat
    /// The RSS feed variant (> 0).
    var submodule: Int = 1
    /// Downloads that run at the same time, 1–8.
    var parallel: Int = 1
    /// Pause between two downloads in seconds, 0–3600.
    var delay: Double = 0
    /// Download speed cap in KiB/s; 0 means no cap, otherwise 1–1 000 000.
    var limitKiB: Int = 0
    /// Store the thumbnail next to the video.
    var thumb: Bool = false
    /// Store the metadata as JSON next to the video.
    var meta: Bool = false
    var theme: Theme = .auto
    /// How the chrome and the floating panels of the app are drawn.
    var interfaceStyle: InterfaceStyle = .glass
    /// Whether the accent comes from the theme; off keeps the orange of
    /// Orangeflix.
    var tintWithTheme = true
    /// Whether the app draws its own plates in glass; the style decides
    /// whether the choice shows at all.
    var glassPanels = true
    /// The symbol of the app in the Dock.
    var appIcon: AppIcon = .standard
    /// The theme of the light appearance (id of a built-in or imported theme).
    var lightThemeID = AppTheme.orangeflixLight.id
    /// The theme of the dark appearance.
    var darkThemeID = AppTheme.orangeflixDark.id
    /// Whether the light theme also colors surfaces and texts; off keeps
    /// only its accent.
    var lightExtendedPalette = true
    /// Whether the dark theme also colors surfaces and texts.
    var darkExtendedPalette = true
    /// The themes the user imported from Ghostty or iTerm files.
    var importedThemes: [AppTheme] = []
    /// Whether the subtitles of a file start on. The player remembers the
    /// last choice here, so the next file follows it.
    var subtitlesOn = true
    /// The magazines the user switched off in the catalog (their pids).
    var hiddenMagazines: [Int] = []
    /// The magazines that send a notification for a new episode.
    var notifiedMagazines: [Int] = []
    /// Whether new episodes are announced at all.
    var notificationsOn = false
    /// The newest episode time per magazine that was already announced, by
    /// pid. A later time is a new episode.
    var announcedEpisodes: [String: Double] = [:]
    /// Whether a starting livestream sends a notification.
    var liveNotificationsOn = false
    /// The show of the last livestream announced, so it pops up only once.
    var announcedLiveShow = ""
    /// Whether the app keeps running in the menu bar after its window
    /// closes, so the notifications keep coming.
    var runsInBackground = false
    /// The clips removed from Weiterschauen and when (the API cannot remove
    /// them); a later watch brings a clip back.
    var dismissedRecents: [String: Double] = [:]
    /// Whether the chat shows when the Live page opens.
    var liveChatOpen = false
    /// Where the chat stands while it shows.
    var liveChatPosition: LiveChatPosition = .auto
    /// How a voting shows over the picture.
    var livePolls: LivePolls = .expanded
    /// The size of the text of the live chat.
    var liveChatTextSize: LiveChatTextSize = .normal
    /// Whether the chat shows the pictures of the senders.
    var liveChatAvatars = true
    /// Whether the chat shows the time of the messages.
    var liveChatTimes = true

    init() {}

    /// The limit in bytes per second for the downloader (0 = no cap).
    var limitBytesPerSecond: Int64 { Int64(limitKiB) * 1024 }

    // MARK: Validation

    /// Throws the first invalid value.
    func validate() throws {
        try Self.validateParallel(parallel)
        try Self.validateDelay(delay)
        try Self.validateLimit(limitKiB)
        try Self.validateSubmodule(submodule)
    }

    static func validateParallel(_ value: Int) throws {
        guard parallelRange.contains(value) else {
            throw PersistenceError.invalidSetting("Parallele Downloads: erwartet wird eine Zahl von 1 bis 8.")
        }
    }

    static func validateDelay(_ value: Double) throws {
        guard value.isFinite, delayRange.contains(value) else {
            throw PersistenceError.invalidSetting("Pause: erwartet werden 0 bis 3600 Sekunden.")
        }
    }

    /// 0 (no cap) or 1–1 000 000 KiB/s.
    static func validateLimit(_ value: Int) throws {
        guard value == 0 || limitRange.contains(value) else {
            throw PersistenceError.invalidSetting(
                "Geschwindigkeitslimit: erwartet werden 1 bis 1000000 KiB pro Sekunde (0 = ohne Limit).")
        }
    }

    static func validateSubmodule(_ value: Int) throws {
        guard value > 0 else {
            throw PersistenceError.invalidSetting("Feed-Variante: erwartet wird eine Zahl größer als 0.")
        }
    }

    /// Parses an integer field like Go's `strconv.Atoi` (optional sign, no
    /// white space).
    static func parseInt(_ text: String) -> Int? { Int(text) }

    /// A pause as the settings file writes it: "2", "1.5" (dot, no ".0").
    static func formatDelay(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(value)
    }

    /// Parses a pause in seconds; a decimal comma is accepted ("1,5").
    static func parseDelay(_ text: String) throws -> Double {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            throw PersistenceError.invalidSetting("Pause: erwartet werden 0 bis 3600 Sekunden.")
        }
        try validateDelay(value)
        return value
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case quality, streamQuality, layout, submodule, parallel, delay, limitKiB, thumb, meta, theme, lightThemeID, darkThemeID, lightExtendedPalette, darkExtendedPalette, importedThemes, subtitlesOn, hiddenMagazines, notifiedMagazines, notificationsOn, announcedEpisodes, liveNotificationsOn, announcedLiveShow, runsInBackground, dismissedRecents, liveChatOpen, liveChatStart, liveChatPosition = "liveChatPlacement", livePolls, liveChatTextSize, liveChatAvatars, liveChatTimes, interfaceStyle, tintWithTheme, glassPanels, appIcon
    }

    /// Decodes leniently: a missing or invalid field keeps its default, so a
    /// damaged or older stored value never discards the other settings.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .quality), let quality = try? Quality(validating: value) {
            self.quality = quality
        }
        if let value = try? container.decode(String.self, forKey: .streamQuality), let quality = try? Quality(validating: value) {
            streamQuality = quality
        }
        if let value = try? container.decode(String.self, forKey: .layout), let layout = try? Layout(validating: value) {
            self.layout = layout
        }
        if let value = try? container.decode(Int.self, forKey: .submodule), value > 0 {
            submodule = value
        }
        if let value = try? container.decode(Int.self, forKey: .parallel), Self.parallelRange.contains(value) {
            parallel = value
        }
        if let value = try? container.decode(Double.self, forKey: .delay), (try? Self.validateDelay(value)) != nil {
            delay = value
        }
        if let value = try? container.decode(Int.self, forKey: .limitKiB), (try? Self.validateLimit(value)) != nil {
            limitKiB = value
        }
        if let value = try? container.decode(Bool.self, forKey: .thumb) { thumb = value }
        if let value = try? container.decode(Bool.self, forKey: .meta) { meta = value }
        if let value = try? container.decode(String.self, forKey: .theme), let theme = Theme(rawValue: value) {
            self.theme = theme
        }
        if let value = try? container.decode(String.self, forKey: .interfaceStyle),
           let style = InterfaceStyle(rawValue: value) {
            interfaceStyle = style
        }
        if let value = try? container.decode(Bool.self, forKey: .tintWithTheme) { tintWithTheme = value }
        if let value = try? container.decode(Bool.self, forKey: .glassPanels) { glassPanels = value }
        if let value = try? container.decode(String.self, forKey: .appIcon),
           let icon = AppIcon(rawValue: value) {
            appIcon = icon
        }
        if let value = try? container.decode(String.self, forKey: .lightThemeID) { lightThemeID = value }
        if let value = try? container.decode(String.self, forKey: .darkThemeID) { darkThemeID = value }
        if let value = try? container.decode(Bool.self, forKey: .lightExtendedPalette) { lightExtendedPalette = value }
        if let value = try? container.decode(Bool.self, forKey: .darkExtendedPalette) { darkExtendedPalette = value }
        if let value = try? container.decode([AppTheme].self, forKey: .importedThemes) { importedThemes = value }
        if let value = try? container.decode(Bool.self, forKey: .subtitlesOn) { subtitlesOn = value }
        if let value = try? container.decode([Int].self, forKey: .hiddenMagazines) { hiddenMagazines = value }
        if let value = try? container.decode([Int].self, forKey: .notifiedMagazines) { notifiedMagazines = value }
        if let value = try? container.decode(Bool.self, forKey: .notificationsOn) { notificationsOn = value }
        if let value = try? container.decode([String: Double].self, forKey: .announcedEpisodes) { announcedEpisodes = value }
        if let value = try? container.decode(Bool.self, forKey: .liveNotificationsOn) { liveNotificationsOn = value }
        if let value = try? container.decode(String.self, forKey: .announcedLiveShow) { announcedLiveShow = value }
        if let value = try? container.decode(Bool.self, forKey: .runsInBackground) { runsInBackground = value }
        if let value = try? container.decode([String: Double].self, forKey: .dismissedRecents) { dismissedRecents = value }
        // An older version stored one value: hidden, side or below. Only
        // whether the chat opens carries over; the position starts automatic.
        if let value = try? container.decode(String.self, forKey: .liveChatStart) {
            liveChatOpen = value != "hidden"
        }
        if let value = try? container.decode(Bool.self, forKey: .liveChatOpen) { liveChatOpen = value }
        if let value = try? container.decode(LiveChatPosition.self, forKey: .liveChatPosition) { liveChatPosition = value }
        if let value = try? container.decode(LivePolls.self, forKey: .livePolls) { livePolls = value }
        if let value = try? container.decode(LiveChatTextSize.self, forKey: .liveChatTextSize) { liveChatTextSize = value }
        if let value = try? container.decode(Bool.self, forKey: .liveChatAvatars) { liveChatAvatars = value }
        if let value = try? container.decode(Bool.self, forKey: .liveChatTimes) { liveChatTimes = value }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quality, forKey: .quality)
        try container.encode(streamQuality, forKey: .streamQuality)
        try container.encode(layout, forKey: .layout)
        try container.encode(submodule, forKey: .submodule)
        try container.encode(parallel, forKey: .parallel)
        try container.encode(delay, forKey: .delay)
        try container.encode(limitKiB, forKey: .limitKiB)
        try container.encode(thumb, forKey: .thumb)
        try container.encode(meta, forKey: .meta)
        try container.encode(theme, forKey: .theme)
        try container.encode(interfaceStyle, forKey: .interfaceStyle)
        try container.encode(tintWithTheme, forKey: .tintWithTheme)
        try container.encode(glassPanels, forKey: .glassPanels)
        try container.encode(appIcon, forKey: .appIcon)
        try container.encode(lightThemeID, forKey: .lightThemeID)
        try container.encode(darkThemeID, forKey: .darkThemeID)
        try container.encode(lightExtendedPalette, forKey: .lightExtendedPalette)
        try container.encode(darkExtendedPalette, forKey: .darkExtendedPalette)
        try container.encode(importedThemes, forKey: .importedThemes)
        try container.encode(subtitlesOn, forKey: .subtitlesOn)
        try container.encode(hiddenMagazines, forKey: .hiddenMagazines)
        try container.encode(notifiedMagazines, forKey: .notifiedMagazines)
        try container.encode(notificationsOn, forKey: .notificationsOn)
        try container.encode(announcedEpisodes, forKey: .announcedEpisodes)
        try container.encode(liveNotificationsOn, forKey: .liveNotificationsOn)
        try container.encode(announcedLiveShow, forKey: .announcedLiveShow)
        try container.encode(runsInBackground, forKey: .runsInBackground)
        try container.encode(dismissedRecents, forKey: .dismissedRecents)
        try container.encode(liveChatOpen, forKey: .liveChatOpen)
        try container.encode(liveChatPosition, forKey: .liveChatPosition)
        try container.encode(livePolls, forKey: .livePolls)
        try container.encode(liveChatTextSize, forKey: .liveChatTextSize)
        try container.encode(liveChatAvatars, forKey: .liveChatAvatars)
        try container.encode(liveChatTimes, forKey: .liveChatTimes)
    }

    // MARK: Import

    /// Applies the values of a CLI settings file with the range checks of Go
    /// `Resolve`: parallel only 1–8, limit only 1–1 000 000, submodule > 0;
    /// quality and layout only when valid; thumb/meta only switch on. The
    /// delay (which Go's Resolve never takes from the file) is applied when
    /// it is in 0–3600. Invalid values are skipped and named in `rejected`.
    func applying(_ file: ConfigFileValues) -> (settings: AppSettings, rejected: [String]) {
        var result = self
        var rejected: [String] = []
        if !file.quality.isEmpty {
            if let quality = try? Quality(validating: file.quality) { result.quality = quality } else { rejected.append("quality") }
        }
        if !file.layout.isEmpty {
            if let layout = try? Layout(validating: file.layout) { result.layout = layout } else { rejected.append("layout") }
        }
        if file.submodule != 0 {
            if file.submodule > 0 { result.submodule = file.submodule } else { rejected.append("submodule") }
        }
        if file.parallel != 0 {
            if Self.parallelRange.contains(file.parallel) { result.parallel = file.parallel } else { rejected.append("parallel") }
        }
        if file.limit != 0 {
            if Self.limitRange.contains(file.limit) { result.limitKiB = file.limit } else { rejected.append("limit") }
        }
        if file.delay != 0 {
            if (try? Self.validateDelay(file.delay)) != nil { result.delay = file.delay } else { rejected.append("delay") }
        }
        result.thumb = result.thumb || file.thumb
        result.meta = result.meta || file.meta
        return (result, rejected)
    }
}
