import Foundation
import os

/// Security-scoped access to a folder; balance with `stop()` (also called on
/// deinit). Calling `stop()` more than once is harmless.
final class ScopedFolderAccess: Sendable {
    /// The resolved folder.
    let url: URL
    private let state: OSAllocatedUnfairLock<Bool>

    fileprivate init(url: URL, started: Bool) {
        self.url = url
        state = OSAllocatedUnfairLock(initialState: started)
    }

    /// Ends the security-scoped access.
    func stop() {
        let wasStarted = state.withLock { started in
            defer { started = false }
            return started
        }
        if wasStarted { url.stopAccessingSecurityScopedResource() }
    }

    deinit { stop() }
}

/// Remembers the download folder the user picked as a security-scoped
/// bookmark in UserDefaults (the sandboxed replacement of Go's
/// `downloads_dir` setting). Requires the entitlement
/// `com.apple.security.files.bookmarks.app-scope`.
final class FolderBookmarkStore: Sendable {
    /// The UserDefaults key of the bookmark data.
    static let key = "orangeflix.downloadFolderBookmark.v1"

    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "persistence")

    /// UserDefaults is documented thread-safe but not Sendable, so only the
    /// suite name is stored and the instance is looked up per call.
    private let suiteName: String?
    private var defaults: UserDefaults { suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard }
    private let key: String

    init(suiteName: String? = nil, key: String = FolderBookmarkStore.key) {
        self.suiteName = suiteName
        self.key = key
    }

    /// ~/Downloads/Orangeflix, usable with the Downloads read-write
    /// entitlement without a bookmark (the Go default was "<workdir>/downloads").
    static func defaultFolder() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("Orangeflix", isDirectory: true)
    }

    /// Whether a bookmark is stored.
    var hasBookmark: Bool { defaults.data(forKey: key) != nil }

    /// Stores a bookmark of `url` (e.g. from NSOpenPanel, while the app holds
    /// the implicit access granted by the panel).
    func save(_ url: URL) throws {
        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw PersistenceError.bookmark(error.localizedDescription)
        }
        defaults.set(data, forKey: key)
    }

    /// Forgets the folder.
    func clear() { defaults.removeObject(forKey: key) }

    /// Resolves the stored bookmark and starts security-scoped access. A
    /// stale bookmark is re-created and stored. nil when no bookmark is stored.
    func access() throws -> ScopedFolderAccess? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            throw PersistenceError.bookmark(error.localizedDescription)
        }
        let started = url.startAccessingSecurityScopedResource()
        let access = ScopedFolderAccess(url: url, started: started)
        if stale {
            do {
                try save(url)
                Self.logger.info("Lesezeichen des Download-Ordners erneuert")
            } catch {
                Self.logger.error("Lesezeichen konnte nicht erneuert werden: \(error.localizedDescription, privacy: .public)")
            }
        }
        return access
    }

    /// Creates the folder and checks that a file can be written into it
    /// (Go `config.EnsureWritableDir`). The caller must hold access.
    static func ensureWritable(_ url: URL) throws {
        let path = url.path
        guard !path.isEmpty else { throw PersistenceError.notWritable(path: path, reason: "kein Ordner angegeben") }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw PersistenceError.notDirectory(path) }
        } else {
            do {
                try manager.createDirectory(at: url, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755])
            } catch {
                throw PersistenceError.notWritable(path: path, reason: error.localizedDescription)
            }
        }
        let probe = url.appendingPathComponent(".orangeflix-dl-write-test")
        guard manager.createFile(atPath: probe.path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o600]) else {
            let reason = String(cString: strerror(errno))
            throw PersistenceError.notWritable(path: path, reason: reason)
        }
        try? manager.removeItem(at: probe)
    }
}
