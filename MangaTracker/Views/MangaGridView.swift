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
    let onTogglePlanned: (Manga) -> Void
    let onToggleFavorite: (Manga) -> Void
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
                        if manga.isPlanned ?? false {
                            // Wishlist entry: buying it moves it into the library proper.
                            // Nothing to sell yet, so that option stays hidden.
                            Button("Kupiona — przenieś do biblioteki", systemImage: "cart") {
                                onTogglePlanned(manga)
                            }
                        } else {
                            Button("Oznacz kolejny tom jako przeczytany") {
                                onMarkNextAsRead(manga)
                            }
                            Button(
                                manga.isFavorite ?? false ? "Usuń z ulubionych" : "Dodaj do ulubionych",
                                systemImage: manga.isFavorite ?? false ? "heart.slash" : "heart"
                            ) {
                                onToggleFavorite(manga)
                            }
                            Button("Przenieś do planowanych", systemImage: "bookmark") {
                                onTogglePlanned(manga)
                            }
                            Button(
                                manga.isSold ?? false
                                    ? "Cofnij sprzedane" : "Sprzedane"
                            ) {
                                onToggleSold(manga)
                            }
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
