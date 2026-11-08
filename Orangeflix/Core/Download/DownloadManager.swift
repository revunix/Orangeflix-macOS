import Foundation

/// Decides what has to be downloaded and where the file ends up (port of
/// manager.go). An episode counts as downloaded when a non-empty regular
/// file matches one of its globs (any quality, both layouts); partial files
/// never count. With `force` the matching files and partial files are
/// removed instead.
///
/// `root` must be accessible: inside the App Sandbox the App layer starts
/// security-scoped access to a user-picked folder before using the manager.
struct DownloadManager: Sendable {
    /// The root of the downloads.
    var root: URL
    /// Remove existing files instead of skipping them.
    var force: Bool = false
    /// Receives the German log lines.
    var log: (@Sendable (String) -> Void)?

    init(root: URL, force: Bool = false, log: (@Sendable (String) -> Void)? = nil) {
        self.root = root
        self.force = force
        self.log = log
    }

    /// The absolute file of the episode.
    func target(_ naming: MediaNaming, extension fileExtension: String) -> URL {
        root.appending(path: naming.relativeFile(extension: fileExtension), directoryHint: .notDirectory)
    }

    /// The file of an already downloaded episode, nil when it has to be
    /// downloaded.
    func existing(_ naming: MediaNaming) -> URL? {
        for pattern in naming.globs {
            for match in glob(pattern) where !match.hasSuffix(Downloader.partSuffix) {
                if let size = regularFileSize(match), size > 0 {
                    return URL(fileURLWithPath: match)
                }
            }
        }
        return nil
    }

    /// Returns the existing file when the episode must be skipped and nil
    /// when it has to be downloaded. With `force` the existing files (any
    /// size) and the partial files of the episode are removed first.
    func prepare(_ naming: MediaNaming) -> URL? {
        guard force else { return existing(naming) }
        for pattern in naming.globs {
            for match in glob(pattern) where !match.hasSuffix(Downloader.partSuffix) {
                if regularFileSize(match) != nil {
                    remove(match)
                }
            }
        }
        // A forced download starts from the beginning.
        for pattern in partGlobs(naming) {
            for match in glob(pattern) {
                remove(match)
            }
        }
        return nil
    }

    /// Creates the directory of the target file.
    func ensureDirectory(_ naming: MediaNaming) throws(DownloadError) {
        let directory = target(naming, extension: ".mp4").deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .directoryNotWritable(directory.path(percentEncoded: false))
        }
    }

    // MARK: Helpers

    /// The patterns of the partial files of an episode, for both layouts.
    func partGlobs(_ naming: MediaNaming) -> [String] {
        var compat = naming
        compat.layout = .compat
        var flat = naming
        flat.layout = .flat
        return [
            compat.seriesPrefix + ".*/" + compat.episodePrefix + ".*/" + compat.episodePrefix + ".*" + Downloader.partSuffix,
            flat.seriesPrefix + "/" + flat.episodePrefix + ".*" + Downloader.partSuffix,
        ]
    }

    private func remove(_ path: String) {
        log?("Erneuter Download, entferne: \(path)")
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            log?("Die Datei konnte nicht entfernt werden: \(error.localizedDescription)")
        }
    }

    private func regularFileSize(_ path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The absolute paths that match a pattern relative to the root, in
    /// lexical order. The root itself is escaped, so glob characters in the
    /// folder name match literally (the sanitized names carry none).
    func glob(_ pattern: String) -> [String] {
        guard !pattern.isEmpty else { return [] }
        var base = root.path(percentEncoded: false)
        if !base.hasSuffix("/") { base += "/" }
        var escaped = ""
        for character in base {
            if "*?[]\\{}".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        var result = glob_t()
        defer { globfree(&result) }
        guard Darwin.glob(escaped + pattern, 0, nil, &result) == 0 else { return [] }
        var matches: [String] = []
        for index in 0..<Int(result.gl_pathc) {
            if let path = result.gl_pathv[index] {
                matches.append(String(cString: path))
            }
        }
        return matches
    }
}
