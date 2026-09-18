import Foundation

/// Sections of the library shown in the sidebar and as filter chips.
enum LibraryCategory: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case completed
    case favorites
    case planned
    case sold

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: "Biblioteka"
        case .inProgress: "W trakcie"
        case .completed: "Ukończone"
        case .favorites: "Ulubione"
        case .planned: "Planowane"
        case .sold: "Sprzedane"
        }
    }

    /// Shorter label used on the filter chips above the grid.
    var chipLabel: String {
        self == .all ? "Wszystkie" : label
    }

    var systemImage: String {
        switch self {
        case .all: "books.vertical.fill"
        case .inProgress: "book"
        case .completed: "checkmark.circle"
        case .favorites: "heart"
        case .planned: "cart"
        case .sold: "tag"
        }
    }

    func contains(_ manga: Manga) -> Bool {
        let isSold = manga.isSold ?? false
        let ownsAnything = manga.volumes.contains { $0.owned }

        switch self {
        case .all:
            return !isSold
        case .inProgress:
            // Everything you own that isn't wrapped up yet — including fully
            // read series that are still being published.
            return !isSold && ownsAnything && !manga.isCompleted
        case .completed:
            return !isSold && manga.isCompleted
        case .favorites:
            return !isSold && (manga.rating ?? 0) >= 4.5
        case .planned:
            return !isSold && manga.volumes.contains { !$0.owned }
        case .sold:
            return isSold
        }
    }
}
