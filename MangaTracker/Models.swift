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
    var bannerImage: String?
    var aniListId: Int?
    var aniListStatus: String?
    var aniListAverageScore: Int?
    var aniListStartDate: Date?
    var aniListEndDate: Date?
    var aniListGenresRaw: String?
    var aniListAuthor: String?

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
        aniListId: Int? = nil,
        aniListStatus: String? = nil,
        aniListAverageScore: Int? = nil,
        aniListStartDate: Date? = nil,
        aniListEndDate: Date? = nil,
        aniListGenresRaw: String? = nil,
        aniListAuthor: String? = nil,
        bannerImage: String? = ""
    ) {
        self.title = title
        self.note = note
        self.summary = summary
        self.createdAt = createdAt
        self.volumes = volumes
        self.coverURL = coverUrl
        self.sortOrder = sortOrder
        self.rating = rating
        self.aniListId = aniListId
        self.aniListStatus = aniListStatus
        self.aniListAverageScore = aniListAverageScore
        self.aniListStartDate = aniListStartDate
        self.aniListEndDate = aniListEndDate
        self.aniListGenresRaw = aniListGenresRaw
        self.aniListAuthor = aniListAuthor
        self.bannerImage = bannerImage
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

    var manga: Manga?

    init(
        number: Int,
        owned: Bool = false,
        purchaseDate: Date? = nil,
        price: Double? = nil,
        read: Bool? = false,
        manga: Manga? = nil,
        readDate: Date? = nil
    ) {
        self.number = number
        self.owned = owned
        self.purchaseDate = purchaseDate
        self.price = price
        self.read = read
        self.manga = manga
        self.readDate = readDate
    }
}
