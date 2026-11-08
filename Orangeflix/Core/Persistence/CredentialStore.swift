import Foundation
import os
import Security

/// The keychain entry of the account password.
///
/// The password is the only secret that has to be recoverable in clear (the
/// legacy API and the download host ask for basic authentication), so it is
/// the only one that goes into the keychain. The tokens live in the file
/// `credentials.json`; they expire and can be renewed, a password cannot.
private enum AccountKeychain {
    /// The service name of the entry; one item per account.
    static let service = "com.revunix.orangeflix"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The stored password, or nil when there is none or the keychain refuses.
    static func password(for account: String) -> String? {
        guard !account.isEmpty else { return nil }
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes the password; false when the keychain refuses the item.
    @discardableResult
    static func setPassword(_ password: String, for account: String) -> Bool {
        guard !account.isEmpty else { return false }
        let data = Data(password.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query(account: account) as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = query(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Orangeflix"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Drops the password of the account.
    static func removePassword(for account: String) {
        guard !account.isEmpty else { return }
        SecItemDelete(query(account: account) as CFDictionary)
    }
}

/// Stores the account data of the app: the login address and the session
/// tokens.
///
/// The tokens live in `Application Support/Orangeflix/credentials.json` with
/// mode 0600. The password is **not** written there: it is the one secret that
/// stays valid until the user changes it, so it goes into the keychain of the
/// user. A file that is copied, backed up or read by another process never
/// carries it.
///
/// Older builds kept the password in the file. `load` moves such a password
/// into the keychain and rewrites the file without it, so an existing install
/// is cleaned up on the next start without asking the user for the password
/// again.
actor CredentialStore {
    /// The stored account data.
    struct Payload: Sendable, Equatable {
        var email = ""
        /// Filled by `load` from the keychain; never part of the file.
        var password = ""
        var accessToken = ""
        var refreshToken = ""
        var expiry: Date?

        var hasLogin: Bool { !email.isEmpty && !password.isEmpty }
        var hasSession: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }
    }

    /// The file with the tokens and the login address.
    let url: URL

    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "credentials")

    /// False after `clear` until the next `setLogin`: a renewal of the token
    /// that was still running must not bring back a session the user ended.
    private var acceptsSessions = true

    /// Creates the folder and remembers the file location.
    init(url: URL? = nil) throws {
        if let url {
            self.url = url
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = support.appendingPathComponent("Orangeflix", isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            self.url = folder.appendingPathComponent("credentials.json", isDirectory: false)
        }
    }

    /// Reads the stored data; a missing or broken file counts as empty. The
    /// password comes from the keychain, and a password an older build left in
    /// the file is moved there before it is returned.
    func load() -> Payload {
        guard let data = try? Data(contentsOf: url) else { return Payload() }
        var payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            Self.logger.error("Zugangsdaten nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return Payload()
        }
        if let legacy = Self.legacyPassword(in: data), !payload.email.isEmpty {
            // One-time move: the file is rewritten without the password, so a
            // copy of it no longer carries the secret.
            if AccountKeychain.setPassword(legacy, for: payload.email) {
                try? write(payload)
                Self.logger.notice("Passwort aus der Datei in den Schlüsselbund verschoben.")
            } else {
                Self.logger.error("Passwort konnte nicht in den Schlüsselbund geschrieben werden.")
            }
            payload.password = legacy
            return payload
        }
        payload.password = AccountKeychain.password(for: payload.email) ?? ""
        return payload
    }

    /// Reads the `password` field an older build wrote into the file.
    private static func legacyPassword(in data: Data) -> String? {
        struct Legacy: Decodable { let password: String? }
        guard let legacy = try? JSONDecoder().decode(Legacy.self, from: data),
              let password = legacy.password, !password.isEmpty else { return nil }
        return password
    }

    /// Writes the tokens atomically and keeps the file private. The password
    /// is not part of the file.
    private func write(_ payload: Payload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Stores mail and password; the session stays untouched. The password
    /// goes into the keychain of the user, the address into the file. When the
    /// keychain refuses the item, the password is kept in memory only and the
    /// user has to enter it again after a restart.
    func setLogin(email: String, password: String) throws {
        var payload = load()
        acceptsSessions = true
        // A different account must not inherit the password of the old one.
        if !payload.email.isEmpty, payload.email != email {
            AccountKeychain.removePassword(for: payload.email)
        }
        payload.email = email
        payload.password = password
        if !AccountKeychain.setPassword(password, for: email) {
            Self.logger.error("Passwort nicht im Schlüsselbund gespeichert; es gilt nur für diese Sitzung.")
        }
        try write(payload)
    }

    /// Stores the tokens of the running session.
    func storeSession(accessToken: String, refreshToken: String, expiry: Date?) throws {
        guard acceptsSessions else { return }
        var payload = load()
        if !accessToken.isEmpty { payload.accessToken = accessToken }
        if !refreshToken.isEmpty { payload.refreshToken = refreshToken }
        if let expiry { payload.expiry = expiry }
        try write(payload)
    }

    /// Removes the session, keeps the login.
    func clearSession() throws {
        var payload = load()
        payload.accessToken = ""
        payload.refreshToken = ""
        payload.expiry = nil
        try write(payload)
    }

    /// Removes everything; tokens that arrive afterwards are dropped until
    /// the next login.
    func clear() {
        acceptsSessions = false
        AccountKeychain.removePassword(for: load().email)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Coding

extension CredentialStore.Payload: Codable {
    /// Only these fields are written; `password` stays out of the file.
    private enum CodingKeys: String, CodingKey {
        case email, accessToken, refreshToken, expiry
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        expiry = try container.decodeIfPresent(Date.self, forKey: .expiry)
        password = ""
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(expiry, forKey: .expiry)
    }
}
