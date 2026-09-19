import SwiftData
import SwiftUI

/// Home screen: stat tiles, category chips and the collection as a grid.
/// Tapping a card pushes `MangaDetailScreen`.
struct LibraryScreen: View {
    let mangas: [Manga]
    @Binding var path: [Manga]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @AppStorage("librarySortOption") private var sortOptionRaw: String = LibrarySortOption.manual.rawValue
    @AppStorage("librarySortAscending") private var sortAscending: Bool = true
    @AppStorage("libraryCategory") private var categoryRaw: String = LibraryCategory.all.rawValue
    @AppStorage("libraryHideSpinOffs") private var hideSpinOffs = false

    @State private var searchText = ""
    @State private var isAddingManga = false
    @State private var isShowingSettings = false
    @State private var mangaToDelete: Manga?

    private let horizontalPadding: CGFloat = 16

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .manual
    }

    private var category: LibraryCategory {
        LibraryCategory(rawValue: categoryRaw) ?? .all
    }

    private var filteredMangas: [Manga] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = mangas.filter { manga in
            (!hideSpinOffs || manga.isSpinOff != true)
                && (query.isEmpty || manga.title.localizedCaseInsensitiveContains(query))
                && category.contains(manga)
        }
        let sorted = sortOption.sorted(matching)
        return sortAscending ? sorted : sorted.reversed()
    }

    /// Series per section for the chips, from one pass over the library.
    private var categoryCounts: [LibraryCategory: Int] {
        var counts: [LibraryCategory: Int] = [:]
        for manga in mangas where !hideSpinOffs || manga.isSpinOff != true {
            let stats = manga.volumeStats
            for section in LibraryCategory.allCases where section.contains(manga, stats: stats) {
                counts[section, default: 0] += 1
            }
        }
        return counts
    }

    private var stats: MangaLibraryStats {
        MangaLibraryStats(mangas: mangas)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                statsStrip
                categoryChips
                grid
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppBackgroundView())
        .navigationTitle("Biblioteka")
        .searchable(text: $searchText, prompt: "Szukaj tytułu…")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Ustawienia", systemImage: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortMenu
                Button {
                    isAddingManga = true
                } label: {
                    Label("Dodaj mangę", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingManga) {
            AddMangaSheet(nextSortOrder: (mangas.compactMap(\.sortOrder).max() ?? -1) + 1) { manga in
                path.append(manga)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen()
        }
        .confirmationDialog(
            "Usunąć tę serię?",
            isPresented: Binding(
                get: { mangaToDelete != nil },
                set: {
                    if !$0 {
                        mangaToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: mangaToDelete
        ) { manga in
            Button("Usuń", role: .destructive) { delete(manga) }
            Button("Anuluj", role: .cancel) {}
        } message: { manga in
            Text("„\(manga.title)” i wszystkie jej tomy zostaną usunięte także na pozostałych urządzeniach.")
        }
    }

    // MARK: - Header

    private var statsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatCardView(
                    title: "serii",
                    value: "\(stats.mangaCount)",
                    systemImage: "books.vertical.fill",
                    accentColor: .blue
                )
                StatCardView(
                    title: "tomów",
                    value: "\(stats.ownedVolumesCount)",
                    systemImage: "square.stack.3d.up.fill",
                    accentColor: .green
                )
                StatCardView(
                    title: "przeczytane",
                    value: stats.totalReadPercent.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%",
                    systemImage: "circle.dashed.inset.filled",
                    accentColor: .green
                )
                StatCardView(
                    title: "łączna wartość",
                    value: stats.totalPaid.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                    systemImage: "wallet.pass.fill",
                    accentColor: .yellow,
                    unit: "PLN"
                )
                StatCardView(
                    title: "streak",
                    value: L("%lld dni", stats.currentReadStreak),
                    systemImage: stats.didReadToday ? "flame.fill" : "flame",
                    accentColor: stats.didReadToday ? .orange : .gray
                )
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryCategory.allCases) { section in
                    FilterChip(
                        title: section.chipLabel,
                        systemImage: section.systemImage,
                        count: categoryCounts[section, default: 0],
                        isSelected: category == section
                    ) {
                        categoryRaw = section.rawValue
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortuj", selection: $sortOptionRaw) {
                ForEach(LibrarySortOption.allCases) { option in
                    Label(option.label, systemImage: option.systemImage)
                        .tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Kierunek", selection: $sortAscending) {
                Label("Rosnąco", systemImage: "arrow.up").tag(true)
                Label("Malejąco", systemImage: "arrow.down").tag(false)
            }
            .pickerStyle(.inline)

            Divider()

            Toggle("Ukryj spin-offy", isOn: $hideSpinOffs)
        } label: {
            Label("Sortuj", systemImage: hideSpinOffs ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category == .all ? "Wszystkie serie" : category.label)
                    .font(.title3.weight(.bold))
                Text("(\(filteredMangas.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if mangas.isEmpty {
                ContentUnavailableView {
                    Label("Pusta biblioteka", systemImage: "books.vertical")
                } description: {
                    Text("Dodaj pierwszą serię, żeby zacząć śledzić kolekcję.")
                } actions: {
                    Button("Dodaj mangę") { isAddingManga = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .padding(.vertical, 40)
            } else if filteredMangas.isEmpty {
                ContentUnavailableView(
                    "Brak wyników",
                    systemImage: "magnifyingglass",
                    description: Text("Żadna seria nie pasuje do wybranych filtrów.")
                )
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(filteredMangas) { manga in
                        NavigationLink(value: manga) {
                            MangaCardView(manga: manga)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: manga) }
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    @ViewBuilder
    private func contextMenu(for manga: Manga) -> some View {
        if manga.volumeStats.nextUnread != nil {
            Button("Oznacz kolejny tom jako przeczytany", systemImage: "checkmark.circle") {
                manga.markNextAsRead()
            }
        }
        Button(
            manga.isFavorite == true ? "Usuń z ulubionych" : "Dodaj do ulubionych",
            systemImage: manga.isFavorite == true ? "heart.slash" : "heart"
        ) {
            manga.isFavorite = !(manga.isFavorite ?? false)
        }
        Toggle("Planowana", systemImage: "bookmark", isOn: Binding(
            get: { manga.isPlanned ?? false },
            set: { manga.isPlanned = $0 }
        ))
        Toggle("Sprzedane", systemImage: "tag", isOn: Binding(
            get: { manga.isSold ?? false },
            set: { manga.isSold = $0 }
        ))
        Toggle("Spin-off", systemImage: "arrow.triangle.branch", isOn: Binding(
            get: { manga.isSpinOff ?? false },
            set: { manga.isSpinOff = $0 }
        ))
        Divider()
        Button("Usuń serię", systemImage: "trash", role: .destructive) {
            mangaToDelete = manga
        }
    }

    private func delete(_ manga: Manga) {
        path.removeAll { $0.persistentModelID == manga.persistentModelID }
        modelContext.delete(manga)
    }
}
