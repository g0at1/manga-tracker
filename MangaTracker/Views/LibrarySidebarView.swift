import SwiftUI

struct LibrarySidebarView: View {
    let filteredMangas: [Manga]

    @Binding var selectedManga: Manga?
    @Binding var searchText: String
    @Binding var draggedManga: Manga?
    @Binding var sortOptionRaw: String
    @Binding var sortAscending: Bool
    @Binding var showUnreadOnly: Bool
    @Binding var hideSold: Bool
    @Binding var hideSpinOffs: Bool

    let viewMode: LibraryViewMode
    let isReorderable: Bool

    let onToggleViewMode: () -> Void
    let onAddManga: () -> Void
    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangas: (IndexSet, Int) -> Void
    let onMoveMangaInGrid: (Manga, Manga) -> Void
    let onMarkNextAsRead: (Manga) -> Void
    let onToggleSold: (Manga) -> Void
    let onToggleSpinOff: (Manga) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                searchField
                filterSortBar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            Group {
                if viewMode == .list {
                    MangaListView(
                        mangas: filteredMangas,
                        selectedManga: $selectedManga,
                        onDeleteManga: onDeleteManga,
                        onMoveMangaUp: onMoveMangaUp,
                        onMoveMangaDown: onMoveMangaDown,
                        onMoveMangas: onMoveMangas,
                        onMarkNextAsRead: onMarkNextAsRead,
                        onToggleSold: onToggleSold,
                        isReorderable: isReorderable
                    )
                } else {
                    MangaGridView(
                        mangas: filteredMangas,
                        selectedManga: $selectedManga,
                        draggedManga: $draggedManga,
                        onDeleteManga: onDeleteManga,
                        onMoveMangaUp: onMoveMangaUp,
                        onMoveMangaDown: onMoveMangaDown,
                        onMoveMangaInGrid: onMoveMangaInGrid,
                        onMarkNextAsRead: onMarkNextAsRead,
                        onToggleSold: onToggleSold,
                        onToggleSpinOff: onToggleSpinOff,
                        isReorderable: isReorderable
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
    }

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .manual
    }

    private var activeFilterCount: Int {
        [showUnreadOnly, hideSold, hideSpinOffs].filter { $0 }.count
    }

    private var filterSortBar: some View {
        HStack(spacing: 8) {
            Menu {
                Toggle("Tylko nieprzeczytane", isOn: $showUnreadOnly)
                Toggle("Ukryj sprzedane", isOn: $hideSold)
                Toggle("Ukryj spin-offy", isOn: $hideSpinOffs)
                if activeFilterCount > 0 {
                    Divider()
                    Button("Wyczyść filtry") {
                        showUnreadOnly = false
                        hideSold = false
                        hideSpinOffs = false
                    }
                }
            } label: {
                Label(
                    activeFilterCount > 0 ? "Filtry (\(activeFilterCount))" : "Filtry",
                    systemImage: activeFilterCount > 0
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .tint(activeFilterCount > 0 ? .green : .primary)

            Menu {
                Picker("Sortuj", selection: $sortOptionRaw) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Label(option.label, systemImage: option.systemImage)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sortuj: \(sortOption.label)", systemImage: sortOption.systemImage)
            }

            Spacer(minLength: 0)

            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
            }
            .help(sortAscending ? "Rosnąco" : "Malejąco")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Szukaj tytułu…", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
