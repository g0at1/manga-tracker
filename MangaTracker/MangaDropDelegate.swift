import SwiftData
import SwiftUI

struct MangaDropDelegate: DropDelegate {
    let targetManga: Manga
    let mangas: [Manga]

    @Binding var draggedManga: Manga?
    let moveAction: (Manga, Manga) -> Void

    func dropEntered(info _: DropInfo) {
        guard
            let draggedManga,
            draggedManga.persistentModelID != targetManga.persistentModelID
        else { return }

        moveAction(draggedManga, targetManga)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedManga = nil
        return true
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
