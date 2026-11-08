import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import os

/// Pictures from the network, kept in memory and on disk, so a start and a
/// scroll back do not fetch them again.
///
/// The disk copies live in `Caches/Orangeflix/images`; they are pure caches,
/// so macOS may delete them at any time.
actor ImageCache {
    static let shared = ImageCache()

    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "images")

    /// The memory layer; `totalCostLimit` is the budget for the whole app.
    private static let memoryLimit = 96 * 1024 * 1024
    /// The disk layer; older files go when the folder grows past this.
    private static let diskLimit = 256 * 1024 * 1024

    private let memory: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = memoryLimit
        return cache
    }()

    private let session: URLSession
    private let folder: URL?
    /// Files that are being fetched; a second reader waits instead of
    /// downloading the same picture again.
    private var running: [URL: Task<NSImage?, Never>] = [:]
    /// The hero carousel reuses its image-derived colors on every turn.
    private var imageColors: [URL: ThemeRGB] = [:]

    init(session: URLSession = .shared, folder: URL? = nil) {
        self.session = session
        if let folder {
            self.folder = folder
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            self.folder = base?.appendingPathComponent("Orangeflix", isDirectory: true)
                .appendingPathComponent("images", isDirectory: true)
        }
    }

    /// The picture of `url`: from memory, else from disk, else from the
    /// network. nil when it cannot be loaded; nothing is stored then.
    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let fetched = running[url] { return await fetched.value }
        let task = Task<NSImage?, Never> { [weak self] in
            await self?.load(url)
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        return image
    }

    /// Drops the memory layer; the files stay for the next start.
    func clear() {
        memory.removeAllObjects()
        imageColors.removeAll()
    }

    /// A small, color-weighted sample of the already cached image. Sampling
    /// stays on this actor, not in the view's layout or on the main actor.
    func representativeColor(for url: URL) async -> ThemeRGB? {
        if let color = imageColors[url] { return color }
        guard let image = await image(for: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                              CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.05 else { continue }
            let r = min(1, Double(pixels[index]) / 255 / alpha)
            let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
            let saturation = max(r, g, b) - min(r, g, b)
            // Prefer the picture's color over white lettering or black bars,
            // but still produce a neutral shade for monochrome artwork.
            let weight = alpha * (0.15 + saturation * 0.85)
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 0 else { return nil }
        let color = ThemeRGB(red: red / total, green: green / total, blue: blue / total)
        if imageColors.count >= 64 { imageColors.removeAll() }
        imageColors[url] = color
        return color
    }

    // MARK: Loading

    private func load(_ url: URL) async -> NSImage? {
        if let image = readFromDisk(url) {
            remember(image, for: url)
            return image
        }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                Self.logger.debug("Bild nicht geladen (HTTP \(http.statusCode)): \(url.absoluteString, privacy: .public)")
                return nil
            }
            guard let image = NSImage(data: data) else {
                Self.logger.debug("Bild nicht lesbar: \(url.absoluteString, privacy: .public)")
                return nil
            }
            remember(image, for: url)
            writeToDisk(data, for: url)
            return image
        } catch {
            Self.logger.debug("Bild nicht geladen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func remember(_ image: NSImage, for url: URL) {
        let pixels = Int(image.size.width * image.size.height * 4)
        memory.setObject(image, forKey: url as NSURL, cost: max(pixels, 1))
    }

    // MARK: Disk

    /// The file of a picture: the SHA-256 of its address.
    private func file(for url: URL) -> URL? {
        guard let folder else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".img"
        return folder.appendingPathComponent(name, isDirectory: false)
    }

    private func readFromDisk(_ url: URL) -> NSImage? {
        guard let file = file(for: url) else { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return NSImage(data: data)
    }

    private func writeToDisk(_ data: Data, for url: URL) {
        guard let folder, let file = file(for: url) else { return }
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            prune()
        } catch {
            Self.logger.debug("Bild nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes the oldest files while the folder is above `diskLimit`.
    private func prune() {
        guard let folder else { return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else { return }
        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            let size = values.fileSize ?? 0
            total += size
            entries.append((file, size, values.contentModificationDate ?? .distantPast))
        }
        guard total > Self.diskLimit else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > Self.diskLimit else { break }
            guard (try? FileManager.default.removeItem(at: entry.url)) != nil else { continue }
            total -= entry.size
        }
    }
}
