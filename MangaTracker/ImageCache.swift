import CryptoKit
import Foundation

final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSData>()
    private let fm = FileManager.default
    private let folderURL: URL

    private init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folderURL = base.appendingPathComponent(
            "MangaCovers",
            isDirectory: true
        )
        try? fm.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        memory.countLimit = 300
    }

    func data(for url: URL) -> Data? {
        let key = url.absoluteString as NSString
        if let d = memory.object(forKey: key) {
            return Data(referencing: d)
        }
        let file = fileURL(for: url)
        if let d = try? Data(contentsOf: file) {
            memory.setObject(d as NSData, forKey: key)
            return d
        }
        return nil
    }

    func store(_ data: Data, for url: URL) {
        let key = url.absoluteString as NSString
        memory.setObject(data as NSData, forKey: key)

        let file = fileURL(for: url)
        try? data.write(to: file, options: [.atomic])
    }

    func clearAll() {
        memory.removeAllObjects()
        try? fm.removeItem(at: folderURL)
        try? fm.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = hash.map { String(format: "%02x", $0) }.joined()
        return folderURL.appendingPathComponent(name).appendingPathExtension(
            "img"
        )
    }
}
