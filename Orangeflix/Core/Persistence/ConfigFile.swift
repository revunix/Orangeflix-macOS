import Foundation

/// The values of the CLI settings file (`~/.config/orangeflix-dl/config`),
/// port of Go `config.FileConfig`. Zero / "" means "not set".
struct ConfigFileValues: Sendable, Hashable {
    var quality = ""
    var layout = ""
    var submodule = 0
    var parallel = 0
    var delay = 0.0
    var limit = 0
    var thumb = false
    var meta = false
    var downloadsDir = ""
}

/// Parser of the CLI settings file, used to import a file the user picked.
enum ConfigFile {
    /// Parses the "key=value" text like Go `LoadConfigFile`: lines are
    /// trimmed, "#" comments and lines without "=" are skipped, keys are
    /// lower-cased, empty values ignored, the first value of every key wins,
    /// thumb/meta switch on with "1", "true", "yes", "ja", "an".
    ///
    /// Go lower-cases the key before matching, so its `ORANGEFLIX_…` aliases
    /// can never match; this port keeps that behaviour.
    static func parse(_ text: String) -> ConfigFileValues {
        var result = ConfigFileValues()
        // Split on scalars: as Characters, "\r\n" is one grapheme and would
        // not match "\n".
        for rawLine in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { continue }
            switch key {
            case "quality":
                if result.quality.isEmpty { result.quality = value }
            case "layout":
                if result.layout.isEmpty { result.layout = value }
            case "submodule":
                if result.submodule == 0, let parsed = Int(value) { result.submodule = parsed }
            case "parallel":
                if result.parallel == 0, let parsed = Int(value) { result.parallel = parsed }
            case "limit":
                if result.limit == 0, let parsed = Int(value) { result.limit = parsed }
            case "delay":
                if result.delay == 0, let parsed = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    result.delay = parsed
                }
            case "downloads_dir":
                if result.downloadsDir.isEmpty { result.downloadsDir = value }
            case "thumb":
                result.thumb = result.thumb || isTruthy(value)
            case "meta":
                result.meta = result.meta || isTruthy(value)
            default:
                continue
            }
        }
        return result
    }

    /// Reads and parses a file; a missing or unreadable file gives empty
    /// values (like Go). The caller must hold security-scoped access.
    static func load(from url: URL) -> ConfigFileValues {
        guard let data = try? Data(contentsOf: url) else { return ConfigFileValues() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// "1", "true", "yes", "ja" and "an" (case-insensitive, trimmed) are on.
    static func isTruthy(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "ja", "an": return true
        default: return false
        }
    }
}
