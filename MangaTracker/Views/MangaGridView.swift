internal import UniformTypeIdentifiers
import SwiftData
import SwiftUI

struct MangaGridView: View {
    let mangas: [Manga]

    @Binding var selectedManga: Manga?
    @Binding var draggedManga: Manga?

    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangaInGrid: (Manga, Manga) -> Void
    let onMarkNextAsRead: (Manga) -> Void
    let onToggleSold: (Manga) -> Void
    let onToggleSpinOff: (Manga) -> Void
    let isReorderable: Bool

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 140, maximum: 175), spacing: 14),
            ],
            spacing: 16
        ) {
            ForEach(mangas) { manga in
                card(for: manga)
                    .contextMenu {
                        Button("Oznacz kolejny tom jako przeczytany") {
                            onMarkNextAsRead(manga)
                        }
                        Button(
                            manga.isSold ?? false
                                ? "Cofnij sprzedane" : "Sprzedane"
                        ) {
                            onToggleSold(manga)
                        }
                        Button(
                            manga.isSpinOff ?? false
                                ? "Cofnij spin-off" : "Oznacz jako spin-off"
                        ) {
                            onToggleSpinOff(manga)
                        }
                        if isReorderable {
                            Divider()
                            Button("Przesuń wyżej") { onMoveMangaUp(manga) }
                            Button("Przesuń niżej") { onMoveMangaDown(manga) }
                        }
                        Divider()
                        Button("Usuń", role: .destructive) {
                            onDeleteManga(manga)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func card(for manga: Manga) -> some View {
        let card = MangaGridCardView(manga: manga)
            .onTapGesture {
                selectedManga = manga
            }

        if isReorderable {
            card
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
        } else {
            card
        }
    }
}
