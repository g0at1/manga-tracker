import Foundation

extension Manga {
    /// Copies what AniList knows about the series over the local record and
    /// fills in any volume numbers the series is missing. The cover is only
    /// taken when there isn't one yet, so a hand-picked cover survives a
    /// refresh; the synopsis is replaced only when AniList has one.
    func applyAniListInfo(_ info: AniListMangaInfo) {
        aniListId = info.id
        aniListStatus = info.status
        aniListGenresRaw = info.genres.joined(separator: ", ")
        aniListAverageScore = info.averageScore
        aniListStartDate = info.startDate
        aniListEndDate = info.endDate
        aniListAuthor = info.author
        bannerImage = info.bannerImage
        aniListParentId = info.parentId
        isSpinOff = info.parentId != nil
        if let description = info.description {
            summary = description
        }

        if let totalVolumes = info.volumes, totalVolumes > 0 {
            let existing = Set(volumes.map(\.number))
            for number in 1 ... totalVolumes where !existing.contains(number) {
                volumes.append(Volume(number: number, owned: false, manga: self))
            }
        }

        if (coverURL ?? "").isEmpty {
            coverURL = info.coverURL
        }
    }
}
