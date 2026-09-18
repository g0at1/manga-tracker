import SwiftUI

/// Home screen: banner header with stats, a "continue reading" row, and
/// the whole collection as a filterable grid. Tapping a card opens
/// `MangaDetailView`.
struct LibraryView: View {
    /// Everything in the library, used for stats and the featured banner.
    let allMangas: [Manga]
    /// What the grid shows after category, spin-off and search filtering.
    let filteredMangas: [Manga]
    /// Series per section, for the filter chips.
    let categoryCounts: [LibraryCategory: Int]

    @Binding var selectedManga: Manga?
    @Binding var category: LibraryCategory
    @Binding var searchText: String
    @Binding var draggedManga: Manga?
    @Binding var sortOptionRaw: String
    @Binding var sortAscending: Bool
    @Binding var hideSpinOffs: Bool

    let isReorderable: Bool
    /// Picks which series' banner sits behind the header; fixed for the app's lifetime.
    let bannerSeed: Int

    let onAddManga: () -> Void
    let onDeleteManga: (Manga) -> Void
    let onMoveMangaUp: (Manga) -> Void
    let onMoveMangaDown: (Manga) -> Void
    let onMoveMangaInGrid: (Manga, Manga) -> Void
    let onMarkNextAsRead: (Manga) -> Void
    let onToggleSold: (Manga) -> Void
    let onToggleSpinOff: (Manga) -> Void

    @FocusState private var searchFocused: Bool
    @Environment(\.locale) private var locale

    private let horizontalPadding: CGFloat = 28

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                header

                if showsContinueReading, !continueReading.isEmpty {
                    continueReadingSection
                }

                allSeriesSection
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
        .onTapGesture {
            // Clicking anywhere that isn't a control takes focus off the search field.
            blurSearch()
        }
        .onAppear {
            // macOS hands first-responder status to the first text field in the
            // window; give it back so the search field doesn't start focused.
            DispatchQueue.main.async(execute: blurSearch)
        }
        .onChange(of: category) { _, _ in
            blurSearch()
        }
        .background {
            // Invisible: ⌘K focuses the search field.
            Button("Szukaj") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func blurSearch() {
        searchFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: - Derived data

    private var stats: MangaLibraryStats {
        MangaLibraryStats(mangas: allMangas)
    }

    /// Series with an owned volume still unread, most recently read first.
    private var continueReading: [Manga] {
        allMangas
            .compactMap { manga -> (manga: Manga, lastRead: Date)? in
                guard manga.isSold != true, !hideSpinOffs || manga.isSpinOff != true else { return nil }
                let stats = manga.volumeStats
                guard stats.nextUnread != nil else { return nil }
                return (manga, stats.lastReadDate ?? .distantPast)
            }
            .sorted { $0.lastRead > $1.lastRead }
            .prefix(8)
            .map(\.manga)
    }

    private var showsContinueReading: Bool {
        category == .all && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Banner behind the header: a random series that has one, different on every launch.
    private var featuredManga: Manga? {
        let candidates = allMangas
            .filter { !($0.bannerImage ?? "").isEmpty }
            .sorted { $0.title < $1.title }
        guard !candidates.isEmpty else { return nil }
        return candidates[bannerSeed % candidates.count]
    }

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortOptionRaw) ?? .manual
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Biblioteka")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Twoje mangi w jednym miejscu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    searchField
                        .frame(width: 300)

                    addButton
                }
            }

            HStack(spacing: 12) {
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

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background { bannerBackground }
    }

    private var bannerBackground: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if let featured = featuredManga,
                   let url = URL(string: featured.bannerImage ?? "")
                {
                    BannerImageView(url: url, size: proxy.size)

                    // Fade into the page on the left and at the bottom.
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.06, blue: 0.07),
                            Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.6),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [.clear, Color(red: 0.055, green: 0.06, blue: 0.07)],
                        startPoint: UnitPoint(x: 0.5, y: 0.55),
                        endPoint: .bottom
                    )

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\u{201C}A good story stays with you.\u{201D}")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.8))
                        Text(featured.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 28)
                    .padding(.trailing, horizontalPadding + 8)
                }
            }
        }
    }

    private var addButton: some View {
        Button(action: onAddManga) {
            HStack(spacing: 8) {
                Label("Dodaj mangę", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))

                Text("⌘N")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("Dodaj nową serię (⌘N)")
        .shadow(color: .green.opacity(0.35), radius: 10, y: 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Szukaj tytułu…").foregroundStyle(.white.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .focused($searchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘K")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.8))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(searchFocused ? 0.4 : 0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    // MARK: - Continue reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                category = .inProgress
            } label: {
                HStack(spacing: 8) {
                    Text("Kontynuuj czytanie")
                        .font(.title3.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(continueReading) { manga in
                        ContinueReadingCardView(manga: manga) {
                            selectedManga = manga
                        }
                        .contextMenu {
                            Button("Oznacz kolejny tom jako przeczytany") {
                                onMarkNextAsRead(manga)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - All series

    private var allSeriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category == .all ? "Wszystkie serie" : category.label)
                    .font(.title3.weight(.bold))
                Text("(\(filteredMangas.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                categoryChips
                Spacer(minLength: 12)
                sortMenu
                filterMenu
            }

            if allMangas.isEmpty {
                ContentUnavailableView {
                    Label("Pusta biblioteka", systemImage: "books.vertical")
                } description: {
                    Text("Dodaj pierwszą serię, żeby zacząć śledzić kolekcję.")
                } actions: {
                    Button("Dodaj mangę", action: onAddManga)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if filteredMangas.isEmpty {
                ContentUnavailableView(
                    "Brak wyników",
                    systemImage: "magnifyingglass",
                    description: Text("Żadna seria nie pasuje do wybranych filtrów.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            ForEach(LibraryCategory.allCases) { section in
                FilterChip(
                    title: section.chipLabel,
                    systemImage: section.systemImage,
                    count: categoryCounts[section, default: 0],
                    isSelected: category == section
                ) {
                    category = section
                }
            }
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
        } label: {
            HStack(spacing: 6) {
                Text("Sortuj:")
                Text(sortOption.label)
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.semibold))
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(isReorderable ? L("Własna kolejność: przeciągnij okładki, aby zmienić kolejność") : "")
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Ukryj spin-offy", isOn: $hideSpinOffs)
        } label: {
            Label(
                hideSpinOffs ? "Filtry (1)" : "Filtry",
                systemImage: hideSpinOffs
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(hideSpinOffs ? .green : .primary)
    }
}
