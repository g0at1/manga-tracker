import CryptoKit
import Foundation
import ImageIO

/// Decoded covers and banners, keyed by URL.
///
/// Memory holds ready-to-draw `CGImage`s so a card that scrolls back into
/// view doesn't decode its JPEG again; the Caches folder keeps the original
/// bytes so a relaunch doesn't hit the network. Disk reads, decoding and
/// downloads all run off the main thread, and concurrent requests for the
/// same URL share one download.
actor ImageCache {
    static let shared = ImageCache()

    /// Longest edge, in pixels, a cover is decoded to. The largest a cover is
    /// drawn is 188pt wide on the detail page — 376px on a Retina display —
    /// and a 2:3 cover capped at 600px tall is ~400px wide, so nothing is
    /// upscaled. Core Animation keeps its own copy of every drawn bitmap,
    /// so decoding larger than this costs memory twice.
    static let coverMaxPixelSize = 600
    /// Banners span the whole window, so they keep more detail.
    static let bannerMaxPixelSize = 2400

    // NSCache is thread-safe; it's read synchronously from the main thread
    // so an already-decoded image can be drawn on the first frame.
    private nonisolated(unsafe) let memory = NSCache<NSString, CGImage>()
    private let folderURL: URL
    private var inFlight: [NSString: Task<CGImage?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folderURL = base.appendingPathComponent("MangaCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        memory.countLimit = 400
        memory.totalCostLimit = 150 * 1024 * 1024
    }

    /// Memory-only lookup; never touches disk or the network.
    nonisolated func cachedImage(for url: URL, maxPixelSize: Int = coverMaxPixelSize) -> CGImage? {
        memory.object(forKey: Self.key(url, maxPixelSize: maxPixelSize))
    }

    /// Memory, then disk, then network. Returns `nil` when the image can't
    /// be fetched or decoded.
    func image(for url: URL, maxPixelSize: Int = coverMaxPixelSize) async -> CGImage? {
        let key = Self.key(url, maxPixelSize: maxPixelSize)
        if let image = memory.object(forKey: key) {
            return image
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let file = fileURL(for: url)
        let task = Task.detached(priority: .userInitiated) {
            await Self.load(url: url, file: file, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            memory.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    func clearAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folderURL)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    // MARK: - Loading

    private static func load(url: URL, file: URL, maxPixelSize: Int) async -> CGImage? {
        if let data = try? Data(contentsOf: file),
           let image = decode(data, maxPixelSize: maxPixelSize)
        {
            return image
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true,
              let image = decode(data, maxPixelSize: maxPixelSize)
        else { return nil }

        // Only keep bytes that decoded, so an error page never poisons the cache.
        try? data.write(to: file, options: .atomic)
        return image
    }

    /// Decodes straight to a bitmap no larger than `maxPixelSize`, so the
    /// image is cheap to draw and doesn't hold the full-size pixels.
    private static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Keys

    private static func key(_ url: URL, maxPixelSize: Int) -> NSString {
        "\(url.absoluteString)#\(maxPixelSize)" as NSString
    }

    private nonisolated func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return folderURL.appendingPathComponent(name).appendingPathExtension("img")
    }
}
