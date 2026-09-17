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

    @AppStorage("libraryViewMode") var viewModeRaw: String = LibraryViewMode.list.rawValue
    @AppStorage("librarySortOption") private var sortOptionRaw: String = LibrarySortOption.manual.rawValue
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true
    @AppStorage("libraryShowUnreadOnly") private var showUnreadOnly = false
    @AppStorage("libraryHideSold") private var hideSold = false
    @AppStorage("libraryHideSpinOffs") private var hideSpinOffs = false
    @AppStorage("lastBackupAt") var lastBackupAtTimestamp: Double = 0
    @AppStorage("backupReminderIntervalDays") var backupReminderIntervalDays: Int = 7
    @StateObject private var toastService = ToastService.shared

    /// Import state
    @State private var isImporting: Bool = false

    /// Slightly larger than the default toolbar glyph size.
    static let toolbarIconFont: Font = .system(size: 16, weight: .medium)

    var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .list
    }

    var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .manual
    }

    /// Drag-reordering only makes sense when the list shows the user's own order.
    var isReorderable: Bool {
        sortOption == .manual
    }

    var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = mangas
        if showUnreadOnly {
            result = result.filter { manga in
                manga.isSold != true &&
                    manga.volumes.contains { volume in
                        volume.owned &&
                            volume.read != true
                    }
            }
        }
        if hideSold {
            result = result.filter { $0.isSold != true }
        }
        if hideSpinOffs {
            result = result.filter { $0.isSpinOff != true }
        }
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
            }
        }
        result.sort(by: sortOption.areInIncreasingOrder)
        return sortAscending ? result : result.reversed()
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                StatsSidebarView(mangas: mangas)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } content: {
                LibrarySidebarView(
                    filteredMangas: filteredMangas,
                    selectedManga: $selectedManga,
                    searchText: $searchText,
                    draggedManga: $draggedManga,
                    sortOptionRaw: $sortOptionRaw,
                    sortAscending: $sortAscending,
                    showUnreadOnly: $showUnreadOnly,
                    hideSold: $hideSold,
                    hideSpinOffs: $hideSpinOffs,
                    viewMode: viewMode,
                    isReorderable: isReorderable,
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
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            toggleViewMode()
                        } label: {
                            Label(
                                viewMode == .list ? "Grid view" : "List view",
                                systemImage: viewMode == .list ? "square.grid.2x2" : "list.bullet"
                            )
                            .font(Self.toolbarIconFont)
                        }

                        Button {
                            openWindow(id: "dashboard")
                        } label: {
                            Label("Dashboard", systemImage: "chart.xyaxis.line")
                                .font(Self.toolbarIconFont)
                        }

                        Button {
                            openWindow(id: "upcoming")
                        } label: {
                            Label("Nadchodzące", systemImage: "calendar.badge.clock")
                                .font(Self.toolbarIconFont)
                        }

                        NotificationsMenuView(toastService: toastService)

                        Button {
                            // Export to Downloads folder (avoids save panel entitlement issues)
                            exportToDownloads()
                        } label: {
                            Label("Eksportuj", systemImage: "square.and.arrow.up")
                                .font(Self.toolbarIconFont)
                        }
                        .help(backupStatusText())

                        Button {
                            // show import dialog (open panel) to pick JSON file
                            isImporting = true
                        } label: {
                            Label("Importuj", systemImage: "square.and.arrow.down")
                                .font(Self.toolbarIconFont)
                        }

                        Button {
                            addManga()
                        } label: {
                            Label("Dodaj", systemImage: "plus")
                                .font(Self.toolbarIconFont)
                        }
                    }
                }
                .onAppear {
                    if selectedManga == nil {
                        selectedManga = filteredMangas.first
                    }
                    showBackupReminderIfNeeded()
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
            .frame(minWidth: 1100, minHeight: 600)
            .toolbarBackground(.hidden, for: .windowToolbar)

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
            case let .success(url):
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
            case let .failure(error):
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
            lastBackupAtTimestamp = Date().timeIntervalSince1970
            toastService.show("Eksport zapisano: \(url.path)")
        } catch {
            toastService.show("Eksport nieudany: \(error.localizedDescription)")
        }
    }

    private func backupStatusText() -> String {
        guard lastBackupAtTimestamp > 0 else {
            return "Ostatni backup: nigdy"
        }
        let date = Date(timeIntervalSince1970: lastBackupAtTimestamp)
        let formatted = DateFormatters.yyyyMMdd.string(from: date)
        return "Ostatni backup: \(formatted)"
    }

    private func showBackupReminderIfNeeded() {
        guard lastBackupAtTimestamp > 0 else { return }
        let lastBackupDate = Date(timeIntervalSince1970: lastBackupAtTimestamp)
        let daysSinceBackup = Calendar.current.dateComponents([.day], from: lastBackupDate, to: Date()).day ?? 0
        if daysSinceBackup >= backupReminderIntervalDays {
            toastService.show("Minęło \(daysSinceBackup) dni od ostatniego backupu. Warto wykonać eksport.")
        }
    }
}
