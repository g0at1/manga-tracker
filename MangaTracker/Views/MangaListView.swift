import SwiftUI

struct MangaListView: View {
    let mangas: [Manga]
    @Binding var selectedManga: Manga?

    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangas: (IndexSet, Int) -> Void

    var body: some View {
        List(selection: $selectedManga) {
            ForEach(mangas) { manga in
                MangaListRowView(manga: manga)
                    .tag(manga)
                    .contextMenu {
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
