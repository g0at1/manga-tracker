import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Manga.createdAt, order: .reverse)
    private var mangas: [Manga]

    @State private var selectedManga: Manga?
    @State private var searchText = ""

    var filteredMangas: [Manga] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mangas
        }
        return mangas.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var mangaCount: Int {
        mangas.count
    }

    private var totalPaid: Double {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    private var ownedVolumesCount: Int {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .count
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {

                HStack(spacing: 12) {
                    Text("Mangi: \(mangaCount)")

                    Text("•")

                    Text("Tomy: \(ownedVolumesCount)")

                    Text("•")

                    Text("Wydano:")
                    Text(
                        totalPaid,
                        format: .currency(
                            code: Locale.current.currency?.identifier ?? "PLN"
                        )
                    )
                    .monospacedDigit()

                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()

                List(selection: $selectedManga) {
                    ForEach(filteredMangas) { manga in
                        HStack(spacing: 10) {
                            CachedAsyncImage(
                                url: URL(string: manga.coverURL ?? ""),
                                cornerRadius: 6
                            )
                            .frame(width: 40, height: 56)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(manga.title).font(.headline)
                                if !manga.note.isEmpty {
                                    Text(manga.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(manga)
                        .contextMenu {
                            Button("Usuń") { deleteManga(manga) }
                        }
                    }
                }
            }.navigationTitle("Mangi")
                .searchable(text: $searchText, prompt: "Szukaj tytułu…")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            addManga()
                        } label: {
                            Label("Dodaj", systemImage: "plus")
                        }
                    }
                }
        } detail: {
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
            } else {
                ContentUnavailableView(
                    "Wybierz mangę",
                    systemImage: "books.vertical",
                    description: Text("Albo dodaj nową po lewej.")
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func addManga() {
        let m = Manga(title: "Nowa manga")
        modelContext.insert(m)
        selectedManga = m
    }

    private func deleteManga(_ manga: Manga) {
        if selectedManga?.persistentModelID == manga.persistentModelID {
            selectedManga = nil
        }
        modelContext.delete(manga)
    }
}
