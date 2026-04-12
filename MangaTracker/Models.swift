import Foundation
import SwiftData

@Model
final class Manga {
    var title: String
    var note: String
    var createdAt: Date
    var coverURL: String?
    var sortOrder: Int?
    var rating: Double?

    @Relationship(deleteRule: .cascade, inverse: \Volume.manga)
    var volumes: [Volume]

    init(
        title: String,
        note: String = "",
        createdAt: Date = .now,
        volumes: [Volume] = [],
        coverUrl: String? = "",
        sortOrder: Int? = 0,
        rating: Double? = 0
    ) {
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.volumes = volumes
        self.coverURL = coverUrl
        self.sortOrder = sortOrder
        self.rating = rating
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
