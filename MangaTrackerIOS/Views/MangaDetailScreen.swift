import SwiftData
import SwiftUI

/// One series: banner hero, stats and progress, the volumes list, then the
/// add-volumes form, note and synopsis.
struct MangaDetailScreen: View {
    @Bindable var manga: Manga

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var isRefreshingAniList = false
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var hoveredRating: Double?

    private let horizontalPadding: CGFloat = 16

    var body: some View {
        // A series deleted underneath an open page (sync) can't be read;
        // `RootView` pops it, this just avoids touching it until then.
        if manga.isDeleted {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeaderView(manga: manga)

                VStack(alignment: .leading, spacing: 18) {
                    actions
                    statsStrip
                    progressCard
                    VolumesListView(manga: manga)
                    DetailSidePanelView(manga: manga)
                }
                .padding(.horizontal, horizontalPadding)
            }
            .padding(.bottom, 32)
        }
        .background(AppBackgroundView())
        .navigationTitle(manga.title.isEmpty ? "Szczegóły" : manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edytuj tytuł i okładkę…", systemImage: "pencil") { isEditing = true }
                    Divider()
                    if !(manga.isPlanned ?? false) {
                        Toggle("Sprzedane", systemImage: "tag", isOn: Binding(
                            get: { manga.isSold ?? false },
                            set: { manga.isSold = $0 }
                        ))
                    }
                    Toggle("Spin-off", systemImage: "arrow.triangle.branch", isOn: Binding(
                        get: { manga.isSpinOff ?? false },
                        set: { manga.isSpinOff = $0 }
                    ))
                    Toggle("Planowana", systemImage: "bookmark", isOn: Binding(
                        get: { manga.isPlanned ?? false },
                        set: { manga.isPlanned = $0 }
                    ))
                    Divider()
                    Button("Usuń serię", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Label("Więcej", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditMangaSheet(manga: manga)
        }
        .confirmationDialog("Usunąć tę serię?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                dismiss()
                modelContext.delete(manga)
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("„\(manga.title)” i wszystkie jej tomy zostaną usunięte także na pozostałych urządzeniach.")
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            GlassButton(
                title: "Odśwież z AniList",
                systemImage: "arrow.clockwise",
                isLoading: isRefreshingAniList
            ) {
                Task { await refreshAniListInfo() }
            }
            .disabled(isRefreshingAniList || manga.title.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer(minLength: 0)

            Button {
                manga.isFavorite = !(manga.isFavorite ?? false)
            } label: {
                Image(systemName: manga.isFavorite == true ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(manga.isFavorite == true ? Color.red : .white.opacity(0.92))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .background(.ultraThinMaterial, in: Circle())
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: manga.isFavorite)
        }
    }

    // MARK: - Stats

    private var statsStrip: some View {
        let stats = manga.volumeStats

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatCardView(title: "tomów", value: "\(stats.total)", systemImage: "books.vertical.fill", accentColor: .blue)
                StatCardView(title: "kupionych", value: "\(stats.owned)", systemImage: "cart.fill", accentColor: .green)
                StatCardView(title: "przeczytanych", value: "\(stats.read)", systemImage: "checkmark.circle.fill", accentColor: .green)
                StatCardView(
                    title: "wydano",
                    value: stats.totalPaid.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                    systemImage: "wallet.pass.fill",
                    accentColor: .yellow,
                    unit: "PLN"
                )
            }
        }
        .scrollClipDisabled()
    }

    private var progressCard: some View {
        let stats = manga.volumeStats
        let completion = stats.readPercent / 100

        return DetailCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Postęp czytania")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(stats.read) / \(stats.total) · \(Int(stats.readPercent.rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Color.green)
                            .frame(width: max(0, geo.size.width * completion))
                            .shadow(color: .green.opacity(0.5), radius: 6)
                    }
                }
                .frame(height: 8)
                .animation(.easeOut(duration: 0.25), value: completion)

