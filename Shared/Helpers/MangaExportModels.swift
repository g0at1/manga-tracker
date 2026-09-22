import Foundation
import SwiftData

struct ExportedVolumePart: Codable {
    var index: Int
    var read: Bool
    var readDate: Date?
}

struct ExportedVolume: Codable {
    var number: Int
    var owned: Bool
    var purchaseDate: Date?
    var price: Double?
    var read: Bool?
    var readDate: Date?
    var releaseDate: Date?
    var buyURL: String?
    /// Left out for an unsplit volume, so snapshots from before parts
    /// existed and of ordinary volumes look the same.
    var parts: [ExportedVolumePart]?
}

struct ExportedManga: Codable {
    var title: String
    var note: String
    var summary: String?
    var createdAt: Date
    var coverURL: String?
    var sortOrder: Int?
    var rating: Double?
    var isSold: Bool?
    var bannerImage: String?
    var aniListId: Int?
    var aniListStatus: String?
    var aniListAverageScore: Int?
    var aniListStartDate: Date?
    var aniListEndDate: Date?
    var aniListGenresRaw: String?
    var aniListAuthor: String?
    var aniListParentId: Int?
    var isSpinOff: Bool?
    var isPlanned: Bool?
    var isFavorite: Bool?

    var volumes: [ExportedVolume]
}

// MARK: - Model ↔ snapshot

extension ExportedVolumePart {
    init(_ part: VolumePart) {
        self.init(index: part.index, read: part.read, readDate: part.readDate)
    }
}

extension ExportedVolume {
    init(_ volume: Volume) {
        self.init(
            number: volume.number,
            owned: volume.owned,
            purchaseDate: volume.purchaseDate,
            price: volume.price,
            read: volume.read,
            readDate: volume.readDate,
            releaseDate: volume.releaseDate,
            buyURL: volume.buyURL,
            parts: volume.isSplit ? volume.sortedParts.map { ExportedVolumePart($0) } : nil
        )
    }
}

extension ExportedManga {
    /// Snapshot of a series and its volumes, used by the JSON backup and
    /// as the sync payload. Volumes come out sorted so equal libraries
    /// produce equal snapshots.
    init(_ manga: Manga) {
        self.init(
            title: manga.title,
            note: manga.note,
            summary: manga.summary,
            createdAt: manga.createdAt,
            coverURL: manga.coverURL,
            sortOrder: manga.sortOrder,
            rating: manga.rating,
            isSold: manga.isSold,
            bannerImage: manga.bannerImage,
            aniListId: manga.aniListId,
            aniListStatus: manga.aniListStatus,
            aniListAverageScore: manga.aniListAverageScore,
            aniListStartDate: manga.aniListStartDate,
            aniListEndDate: manga.aniListEndDate,
            aniListGenresRaw: manga.aniListGenresRaw,
            aniListAuthor: manga.aniListAuthor,
            aniListParentId: manga.aniListParentId,
            isSpinOff: manga.isSpinOff,
            isPlanned: manga.isPlanned,
            isFavorite: manga.isFavorite,
            volumes: manga.volumes
                .sorted { $0.number < $1.number }
                .map { ExportedVolume($0) }
        )
    }
}

extension VolumePart {
    convenience init(exported: ExportedVolumePart, volume: Volume? = nil) {
        self.init(index: exported.index, read: exported.read, readDate: exported.readDate, volume: volume)
    }

    @discardableResult
    func apply(_ exported: ExportedVolumePart) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<VolumePart, T>, _ value: T) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            changed = true
        }
        set(\.index, exported.index)
        set(\.read, exported.read)
        set(\.readDate, exported.readDate)
        return changed
    }
}

extension Volume {
    convenience init(exported: ExportedVolume, manga: Manga? = nil) {
        self.init(
            number: exported.number,
            owned: exported.owned,
            purchaseDate: exported.purchaseDate,
            price: exported.price,
            read: exported.read,
            manga: manga,
            readDate: exported.readDate,
            releaseDate: exported.releaseDate,
            buyURL: exported.buyURL
        )
        parts = (exported.parts ?? []).map { VolumePart(exported: $0, volume: self) }
    }

