import Foundation
import SwiftData

@Model
final class Manga {
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
    /// The series on MangaDex, which is where per-volume covers come
    /// from. Resolved once from `aniListId` and kept so later refreshes
    /// skip the search.
    var mangaDexId: String?
    /// On the wishlist: shown under "Planowane" until unmarked.
    var isPlanned: Bool?
    /// Hearted by the user; what "Ulubione" shows.
    var isFavorite: Bool?
    /// Stable identity shared with the sync backend, so the same series can
    /// be matched across devices. Rows from before sync existed get one
    /// assigned on the first launch of the sync engine.
    var syncID: String?

    @Relationship(deleteRule: .cascade, inverse: \Volume.manga)
    var volumes: [Volume]

    init(
        title: String,
        note: String = "",
        summary: String? = "",
        createdAt: Date = .now,
        volumes: [Volume] = [],
        coverUrl: String? = "",
        sortOrder: Int? = 0,
        rating: Double? = 0,
        isSold: Bool? = false,
        aniListId: Int? = nil,
        aniListStatus: String? = nil,
        aniListAverageScore: Int? = nil,
        aniListStartDate: Date? = nil,
        aniListEndDate: Date? = nil,
        aniListGenresRaw: String? = nil,
        aniListAuthor: String? = nil,
        bannerImage: String? = "",
        aniListParentId: Int? = nil,
        isSpinOff: Bool? = false,
        mangaDexId: String? = nil,
        isPlanned: Bool? = false,
        isFavorite: Bool? = false,
        syncID: String? = UUID().uuidString
    ) {
        self.title = title
        self.note = note
        self.summary = summary
        self.createdAt = createdAt
        self.volumes = volumes
        coverURL = coverUrl
        self.sortOrder = sortOrder
        self.rating = rating
        self.isSold = isSold
        self.aniListId = aniListId
        self.aniListStatus = aniListStatus
        self.aniListAverageScore = aniListAverageScore
        self.aniListStartDate = aniListStartDate
        self.aniListEndDate = aniListEndDate
        self.aniListGenresRaw = aniListGenresRaw
        self.aniListAuthor = aniListAuthor
        self.bannerImage = bannerImage
        self.aniListParentId = aniListParentId
        self.isSpinOff = isSpinOff
        self.mangaDexId = mangaDexId
        self.isPlanned = isPlanned
        self.isFavorite = isFavorite
        self.syncID = syncID
    }
}

@Model
final class Volume {
    var number: Int
    var owned: Bool
    var purchaseDate: Date?
    var price: Double?
    var read: Bool?
    var readDate: Date?
    var releaseDate: Date?
    var buyURL: String?
    /// This volume's cover art, fetched from MangaDex. Nil until the
    /// series' covers are pulled, and for volumes MangaDex has none for.
    var coverURL: String?

    var manga: Manga?

    /// The original volumes a collected edition binds together (a deluxe
    /// Berserk volume holds three), so each can be marked read on its own.
    /// Empty for an ordinary volume. `read` on the volume is kept in step:
    /// true once every part is read.
    @Relationship(deleteRule: .cascade, inverse: \VolumePart.volume)
    var parts: [VolumePart]

    init(
        number: Int,
        owned: Bool = false,
        purchaseDate: Date? = nil,
        price: Double? = nil,
        read: Bool? = false,
        manga: Manga? = nil,
        readDate: Date? = nil,
        releaseDate: Date? = nil,
        buyURL: String? = nil,
        coverURL: String? = nil,
        parts: [VolumePart] = []
    ) {
        self.number = number
        self.owned = owned
        self.purchaseDate = purchaseDate
        self.price = price
        self.read = read
        self.manga = manga
        self.readDate = readDate
        self.releaseDate = releaseDate
        self.buyURL = buyURL
        self.coverURL = coverURL
        self.parts = parts
    }
}

/// One original volume inside a split `Volume`. Owned, priced and dated
/// through its volume; only reading is tracked here.
@Model
final class VolumePart {
    /// 1-based position within the volume.
    var index: Int
    var read: Bool
    var readDate: Date?

    var volume: Volume?

    init(index: Int, read: Bool = false, readDate: Date? = nil, volume: Volume? = nil) {
        self.index = index
        self.read = read
        self.readDate = readDate
        self.volume = volume
    }
}
