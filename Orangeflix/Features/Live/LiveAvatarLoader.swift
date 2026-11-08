import Foundation

/// Loads the pictures of the chat users (Go `App.ChatAvatar`). Only small
/// pictures are taken and they are kept for the session; a name without a
/// picture keeps the coloured dot.
actor LiveAvatarLoader {
    /// The address of the pictures; the name follows it. The web chat uses
    /// the same address.
    static let baseURL = "https://orangeflix.de/api/live/chat-avatar/"

    /// The largest picture that is read; the server sends 50 by 50 pixels.
    static let byteLimit = 256 << 10

    /// The time the server may take; a slow server must not hold the chat.
    static let timeout: TimeInterval = 10

    private var cache: [String: Data] = [:]
    private var failed: Set<String> = []

    /// The picture of a chat user; nil when there is none.
    func data(for name: String) async -> Data? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if failed.contains(key) { return nil }
        guard let url = Self.url(for: key) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(APIDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                failed.insert(key)
                return nil
            }
            if let kind = http.value(forHTTPHeaderField: "Content-Type"),
               !kind.lowercased().hasPrefix("image/") {
                failed.insert(key)
                return nil
            }
            guard data.count <= Self.byteLimit else {
                failed.insert(key)
                return nil
            }
            cache[key] = data
            return data
        } catch {
            failed.insert(key)
            return nil
        }
    }

    /// The address of the picture of a name; the name is escaped like Go's
    /// `url.PathEscape` does.
    static func url(for name: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let escaped = name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: baseURL + escaped)
    }
}

/// The colour of a sender without a picture (Go `fallbackAvatar`): the
/// name picks a colour of the palette of the messenger.
enum LiveAvatarStyle {
    /// The colours of the senders.
    static let palette = ["#7dd3fc", "#86efac", "#fca5a5", "#c4b5fd",
                          "#fcd34d", "#f9a8d4", "#5eead4", "#fdba74"]

    /// The colour of a name: the hash of the name picks one of the palette.
    static func colorHex(for name: String) -> String {
        palette[Int(Self.hash(name) % UInt32(palette.count))]
    }

    /// The hash of the name (FNV-1a, like the Go app).
    static func hash(_ name: String) -> UInt32 {
        var value: UInt32 = 2166136261
        for byte in name.utf8 {
            value ^= UInt32(byte)
            value = value &* 16777619
        }
        return value
    }
}