    /// Copies every field from the snapshot, touching only the ones that
    /// differ so an identical snapshot doesn't dirty the context. Parts are
    /// matched by index — updated, added, or deleted when missing.
    /// Returns whether anything changed.
    @discardableResult
    func apply(_ exported: ExportedVolume) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Volume, T>, _ value: T) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            changed = true
        }
        set(\.number, exported.number)
        set(\.owned, exported.owned)
        set(\.purchaseDate, exported.purchaseDate)
        set(\.price, exported.price)
        set(\.read, exported.read)
        set(\.readDate, exported.readDate)
        set(\.releaseDate, exported.releaseDate)
        set(\.buyURL, exported.buyURL)

        var existing: [Int: VolumePart] = [:]
        for part in parts {
            existing[part.index] = part
        }
        var seen = Set<Int>()
        for snapshot in exported.parts ?? [] {
            seen.insert(snapshot.index)
            if let part = existing[snapshot.index] {
                if part.apply(snapshot) {
                    changed = true
                }
            } else {
                parts.append(VolumePart(exported: snapshot, volume: self))
                changed = true
            }
        }
        let stale = parts.filter { !seen.contains($0.index) }
        if !stale.isEmpty {
            let staleIDs = Set(stale.map(\.persistentModelID))
            parts.removeAll { staleIDs.contains($0.persistentModelID) }
            for part in stale {
                part.modelContext?.delete(part)
            }
            changed = true
        }
        return changed
    }
}

extension Manga {
    /// A new series built from a snapshot, volumes included. The caller
    /// still has to insert it into a context.
    convenience init(exported: ExportedManga, syncID: String? = UUID().uuidString) {
        self.init(
            title: exported.title,
            note: exported.note,
            summary: exported.summary,
            createdAt: exported.createdAt,
            volumes: [],
            coverUrl: exported.coverURL,
            sortOrder: exported.sortOrder,
            rating: exported.rating,
            isSold: exported.isSold,
            aniListId: exported.aniListId,
            aniListStatus: exported.aniListStatus,
            aniListAverageScore: exported.aniListAverageScore,
            aniListStartDate: exported.aniListStartDate,
            aniListEndDate: exported.aniListEndDate,
            aniListGenresRaw: exported.aniListGenresRaw,
            aniListAuthor: exported.aniListAuthor,
            bannerImage: exported.bannerImage,
            aniListParentId: exported.aniListParentId,
            isSpinOff: exported.isSpinOff,
            isPlanned: exported.isPlanned,
            isFavorite: exported.isFavorite,
            syncID: syncID
        )
        volumes = exported.volumes.map { Volume(exported: $0, manga: self) }
    }

    /// Makes this series match the snapshot: fields are overwritten, volumes
    /// are matched by number — updated, added, or deleted when missing from
    /// the snapshot. Only differing values are written, so applying the
    /// snapshot a second time is a no-op. Returns whether anything changed.
    @discardableResult
    func apply(_ exported: ExportedManga) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Manga, T>, _ value: T) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            changed = true
        }
        set(\.title, exported.title)
        set(\.note, exported.note)
        set(\.summary, exported.summary)
        set(\.createdAt, exported.createdAt)
        set(\.coverURL, exported.coverURL)
        set(\.sortOrder, exported.sortOrder)
        set(\.rating, exported.rating)
        set(\.isSold, exported.isSold)
        set(\.bannerImage, exported.bannerImage)
        set(\.aniListId, exported.aniListId)
        set(\.aniListStatus, exported.aniListStatus)
        set(\.aniListAverageScore, exported.aniListAverageScore)
        set(\.aniListStartDate, exported.aniListStartDate)
        set(\.aniListEndDate, exported.aniListEndDate)
        set(\.aniListGenresRaw, exported.aniListGenresRaw)
        set(\.aniListAuthor, exported.aniListAuthor)
        set(\.aniListParentId, exported.aniListParentId)
        set(\.isSpinOff, exported.isSpinOff)
        set(\.isPlanned, exported.isPlanned)
        set(\.isFavorite, exported.isFavorite)

        // Volumes: keyed by number, which the UI keeps unique within a series.
        var existing: [Int: Volume] = [:]
        for volume in volumes {
            existing[volume.number] = volume
        }
        var seen = Set<Int>()
        for snapshot in exported.volumes {
            seen.insert(snapshot.number)
            if let volume = existing[snapshot.number] {
                if volume.apply(snapshot) {
                    changed = true
                }
            } else {
                volumes.append(Volume(exported: snapshot, manga: self))
                changed = true
            }
        }
        let stale = volumes.filter { !seen.contains($0.number) }
        if !stale.isEmpty {
            let staleIDs = Set(stale.map(\.persistentModelID))
            volumes.removeAll { staleIDs.contains($0.persistentModelID) }
            for volume in stale {
                volume.modelContext?.delete(volume)
            }
            changed = true
        }
        return changed
    }
}

// MARK: - JSON backup

func encodeMangasToJSON(_ mangas: [Manga]) throws -> Data {
    let exported = mangas.map { ExportedManga($0) }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(exported)
}

func decodeMangasFromJSON(_ data: Data) throws -> [ExportedManga] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([ExportedManga].self, from: data)
}
