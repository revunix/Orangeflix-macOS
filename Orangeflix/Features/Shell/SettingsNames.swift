import AppKit
import SwiftUI

// MARK: - Names

extension AppSettings.InterfaceStyle {
    /// The German name of the style.
    var shellTitle: String {
        switch self {
        case .classic: "Klassisch"
        case .glass: "Glas"
        }
    }
}

extension AppSettings.AppIcon {
    /// The German name of the symbol.
    var shellTitle: String {
        switch self {
        case .standard: "Standard"
        case .bright: "Leuchtend"
        case .twilight: "Dämmerung"
        }
    }
}

extension AppSettings.Quality {
    /// The German name of the quality.
    var shellTitle: String {
        switch self {
        case .best: "Beste"
        case .hd: "HD"
        case .sd: "SD"
        case .mobile: "Mobil"
        case .audio: "Audio"
        }
    }
}

extension AppSettings.Layout {
    /// The German name of the layout.
    var shellTitle: String {
        switch self {
        case .compat: "Kompatibel"
        case .flat: "Flach"
        }
    }
}
