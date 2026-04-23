import SwiftUI

struct MangaListView: View {
    let mangas: [Manga]
    @Binding var selectedManga: Manga?

    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangas: (IndexSet, Int) -> Void
    let onMarkNextAsRead: (Manga) -> Void

    var body: some View {
        List(selection: $selectedManga) {
            ForEach(mangas) { manga in
                MangaListRowView(manga: manga)
                    .tag(manga)
                    .contextMenu {
                        Button("Oznacz kolejny tom jako przeczytany") { onMarkNextAsRead(manga) }
                        Divider()
                        Button("Przesuń wyżej") { onMoveMangaUp(manga) }
                        Button("Przesuń niżej") { onMoveMangaDown(manga) }
                        Divider()
                        Button("Usuń", role: .destructive) {
                            onDeleteManga(manga)
                        }
                    }
            }
            .onMove(perform: onMoveMangas)
        }
    }
}
