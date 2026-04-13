import SwiftData
import SwiftUI
internal import UniformTypeIdentifiers

struct MangaGridView: View {
    let mangas: [Manga]

    @Binding var selectedManga: Manga?
    @Binding var draggedManga: Manga?

    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangaInGrid: (Manga, Manga) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(mangas) { manga in
                    MangaGridCardView(
                        manga: manga,
                        isSelected: selectedManga?.persistentModelID
                            == manga.persistentModelID
                    )
                    .onTapGesture {
                        selectedManga = manga
                    }
                    .onDrag {
                        draggedManga = manga
                        return NSItemProvider(object: manga.title as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: MangaDropDelegate(
                            targetManga: manga,
                            mangas: mangas,
                            draggedManga: $draggedManga,
                            moveAction: onMoveMangaInGrid
                        )
                    )
                    .contextMenu {
                        Button("Przesuń wyżej") { onMoveMangaUp(manga) }
                        Button("Przesuń niżej") { onMoveMangaDown(manga) }
                        Divider()
                        Button("Usuń", role: .destructive) {
                            onDeleteManga(manga)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
