import SwiftUI

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case manual
    case title
    case totalPrice
    case ownedVolumes
    case readPercent
    case rating
    case dateAdded

    var id: String {
        rawValue
    }

    var label: LocalizedStringKey {
        switch self {
        case .manual: "Własna kolejność"
        case .title: "Tytuł"
        case .totalPrice: "Wydano"
        case .ownedVolumes: "Liczba tomów"
        case .readPercent: "Przeczytano"
        case .rating: "Ocena"
        case .dateAdded: "Data dodania"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "arrow.up.arrow.down"
        case .title: "textformat"
        case .totalPrice: "creditcard"
        case .ownedVolumes: "book"
        case .readPercent: "checkmark.circle"
        case .rating: "star"
        case .dateAdded: "calendar"
        }
    }

    /// Sorts in ascending order for this option; the caller reverses for descending.
    func sorted(_ mangas: [Manga]) -> [Manga] {
        switch self {
        case .manual:
            mangas.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        case .title:
            mangas.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            mangas.sorted { ($0.rating ?? 0) < ($1.rating ?? 0) }
        case .dateAdded:
            mangas.sorted { $0.createdAt < $1.createdAt }
        case .totalPrice:
            Self.sorted(mangas) { $0.totalPaid }
        case .ownedVolumes:
            Self.sorted(mangas) { $0.owned }
        case .readPercent:
            Self.sorted(mangas) { $0.readPercent }
        }
    }

    /// Sorts by a volume-derived key, computing it once per series rather
    /// than once per comparison.
    private static func sorted<Key: Comparable>(
        _ mangas: [Manga],
        by key: (MangaVolumeStats) -> Key
    ) -> [Manga] {
        mangas
            .map { (manga: $0, key: key($0.volumeStats)) }
            .sorted { $0.key < $1.key }
            .map(\.manga)
    }
}
