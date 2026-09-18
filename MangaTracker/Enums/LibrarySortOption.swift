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
    func areInIncreasingOrder(_ lhs: Manga, _ rhs: Manga) -> Bool {
        switch self {
        case .manual:
            (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0)
        case .title:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .totalPrice:
            lhs.totalPaid < rhs.totalPaid
        case .ownedVolumes:
            lhs.ownedVolumesCount < rhs.ownedVolumesCount
        case .readPercent:
            lhs.readPercent < rhs.readPercent
        case .rating:
            (lhs.rating ?? 0) < (rhs.rating ?? 0)
        case .dateAdded:
            lhs.createdAt < rhs.createdAt
        }
    }
}
