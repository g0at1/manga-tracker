internal import UniformTypeIdentifiers
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Manga.sortOrder, order: .forward)
    var mangas: [Manga]

    @State var selectedManga: Manga?
    @State var searchText = ""
    @State var showDashboard = false
    @State var draggedManga: Manga?

    @AppStorage("libraryViewMode") var viewModeRaw: String = LibraryViewMode.list.rawValue
    @StateObject private var toastService = ToastService.shared

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
        ZStack {
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
                    onMarkNextAsRead: markNextAsRead,
                    onToggleSold: toggleSold
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
                                systemImage: viewMode == .list ? "square.grid.2x2" : "list.bullet"
                            )
                        }

                        Button {
                            showDashboard = true
                        } label: {
                            Label("Dashboard", systemImage: "chart.xyaxis.line")
                        }

                        Button {
                            openWindow(id: "upcoming")
                        } label: {
                            Label("Nadchodzące", systemImage: "calendar.badge.clock")
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

            if !toastService.toasts.isEmpty {
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(toastService.toasts) { toast in
                        ToastView(message: toast)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.85),
            value: toastService.toasts
        )
    }
}
