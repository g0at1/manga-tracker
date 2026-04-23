import SwiftData
import SwiftUI

extension ContentView {
    func toggleViewMode() {
        viewModeRaw =
            (viewMode == .list ? LibraryViewMode.grid : LibraryViewMode.list)
            .rawValue
    }

    func addManga() {
        let nextOrder = (mangas.compactMap(\.sortOrder).max() ?? -1) + 1
        let manga = Manga(title: "Nowa manga", sortOrder: nextOrder)
        modelContext.insert(manga)
        selectedManga = manga
    }

    func deleteManga(_ manga: Manga) {
        if selectedManga?.persistentModelID == manga.persistentModelID {
            selectedManga = nil
        }
        modelContext.delete(manga)
    }

    func moveMangas(from source: IndexSet, to destination: Int) {
        var reordered = mangas
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, manga) in reordered.enumerated() {
            manga.sortOrder = index
        }

        do {
            try modelContext.save()
        } catch {
            print("Error while saving sort order: \(error)")
        }
    }

    func moveMangaUp(_ manga: Manga) {
        guard
            let index = mangas.firstIndex(where: {
                $0.persistentModelID == manga.persistentModelID
            }),
            index > 0
        else { return }

        swapSortOrder(at: index, and: index - 1)
    }

    func moveMangaDown(_ manga: Manga) {
        guard
            let index = mangas.firstIndex(where: {
                $0.persistentModelID == manga.persistentModelID
            }),
            index < mangas.count - 1
        else { return }

        swapSortOrder(at: index, and: index + 1)
    }

    func swapSortOrder(at firstIndex: Int, and secondIndex: Int) {
        let first = mangas[firstIndex]
        let second = mangas[secondIndex]

        let temp = first.sortOrder
        first.sortOrder = second.sortOrder
        second.sortOrder = temp

        do {
            try modelContext.save()
        } catch {
            print("Error while changing sort order: \(error)")
        }
    }

    func moveMangaInGrid(_ dragged: Manga, _ target: Manga) {
        guard dragged.persistentModelID != target.persistentModelID else {
            return
        }

        var reordered = mangas

        guard
            let fromIndex = reordered.firstIndex(where: {
                $0.persistentModelID == dragged.persistentModelID
            }),
            let toIndex = reordered.firstIndex(where: {
                $0.persistentModelID == target.persistentModelID
            })
        else { return }

        let movedItem = reordered.remove(at: fromIndex)
        reordered.insert(movedItem, at: toIndex)

        for (index, manga) in reordered.enumerated() {
            manga.sortOrder = index
        }

        do {
            try modelContext.save()
        } catch {
            print("Error while saving grid reorder: \(error)")
        }
    }
    
    func markNextAsRead(_ manga: Manga) {
        let sortedVolumes = manga.volumes.sorted { $0.number < $1.number }

        guard !sortedVolumes.isEmpty else { return }

        let lastReadIndex = sortedVolumes.lastIndex(where: { $0.read == true }) ?? -1
        let nextIndex = lastReadIndex + 1

        guard sortedVolumes.indices.contains(nextIndex) else { return }

        let nextVolume = sortedVolumes[nextIndex]

        guard nextVolume.read != true else { return }

        nextVolume.read = true
        nextVolume.readDate = Date()

        do {
            try modelContext.save()
        } catch {
            print("Error while marking next volume as read: \(error)")
        }
    }
}
