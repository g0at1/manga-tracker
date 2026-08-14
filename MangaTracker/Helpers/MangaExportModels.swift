import Foundation

struct ExportedVolume: Codable {
    var number: Int
    var owned: Bool
    var purchaseDate: Date?
    var price: Double?
    var read: Bool?
    var readDate: Date?
    var releaseDate: Date?
    var buyURL: String?
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

    var volumes: [ExportedVolume]
}

func encodeMangasToJSON(_ mangas: [Manga]) throws -> Data {
    let exported = mangas.map { manga in
        ExportedManga(
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
            volumes: manga.volumes.map { v in
                ExportedVolume(
                    number: v.number,
                    owned: v.owned,
                    purchaseDate: v.purchaseDate,
                    price: v.price,
                    read: v.read,
                    readDate: v.readDate,
                    releaseDate: v.releaseDate,
                    buyURL: v.buyURL
                )
            }
        )
    }

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
