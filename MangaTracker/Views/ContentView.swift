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
    @State var draggedManga: Manga?
    @State private var showUnreadOnly = false

    @AppStorage("libraryViewMode") var viewModeRaw: String = LibraryViewMode.list.rawValue
    @StateObject private var toastService = ToastService.shared

    // Import state
    @State private var isImporting: Bool = false

    var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .list
    }

    var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var mangasToFilter = mangas
        if showUnreadOnly {
            mangasToFilter = mangasToFilter.filter { manga in
                manga.isSold != true &&
                    manga.volumes.contains { volume in
                        volume.owned &&
                            volume.read != true
                    }
            }
        }
        guard !query.isEmpty else { return mangasToFilter }
        return mangasToFilter.filter {
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
                    onToggleSold: toggleSold,
                    onToggleSpinOff: toggleSpinOff
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
                            openWindow(id: "dashboard")
                        } label: {
                            Label("Dashboard", systemImage: "chart.xyaxis.line")
                        }

                        Button {
                            openWindow(id: "upcoming")
                        } label: {
                            Label("Nadchodzące", systemImage: "calendar.badge.clock")
                        }

                        Button {
                            showUnreadOnly.toggle()
                        } label: {
                            Label(
                                showUnreadOnly ? "Pokaż wszystkie" : "Pokaż nieprzeczytane",
                                systemImage: showUnreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                            )
                        }

                        Button {
                            // Export to Downloads folder (avoids save panel entitlement issues)
                            exportToDownloads()
                        } label: {
                            Label("Eksportuj", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            // show import dialog (open panel) to pick JSON file
                            isImporting = true
                        } label: {
                            Label("Importuj", systemImage: "square.and.arrow.down")
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    let exported = try decodeMangasFromJSON(data)

                    // Replace current library with imported data
                    for manga in mangas {
                        modelContext.delete(manga)
                    }

                    for em in exported {
                        let m = Manga(
                            title: em.title,
                            note: em.note,
                            summary: em.summary,
                            createdAt: em.createdAt,
                            volumes: [],
                            coverUrl: em.coverURL,
                            sortOrder: em.sortOrder,
                            rating: em.rating,
                            isSold: em.isSold,
                            aniListId: em.aniListId,
                            aniListStatus: em.aniListStatus,
                            aniListAverageScore: em.aniListAverageScore,
                            aniListStartDate: em.aniListStartDate,
                            aniListEndDate: em.aniListEndDate,
                            aniListGenresRaw: em.aniListGenresRaw,
                            aniListAuthor: em.aniListAuthor,
                            bannerImage: em.bannerImage,
                            aniListParentId: em.aniListParentId,
                            isSpinOff: em.isSpinOff
                        )

                        var vols: [Volume] = []
                        for ev in em.volumes {
                            let v = Volume(
                                number: ev.number,
                                owned: ev.owned,
                                purchaseDate: ev.purchaseDate,
                                price: ev.price,
                                read: ev.read,
                                manga: nil,
                                readDate: ev.readDate,
                                releaseDate: ev.releaseDate,
                                buyURL: ev.buyURL
                            )
                            v.manga = m
                            vols.append(v)
                        }

                        m.volumes = vols
                        modelContext.insert(m)
                    }

                    do {
                        try modelContext.save()
                        toastService.show("Import pomyślny")
                    } catch {
                        toastService.show("Import nieudany: \(error.localizedDescription)")
                    }
                } catch {
                    toastService.show("Import nieudany: \(error.localizedDescription)")
                }
            case .failure(let error):
                toastService.show("Import nieudany: \(error.localizedDescription)")
            }
        }
    }

    private func exportToDownloads() {
        do {
            let data = try encodeMangasToJSON(mangas)
            let filename = "manga-export-\(Date().yyyyMMdd()).json"
            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                toastService.show("Nie można znaleźć folderu Pobrane")
                return
            }
            let url = downloads.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            toastService.show("Eksport zapisano: \(url.path)")
        } catch {
            toastService.show("Eksport nieudany: \(error.localizedDescription)")
        }
    }
}

