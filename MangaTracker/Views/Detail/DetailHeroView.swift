import AppKit
import SwiftUI

/// Top of the detail page: full-bleed banner fading into the page, the
/// cover overlapping its bottom edge, editable title/author, metadata pills
/// and the AniList actions.
struct DetailHeroView: View {
    @Bindable var manga: Manga

    @FocusState private var titleFocused: Bool
    @State private var isRefreshingAniList = false
    @State private var isFetchingRecommendations = false
    @State private var isFetchingCover = false
    @State private var recommendations: [AniListRecommendation] = []
    @State private var showRecommendationsSheet = false
    @State private var showCoverPopover = false

    /// Placeholder titles a new series gets, in either language.
    private let defaultTitles: Set<String> = ["Nowa manga", "New manga"]
    private let bannerHeight: CGFloat = 300
    private let contentTop: CGFloat = 176
    private let coverWidth: CGFloat = 188
    private let horizontalPadding: CGFloat = 28

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
        ZStack(alignment: .topLeading) {
            banner
                .frame(height: bannerHeight)
                .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 26) {
                cover
                info
                    .padding(.bottom, 6)
            }
            .padding(.top, contentTop)
            .padding(.horizontal, horizontalPadding)

            actions
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.top, 18)
                .padding(.trailing, horizontalPadding)
        }
        .sheet(isPresented: $showRecommendationsSheet) {
            RecommendationsSheetView(
                sourceTitle: manga.title,
                bannerURL: (manga.bannerImage ?? "").isEmpty ? nil : URL(string: manga.bannerImage ?? ""),
                recommendations: recommendations
            )
        }
    }

    // MARK: - Banner

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
                        endRadius: 700
                    )
                }

                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.7),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.5, y: 0.5)
                )
                LinearGradient(
                    colors: [.clear, Color(red: 0.055, green: 0.06, blue: 0.07)],
                    startPoint: UnitPoint(x: 0.5, y: 0.35),
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Cover

    private var cover: some View {
        Color.clear
            .frame(width: coverWidth, height: coverHeight)
            .overlay(
                CoverImageView(url: URL(string: manga.coverURL ?? ""), cornerRadius: 14)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if manga.isSold ?? false {
                        badge("Sprzedane", color: .red)
                    }
                    if manga.isSpinOff ?? false {
                        badge("Spin-off", color: .gray)
                    }
                    if manga.isPlanned ?? false {
                        badge("Planowana", color: .blue)
                    }
                }
                .padding(8)
            }
    }

    private func badge(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    // MARK: - Title & metadata

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Tytuł", text: $manga.title)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($titleFocused)
                .onChange(of: titleFocused) { _, focused in
                    if focused, defaultTitles.contains(manga.title) {
                        manga.title = ""
                    }
                }

            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Autor",
                    text: Binding(
                        get: { manga.aniListAuthor ?? "" },
                        set: { manga.aniListAuthor = $0.isEmpty ? nil : $0 }
                    )
                )
                .font(.subheadline.weight(.medium))
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
            }

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
            .padding(.top, 4)

            if !genres.isEmpty {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            GlassButton(
                title: "Odśwież z AniList",
                systemImage: "arrow.clockwise",
                isLoading: isRefreshingAniList
            ) {
                Task { await refreshAniListInfo() }
            }
            .disabled(isRefreshingAniList || manga.title.trimmingCharacters(in: .whitespaces).isEmpty)

            GlassButton(
                title: "Rekomendacje",
                systemImage: "sparkles",
                isLoading: isFetchingRecommendations
            ) {
                if recommendations.isEmpty {
                    Task { await fetchRecommendations() }
                } else {
                    showRecommendationsSheet = true
                }
            }
            .disabled(isFetchingRecommendations || manga.aniListId == nil)
            .tooltip(manga.aniListId == nil ? "Najpierw odśwież dane z AniList" : nil)

            FavoriteHeartButton(manga: manga, size: 30)

            Menu {
                if !(manga.isPlanned ?? false) {
                    Toggle("Sprzedane", isOn: Binding(
                        get: { manga.isSold ?? false },
                        set: { manga.isSold = $0 }
                    ))
                }
                Toggle("Spin-off", isOn: Binding(
                    get: { manga.isSpinOff ?? false },
                    set: { manga.isSpinOff = $0 }
                ))
                Toggle("Planowana", isOn: Binding(
                    get: { manga.isPlanned ?? false },
                    set: { manga.isPlanned = $0 }
                ))
                Divider()
                Button("Zmień okładkę…") {
                    showCoverPopover = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .background(.ultraThinMaterial, in: Circle())
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $showCoverPopover, arrowEdge: .bottom) {
                coverPopover
            }
        }
    }

    private var coverPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Okładka")
                .font(.headline)

            TextField(
                "https://…",
                text: Binding(
                    get: { manga.coverURL ?? "" },
                    set: { manga.coverURL = $0.isEmpty ? nil : $0 }
                )
            )
            .detailInput()

            Text("Wklej link do obrazka (jpg, png, webp). Miniatura zostanie zapisana lokalnie.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                SubtleButton(title: "Pobierz z AniList", systemImage: "arrow.down.circle") {
                    Task { await fetchCoverFromAniList() }
                }
                .disabled(isFetchingCover)

                Spacer()

                Button("Gotowe") { showCoverPopover = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
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

            // AniList has a cover for the series only, so the volumes it just
            // created are filled from MangaDex. A failure here is silent: the
            // series data is already in, and the volume list has a menu item
            // to try the covers again.
            _ = try? await manga.fetchVolumeCovers()

            ToastService.shared.show(L("Dane z AniList odświeżone dla %@.", title), type: .success)
        } catch {
            ToastService.shared.show(L("Nie udało się odświeżyć danych z AniList."), type: .error)
            print("AniList refresh error:", error)
        }
    }

    private func fetchCoverFromAniList() async {
        let title = manga.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            ToastService.shared.show(L("Najpierw wpisz tytuł mangi."), type: .error)
            return
        }

        isFetchingCover = true
        defer { isFetchingCover = false }

        do {
            if let url = try await AniListService.fetchMangaCoverURL(title: title) {
                manga.coverURL = url
                ToastService.shared.show(L("Okładka pobrana z AniList."), type: .success)
            } else {
                ToastService.shared.show(L("Nie znaleziono okładki dla: %@", title), type: .error)
            }
        } catch {
            ToastService.shared.show(L("Nie udało się pobrać okładki."), type: .error)
            print("AniList error:", error)
        }
    }

    private func fetchRecommendations() async {
        guard let mangaId = manga.aniListId else {
            ToastService.shared.show(L("Najpierw odśwież dane z AniList."), type: .error)
            return
        }

        isFetchingRecommendations = true
        defer { isFetchingRecommendations = false }

        do {
            let results = try await AniListService.fetchMangaRecommendations(mangaId: mangaId)
            recommendations = results
            if results.isEmpty {
                ToastService.shared.show(L("Brak rekomendacji do pokazania."), type: .info)
                return
            }
            showRecommendationsSheet = true
        } catch {
            ToastService.shared.show(L("Nie udało się pobrać rekomendacji."), type: .error)
            print("AniList recommendations error:", error)
        }
    }
}
