import SwiftData
import SwiftUI

struct MangaListView: View {
    let mangas: [Manga]
    @Binding var selectedManga: Manga?

    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangas: (IndexSet, Int) -> Void
    let onMarkNextAsRead: (Manga) -> Void
    let onToggleSold: (Manga) -> Void
    let isReorderable: Bool

    var body: some View {
        List(selection: $selectedManga) {
            ForEach(mangas) { manga in
                MangaListRowView(manga: manga)
                    .listRowSelectionHighlightHidden()
                    .tag(manga)
                    .listRowBackground(rowBackground(for: manga))
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
            .onMove(perform: isReorderable ? onMoveMangas : nil)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowBackground(for manga: Manga) -> some View {
        let isSelected = selectedManga?.persistentModelID == manga.persistentModelID
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.green.opacity(0.22) : Color.clear)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
}
