import AppKit
import SwiftData
import SwiftUI

/// AniList's recommendations for one series: a banner header like the
/// library's, then a grid of cards. Series already in the library are
/// marked and can be filtered out.
struct RecommendationsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var mangas: [Manga]

    /// The series these recommendations are for.
    let sourceTitle: String
    let bannerURL: URL?
    let recommendations: [AniListRecommendation]

    @State private var showsOnlyNew = false

    private let horizontalPadding: CGFloat = 28

    /// AniList ids of everything already tracked.
    private var libraryIDs: Set<Int> {
        Set(mangas.compactMap(\.aniListId))
    }

    var body: some View {
        let libraryIDs = libraryIDs
        let newOnes = recommendations.filter { !libraryIDs.contains($0.id) }
        let shown = showsOnlyNew ? newOnes : recommendations

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header(newCount: newOnes.count)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 215), spacing: 14)],
                    spacing: 16
                ) {
                    ForEach(shown) { recommendation in
                        RecommendationCard(
                            recommendation: recommendation,
                            isInLibrary: libraryIDs.contains(recommendation.id),
                            onAddToPlanned: { await addToPlanned(recommendation) }
                        )
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .background(AppBackgroundView())
        .background {
            // Invisible: Esc closes the sheet.
            Button("Zamknij") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Adding

    /// Creates the series on the wishlist with everything AniList knows
    /// about it. The recommendation alone has enough for a card; the
    /// lookup adds author, banner, synopsis and dates, and is skipped
    /// gracefully when it fails.
    private func addToPlanned(_ recommendation: AniListRecommendation) async {
        var info: AniListMangaInfo?
        do {
            info = try await AniListService.fetchMangaInfo(id: recommendation.id)
        } catch {
            print("AniList lookup failed for \(recommendation.id):", error)
        }

        let nextOrder = (mangas.compactMap(\.sortOrder).max() ?? -1) + 1
        let manga = Manga(
            title: recommendation.displayTitle,
            summary: info?.description ?? "",
            coverUrl: info?.coverURL ?? recommendation.coverImageLarge ?? recommendation.coverImageMedium,
            sortOrder: nextOrder,
            aniListId: recommendation.id,
            aniListStatus: info?.status ?? recommendation.status,
            aniListAverageScore: info?.averageScore ?? recommendation.averageScore,
            aniListStartDate: info?.startDate,
            aniListEndDate: info?.endDate,
            aniListGenresRaw: (info?.genres ?? recommendation.genres).joined(separator: ", "),
            aniListAuthor: info?.author,
            bannerImage: info?.bannerImage ?? "",
            aniListParentId: info?.parentId,
            isSpinOff: info?.parentId != nil,
            isPlanned: true
        )

        let totalVolumes = info?.volumes ?? recommendation.volumes ?? 0
        if totalVolumes > 0 {
            manga.volumes = (1 ... totalVolumes).map { number in
                let volume = Volume(number: number, owned: false)
                volume.manga = manga
                return volume
            }
        }

        modelContext.insert(manga)
        ToastService.shared.show(L("Dodano do planowanych: %@", manga.title), type: .success)
    }

    // MARK: - Header

    private func header(newCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rekomendacje")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Podobne do \(sourceTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                GlassButton(title: "Zamknij", systemImage: "xmark") { dismiss() }
            }

            HStack(spacing: 6) {
                FilterChip(title: "Wszystkie", count: recommendations.count, isSelected: !showsOnlyNew) {
                    showsOnlyNew = false
                }
                FilterChip(title: "Tylko nowe", systemImage: "sparkles", count: newCount, isSelected: showsOnlyNew) {
                    showsOnlyNew = true
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background { bannerBackground }
    }

    private var bannerBackground: some View {
        GeometryReader { proxy in
            ZStack {
                if let bannerURL {
                    BannerImageView(url: bannerURL, size: proxy.size)
                } else {
                    RadialGradient(
                        colors: [Color.green.opacity(0.22), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 700
                    )
                }

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
                    startPoint: UnitPoint(x: 0.5, y: 0.4),
                    endPoint: .bottom
                )
            }
        }
    }
}

// MARK: - Card

/// One recommended series, styled like the library grid card: cover with
/// the AniList score, title, status and volumes, genres and upvotes.
/// Clicking opens the series on AniList.
private struct RecommendationCard: View {
    let recommendation: AniListRecommendation
    let isInLibrary: Bool
    let onAddToPlanned: () async -> Void

    @State private var isHovered = false
    @State private var isAdding = false

    private static let cornerRadius: CGFloat = 14

    /// Set only when the series isn't a regular manga.
    private var formatLabel: String? {
        switch recommendation.format {
        case "NOVEL": "Light novel"
        case "ONE_SHOT": "One-shot"
        default: recommendation.type == "ANIME" ? "Anime" : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                cover

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2, reservesSpace: true)

                    HStack(spacing: 4) {
                        if let status = recommendation.status {
                            Text(formatAniListStatus(status))
                        }
                        if let volumes = recommendation.volumes, volumes > 0 {
                            if recommendation.status != nil {
                                Text(verbatim: "·")
                            }
                            Text("\(volumes) tomów")
                        } else if let year = recommendation.startYear {
                            if recommendation.status != nil {
                                Text(verbatim: "·")
                            }
                            Text(verbatim: String(year))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(recommendation.genres.prefix(2).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let rating = recommendation.rating {
                            Label("\(rating)", systemImage: "heart.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .help("Tyle osób poleca tę serię")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openOnAniList)
            .help("Otwórz w AniList")

            addButton
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.07), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.35 : 0),
            radius: isHovered ? 14 : 0,
            y: isHovered ? 8 : 0
        )
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    /// Adds to the wishlist; once the series is in the library the row
    /// turns into a quiet confirmation.
    @ViewBuilder
    private var addButton: some View {
        if isInLibrary {
            Label("W bibliotece", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, minHeight: 28)
        } else {
            Button {
                isAdding = true
                Task {
                    await onAddToPlanned()
                    isAdding = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "bookmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("Do planowanych")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.blue)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(isHovered ? 0.24 : 0.16))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
            .help("Dodaj serię do listy planowanych")
        }
    }

    /// 2:3 cover with the score bottom-left, a library/format badge
    /// top-right, and an "AniList" hint that appears on hover.
    private var cover: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay(
                CoverImageView(
                    url: URL(string: recommendation.coverImageLarge ?? recommendation.coverImageMedium ?? ""),
                    cornerRadius: 10
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let score = recommendation.averageScore {
                    Label("\(score)%", systemImage: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if isInLibrary {
                        badge(Text("W bibliotece"), systemImage: "checkmark", color: .green)
                    }
                    if let formatLabel {
                        badge(Text(verbatim: formatLabel), color: .gray)
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovered {
                    Label("AniList", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .padding(8)
                        .transition(.opacity)
                }
            }
    }

    private func badge(_ text: Text, systemImage: String? = nil, color: Color) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            text
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(color == .gray ? .white : Color.black.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.95), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func openOnAniList() {
        guard let urlString = recommendation.siteUrl, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension AniListRecommendation {
    /// English first, matching how series are named in the library.
    var displayTitle: String {
        title.english
            ?? title.userPreferred
            ?? title.romaji
            ?? title.native
            ?? ""
    }
}
