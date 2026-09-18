import SwiftUI

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

    var label: LocalizedStringKey {
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
    var chipLabel: LocalizedStringKey {
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

    /// Whether `manga` belongs in this section. Pass `stats` when the caller
    /// already has them so the volumes aren't walked again; sections that
    /// don't look at volumes never compute them.
    func contains(_ manga: Manga, stats: MangaVolumeStats? = nil) -> Bool {
        let isSold = manga.isSold ?? false

        switch self {
        case .all:
            return !isSold
        case .sold:
            return isSold
        case .favorites:
            return !isSold && (manga.rating ?? 0) >= 4.5
        case .inProgress:
            // Everything you own that isn't wrapped up yet — including fully
            // read series that are still being published.
            guard !isSold else { return false }
            let stats = stats ?? manga.volumeStats
            return stats.ownsAnything && !manga.isCompleted(stats)
        case .completed:
            guard !isSold else { return false }
            return manga.isCompleted(stats ?? manga.volumeStats)
        case .planned:
            guard !isSold else { return false }
            return (stats ?? manga.volumeStats).hasMissing
        }
    }
}
