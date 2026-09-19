import SwiftData
import SwiftUI

/// The library with the detail page pushed on top, plus the toast overlay.
struct RootView: View {
    @Query(sort: \Manga.sortOrder, order: .forward)
    private var mangas: [Manga]

    @State private var path: [Manga] = []
    /// Not observed here on purpose: toasts render in `ToastOverlayView`,
    /// so showing one doesn't re-evaluate the library.
    private let toastService = ToastService.shared

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                LibraryScreen(mangas: mangas, path: $path)
                    .navigationDestination(for: Manga.self) { manga in
                        MangaDetailScreen(manga: manga)
                    }
            }
            .tint(.green)

            ToastOverlayView(toastService: toastService)
        }
        .onChange(of: mangas.map(\.persistentModelID)) { _, ids in
            // A series deleted elsewhere (sync, or the list's context menu)
            // must not stay open: its model can't be read any more.
            let existing = Set(ids)
            path.removeAll { !existing.contains($0.persistentModelID) }
        }
    }
}
