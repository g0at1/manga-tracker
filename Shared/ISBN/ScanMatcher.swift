import Foundation

/// Finds where a scanned volume belongs in the library. Pure lookups over
/// the series passed in; nothing is changed here.
enum ScanMatcher {
    /// The series a scanned book belongs to, most certain first:
    /// 1. a volume already carrying this ISBN,
    /// 2. the same AniList entry,
    /// 3. a series whose title equals one of `titles` (case, accents and
    ///    punctuation ignored),
    /// 4. the only series whose title before a colon equals one of theirs
    ///    ("Frieren: u kresu drogi" and "Frieren: Beyond Journey's End").
    static func series(
        isbn: String?,
        titles: [String],
        aniListId: Int?,
        in mangas: [Manga]
    ) -> Manga? {
        if let isbn, let manga = mangas.first(where: { $0.volumes.contains { $0.isbn == isbn } }) {
            return manga
        }
        if let aniListId, let manga = mangas.first(where: { $0.aniListId == aniListId }) {
            return manga
        }

        let wanted = Set(titles.map { normalizedTitle($0) }.filter { !$0.isEmpty })
        if let manga = mangas.first(where: { wanted.contains(normalizedTitle($0.title)) }) {
            return manga
        }

        let wantedMain = Set(titles.map { mainTitle($0) }.filter { !$0.isEmpty })
        let loose = mangas.filter { wantedMain.contains(mainTitle($0.title)) }
        return loose.count == 1 ? loose[0] : nil
    }

    /// The volume a scan refers to within a series: the one with this ISBN,
    /// else the one with this number. When a number is given, an ISBN on a
    /// volume with another number doesn't count — the number was typed in
    /// on purpose.
    static func volume(in manga: Manga, isbn: String?, number: Int?) -> Volume? {
        if let isbn, let volume = manga.volumes.first(where: { $0.isbn == isbn && (number == nil || $0.number == number) }) {
            return volume
        }
        if let number {
            return manga.volumes.first { $0.number == number }
        }
        return nil
    }

    /// Lowercased, accents folded ("Sōsō" → "soso"), every run of
    /// punctuation and spaces made one space.
    static func normalizedTitle(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    private static func mainTitle(_ title: String) -> String {
        normalizedTitle(String(title.split(separator: ":", maxSplits: 1).first ?? ""))
    }
}

/// What saving a scanned volume did.
enum ScannedVolumeResult: Equatable {
    /// The volume was already owned; nothing but a missing ISBN was filled in.
    case alreadyOwned
    /// The volume was listed (from AniList, or on its way) and is now owned.
    case markedOwned
    /// The series had no such volume; it was added, owned.
    case added
}

extension Manga {
    /// Puts a scanned volume into this series without duplicating it: an
    /// owned volume is left alone, one listed but not owned is marked
    /// bought (price and date taken when given), and a missing one is
    /// added. The ISBN is kept on the volume either way, so the next scan
    /// of the same book matches it exactly.
    @discardableResult
    func addScannedVolume(
        number: Int,
        isbn: String?,
        price: Double?,
        purchaseDate: Date = .now
    ) -> ScannedVolumeResult {
        if let volume = ScanMatcher.volume(in: self, isbn: isbn, number: number) {
            if volume.isbn == nil, let isbn {
                volume.isbn = isbn
            }
            if volume.owned {
                return .alreadyOwned
            }
            // A volume on its way keeps its order date as the purchase date.
            volume.markOwned(true, on: purchaseDate)
            if let price {
                volume.price = price
            }
            return .markedOwned
        }

        volumes.append(
            Volume(number: number, owned: true, purchaseDate: purchaseDate, price: price, manga: self, isbn: isbn)
        )
        return .added
    }
}
