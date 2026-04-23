import SwiftUI

struct LibrarySidebarView: View {
    let mangas: [Manga]
    let filteredMangas: [Manga]

    @Binding var selectedManga: Manga?
    @Binding var searchText: String
    @Binding var showDashboard: Bool
    @Binding var draggedManga: Manga?

    let viewMode: LibraryViewMode

    let onToggleViewMode: () -> Void
    let onAddManga: () -> Void
    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangas: (IndexSet, Int) -> Void
    let onMoveMangaInGrid: (Manga, Manga) -> Void
    let onMarkNextAsRead: (Manga) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SummaryHeaderView(mangas: mangas)
            Divider()

            Group {
                if viewMode == .list {
                    MangaListView(
                        mangas: filteredMangas,
                        selectedManga: $selectedManga,
                        onDeleteManga: onDeleteManga,
                        onMoveMangaUp: onMoveMangaUp,
                        onMoveMangaDown: onMoveMangaDown,
                        onMoveMangas: onMoveMangas,
                        onMarkNextAsRead: onMarkNextAsRead
                    )
                } else {
                    MangaGridView(
                        mangas: filteredMangas,
                        selectedManga: $selectedManga,
                        draggedManga: $draggedManga,
                        onDeleteManga: onDeleteManga,
                        onMoveMangaUp: onMoveMangaUp,
                        onMoveMangaDown: onMoveMangaDown,
                        onMoveMangaInGrid: onMoveMangaInGrid,
                        onMarkNextAsRead: onMarkNextAsRead
                    )
                }
            }

            Divider()
            BottomBarView(mangas: mangas)
        }
    }
}
