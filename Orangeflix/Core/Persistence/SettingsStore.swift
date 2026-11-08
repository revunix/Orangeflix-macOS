import Foundation
import os

/// Persists `AppSettings` as JSON in UserDefaults.
final class SettingsStore: Sendable {
    /// The UserDefaults key of the settings.
    static let key = "orangeflix.settings.v1"

    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "persistence")

    /// UserDefaults is documented thread-safe but not Sendable, so only the
    /// suite name is stored and the instance is looked up per call.
    private let suiteName: String?
    private var defaults: UserDefaults { suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard }

    /// `suiteName` nil uses the standard defaults of the app.
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// The stored settings; defaults when nothing (or garbage) is stored.
    /// Invalid single fields fall back to their defaults.
    func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Self.logger.error("Gespeicherte Einstellungen unlesbar: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    /// Validates and stores the settings; invalid settings are not stored.
    func save(_ settings: AppSettings) throws {
        try settings.validate()
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }

    /// Removes the stored settings (back to the defaults).
    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
