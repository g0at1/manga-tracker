import SwiftData
import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) var modelContext

    @Query(sort: \Manga.sortOrder, order: .forward)
    var mangas: [Manga]

    @State var selectedManga: Manga?
    @State var searchText = ""
    @State var showDashboard = false
    @State var draggedManga: Manga?
    @AppStorage("libraryViewMode") var viewModeRaw: String = LibraryViewMode
        .list.rawValue

    var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .list
    }

    var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return mangas }
        return mangas.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(
                mangas: mangas,
                filteredMangas: filteredMangas,
                selectedManga: $selectedManga,
                searchText: $searchText,
                showDashboard: $showDashboard,
                draggedManga: $draggedManga,
                viewMode: viewMode,
                onToggleViewMode: toggleViewMode,
                onAddManga: addManga,
                onDeleteManga: deleteManga,
                onMoveMangaUp: moveMangaUp,
                onMoveMangaDown: moveMangaDown,
                onMoveMangas: moveMangas,
                onMoveMangaInGrid: moveMangaInGrid,
                onMarkNextAsRead: markNextAsRead
            )
            .navigationTitle("Mangi")
            .searchable(text: $searchText, prompt: "Szukaj tytułu…")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        toggleViewMode()
                    } label: {
                        Label(
                            viewMode == .list ? "Grid view" : "List view",
                            systemImage: viewMode == .list
                                ? "square.grid.2x2" : "list.bullet"
                        )
                    }

                    Button {
                        showDashboard = true
                    } label: {
                        Label("Dashboard", systemImage: "chart.xyaxis.line")
                    }

                    Button {
                        addManga()
                    } label: {
                        Label("Dodaj", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                if selectedManga == nil {
                    selectedManga = filteredMangas.first
                }
            }
            .onChange(of: mangas) { _, newValue in
                if selectedManga == nil {
                    selectedManga = newValue.first
                }
            }
        } detail: {
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
                    .id(selectedManga.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Wybierz mangę",
                    systemImage: "books.vertical",
                    description: Text("Albo dodaj nową po lewej.")
                )
            }
        }
        .sheet(isPresented: $showDashboard) {
            DashboardView(mangas: mangas)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
