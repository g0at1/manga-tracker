internal import UniformTypeIdentifiers
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Manga.sortOrder, order: .forward)
    var mangas: [Manga]

    @State var selectedManga: Manga?
    /// Series closed most recently, so ⌘→ can reopen it.
    @State private var lastClosedManga: Manga?
    /// Rolled once per launch to pick the header banner.
    @State private var bannerSeed = Int.random(in: 0 ..< 1_000_000)
    @State var searchText = ""
    @State var draggedManga: Manga?

    @AppStorage("librarySortOption") private var sortOptionRaw: String = LibrarySortOption.manual.rawValue
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true
    @AppStorage("libraryCategory") private var categoryRaw: String = LibraryCategory.all.rawValue
    @AppStorage("libraryHideSpinOffs") private var hideSpinOffs = false
    @AppStorage("lastBackupAt") var lastBackupAtTimestamp: Double = 0
    @AppStorage("backupReminderIntervalDays") var backupReminderIntervalDays: Int = 7
    /// Not observed here on purpose: toasts render in `ToastOverlayView`, so
    /// showing one doesn't re-evaluate the whole library.
    private let toastService = ToastService.shared

    /// Import state
    @State private var isImporting: Bool = false
    @State private var isShowingSettings = false

    var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .manual
    }

    var category: Binding<LibraryCategory> {
        Binding(
            get: { LibraryCategory(rawValue: categoryRaw) ?? .all },
            set: { newValue in
                categoryRaw = newValue.rawValue
                // Picking a section always lands on the library, not a detail page.
                goBackToLibrary()
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        )
    }

    /// Drag-reordering only makes sense when the list shows the user's own order.
    var isReorderable: Bool {
        sortOption == .manual
    }

    var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = category.wrappedValue
        let matching = mangas.filter { manga in
            (!hideSpinOffs || manga.isSpinOff != true)
                && (query.isEmpty || manga.title.localizedCaseInsensitiveContains(query))
                && section.contains(manga)
        }
        let sorted = sortOption.sorted(matching)
        return sortAscending ? sorted : sorted.reversed()
    }

    /// Series per section for the sidebar and filter chips, from one pass
    /// over the library.
    var categoryCounts: [LibraryCategory: Int] {
        var counts: [LibraryCategory: Int] = [:]
        for manga in mangas where !hideSpinOffs || manga.isSpinOff != true {
            let stats = manga.volumeStats
            for section in LibraryCategory.allCases where section.contains(manga, stats: stats) {
                counts[section, default: 0] += 1
            }
        }
        return counts
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                NavigationSidebarView(
                    categoryCounts: categoryCounts,
                    category: category,
                    toastService: toastService,
                    onOpenStatistics: {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        openWindow(id: "dashboard")
                    },
                    onOpenUpcoming: {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        openWindow(id: "upcoming")
                    },
                    onOpenSettings: {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        isShowingSettings = true
                    }
                )
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            } detail: {
                ZStack {
                    if let selectedManga {
                        MangaDetailView(manga: selectedManga)
                            .id(selectedManga.persistentModelID)
                            .transition(
                                .opacity.combined(with: .offset(x: 28))
                            )
                    } else {
                        LibraryView(
                            allMangas: mangas,
                            filteredMangas: filteredMangas,
                            categoryCounts: categoryCounts,
                            selectedManga: $selectedManga,
                            category: category,
                            searchText: $searchText,
                            draggedManga: $draggedManga,
                            sortOptionRaw: $sortOptionRaw,
                            sortAscending: $sortAscending,
                            hideSpinOffs: $hideSpinOffs,
                            isReorderable: isReorderable,
                            bannerSeed: bannerSeed,
                            onAddManga: addManga,
                            onDeleteManga: deleteManga,
                            onMoveMangaUp: moveMangaUp,
                            onMoveMangaDown: moveMangaDown,
                            onMoveMangaInGrid: moveMangaInGrid,
                            onMarkNextAsRead: markNextAsRead,
                            onToggleSold: toggleSold,
                            onToggleSpinOff: toggleSpinOff,
                            onTogglePlanned: togglePlanned,
                            onToggleFavorite: toggleFavorite
                        )
                        .transition(.opacity)
                    }
                }
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.9),
                    value: selectedManga?.persistentModelID
                )
                .background {
                    // Invisible: only provides ⌘→ to reopen the last closed series.
                    if selectedManga == nil, lastClosedManga != nil {
                        Button("Dalej", action: reopenLastClosedManga)
                            .keyboardShortcut(.rightArrow, modifiers: .command)
                            .frame(width: 0, height: 0)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if let selectedManga {
                            LibraryBreadcrumbView(manga: selectedManga, onBack: goBackToLibrary)
                                .id(selectedManga.persistentModelID)
                        }
                    }
                    // The system glass pill is sized lazily and lags behind the
                    // title; the breadcrumb draws its own background instead.
                    .sharedBackgroundVisibility(.hidden)
                }
                .onAppear {
                    migrateFavoritesIfNeeded()
                    showBackupReminderIfNeeded()
                }
                .onChange(of: mangas.map(\.persistentModelID)) { _, ids in
                    // A series deleted on another device while open here
                    // can't be read any more; fall back to the library.
                    if let selectedManga, !ids.contains(selectedManga.persistentModelID) {
                        self.selectedManga = nil
                        lastClosedManga = nil
                    }
                }
            }
            .frame(minWidth: 1100, minHeight: 600)
            .toolbarBackground(.hidden, for: .windowToolbar)

            ToastOverlayView(toastService: toastService)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheetView(
                backupReminderIntervalDays: $backupReminderIntervalDays,
                lastBackupAt: lastBackupAtTimestamp,
                onExport: exportBackup,
                onImport: { isImporting = true }
            )
        }
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
                        modelContext.insert(Manga(exported: em))
                    }

                    do {
                        try modelContext.save()
                        toastService.show(L("Import pomyślny"))
                    } catch {
                        toastService.show(L("Import nieudany: %@", error.localizedDescription))
                    }
                } catch {
                    toastService.show(L("Import nieudany: %@", error.localizedDescription))
                }
            case let .failure(error):
                toastService.show(L("Import nieudany: %@", error.localizedDescription))
            }
        }
    }

    func goBackToLibrary() {
        guard let selectedManga else { return }
        lastClosedManga = selectedManga
        self.selectedManga = nil
    }

    private func reopenLastClosedManga() {
        guard selectedManga == nil, let lastClosedManga,
              mangas.contains(where: { $0.persistentModelID == lastClosedManga.persistentModelID })
        else { return }
        selectedManga = lastClosedManga
    }

    /// Writes the whole library as JSON into the export folder from Ustawienia.
    private func exportBackup() {
        do {
            let data = try encodeMangasToJSON(mangas)
            let filename = "manga-export-\(Date().yyyyMMdd()).json"
            let url = try ExportFolder.withWriteAccess { folder in
                let url = folder.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                return url
            }
            lastBackupAtTimestamp = Date().timeIntervalSince1970
            toastService.show(L("Eksport zapisano: %@", url.path))
        } catch {
            toastService.show(L("Eksport nieudany: %@", error.localizedDescription))
        }
    }

    private func showBackupReminderIfNeeded() {
        guard lastBackupAtTimestamp > 0 else { return }
        let lastBackupDate = Date(timeIntervalSince1970: lastBackupAtTimestamp)
        let daysSinceBackup = Calendar.current.dateComponents([.day], from: lastBackupDate, to: Date()).day ?? 0
        if daysSinceBackup >= backupReminderIntervalDays {
            toastService.show(L("Minęło %lld dni od ostatniego backupu. Warto wykonać eksport.", daysSinceBackup))
        }
    }
}