                nextStep(stats)

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    StarRatingView(
                        rating: Binding(
                            get: { manga.rating ?? 0 },
                            set: { manga.rating = $0 }
                        ),
                        hoverRating: $hoveredRating,
                        starSize: 22,
                        spacing: 6
                    )
                    Text((manga.rating ?? 0) == 0 ? "—" : String(format: "%.1f", manga.rating ?? 0))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text("twoja ocena")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func nextStep(_ stats: MangaVolumeStats) -> some View {
        if let next = stats.nextUnread {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Następny do przeczytania")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tom \(next.number)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                AccentButton(title: "Przeczytany", systemImage: "checkmark") {
                    next.read = true
                    if next.readDate == nil {
                        next.readDate = .now
                    }
                }
            }
        } else if let missing = stats.firstMissing {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Następny do kupienia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tom \(missing.number)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                SubtleButton(title: "Kupiony", systemImage: "cart") {
                    missing.owned = true
                    if missing.purchaseDate == nil {
                        missing.purchaseDate = .now
                    }
                }
            }
        } else if stats.total == 0 {
            Text("Dodaj tomy poniżej")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label("Wszystkie tomy przeczytane", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
    }

    // MARK: - AniList

    private func refreshAniListInfo() async {
        let title = manga.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            ToastService.shared.show(L("Najpierw wpisz tytuł mangi."), type: .error)
            return
        }

        isRefreshingAniList = true
        defer { isRefreshingAniList = false }

        do {
            guard let info = try await AniListService.fetchMangaInfo(title: title) else {
                ToastService.shared.show(L("Nie znaleziono danych w AniList dla: %@", title), type: .error)
                return
            }
            manga.applyAniListInfo(info)
            ToastService.shared.show(L("Dane z AniList odświeżone dla %@.", title), type: .success)
        } catch {
            ToastService.shared.show(L("Nie udało się odświeżyć danych z AniList."), type: .error)
            print("AniList refresh error:", error)
        }
    }
}

// MARK: - Header

/// Banner fading into the page with the cover overlapping its bottom edge,
/// then title, author, metadata pills and genres.
private struct DetailHeaderView: View {
    let manga: Manga

    private let bannerHeight: CGFloat = 200
    private let coverWidth: CGFloat = 110

    private var coverHeight: CGFloat {
        coverWidth * 1.46
    }

    private var genres: [String] {
        manga.aniListGenresRaw?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                banner
                    .frame(height: bannerHeight)
                    .frame(maxWidth: .infinity)

                cover
                    .padding(.leading, 16)
                    .offset(y: coverHeight * 0.45)
            }
            .padding(.bottom, coverHeight * 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text(manga.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(3)

                if let author = manga.aniListAuthor, !author.isEmpty {
                    Label(author, systemImage: "person.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let status = manga.aniListStatus {
                            MetadataPill(
                                icon: "dot.radiowaves.left.and.right",
                                text: formatAniListStatus(status),
                                tint: .green
                            )
                        }
                        if let score = manga.aniListAverageScore {
                            MetadataPill(icon: "star.fill", text: "\(score)% AniList", tint: .yellow)
                        }
                        if manga.aniListStartDate != nil || manga.aniListEndDate != nil {
                            MetadataPill(icon: "calendar", text: dateRangeText)
                        }
                    }
                }
                .scrollClipDisabled()

                if !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.05), in: Capsule())
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var banner: some View {
        GeometryReader { proxy in
            ZStack {
                if let url = URL(string: manga.bannerImage ?? ""), !(manga.bannerImage ?? "").isEmpty {
                    BannerImageView(url: url, size: proxy.size)
                } else {
                    RadialGradient(
                        colors: [Color.green.opacity(0.22), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 500
                    )
                }

                LinearGradient(
                    colors: [.clear, Color(red: 0.055, green: 0.06, blue: 0.07)],
                    startPoint: UnitPoint(x: 0.5, y: 0.3),
                    endPoint: .bottom
                )
            }
        }
    }

    private var cover: some View {
        Color.clear
            .frame(width: coverWidth, height: coverHeight)
            .overlay(
                CoverImageView(url: URL(string: manga.coverURL ?? ""), cornerRadius: 12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if manga.isSold ?? false {
                        StatusBadge(text: "Sprzedane", color: .red)
                    }
                    if manga.isSpinOff ?? false {
                        StatusBadge(text: "Spin-off", color: .gray)
                    }
                    if manga.isPlanned ?? false {
                        StatusBadge(text: "Planowana", color: .blue)
                    }
                }
                .padding(6)
            }
    }

    private var dateRangeText: String {
        func year(_ date: Date?) -> String {
            guard let date else { return "…" }
            return String(Calendar.current.component(.year, from: date))
        }
        let start = year(manga.aniListStartDate)
        let end = manga.aniListEndDate == nil
            ? (manga.aniListStatus == "RELEASING" ? L("obecnie") : "…")
            : year(manga.aniListEndDate)
        return start == end ? start : "\(start) – \(end)"
    }
}
