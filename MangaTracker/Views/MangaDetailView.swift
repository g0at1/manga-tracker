import AppKit
import SwiftData
import SwiftUI

struct MangaDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var manga: Manga

    @State private var newVolumeNumber = ""
    @State private var bulkFrom = ""
    @State private var bulkTo = ""
    @State private var filterMode: FilterMode = .all
    @State private var showBulkConfirm = false
    @State private var pendingBulkAction: BulkAction?
    @State private var editingDateTarget: EditingDateTarget?
    @State private var selectedVolumeIDs: Set<PersistentIdentifier> = []
    @State private var lastSelectedVolumeID: PersistentIdentifier?
    @State private var showBulkPricePopover = false
    @State private var bulkPriceText = ""
    @State private var showBulkPurchaseDatePopover = false
    @State private var bulkPurchaseDate: Date = .now
    @State private var volumeValidationMessage: String?
    @State private var isFetchingCover = false
    @State private var coverFetchMessage: String?
    @State private var isRefreshingAniList = false
    @State private var aniListMessage: String?
    @State private var summaryHeight: CGFloat = 140
    @State private var isFetchingRecommendations = false
    @State private var recommendationsMessage: String?
    @State private var recommendations: [AniListRecommendation] = []
    @State private var showRecommendationsSheet = false
    @State private var hoveredRating: Double? = nil
    @FocusState private var titleFocused: Bool

    private let defaultTitle = "Nowa manga"

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "Wszystkie"
        case missing = "Brakujące"
        case unread = "Nieprzeczytane"

        var id: String {
            rawValue
        }
    }

    private enum BulkAction {
        case markOwnedUpTo(Volume)
        case markReadUpTo(Volume)
    }

    private enum EditingDateTarget: Identifiable {
        case purchase(Volume)
        case read(Volume)
        case release(Volume)

        var id: String {
            switch self {
            case let .purchase(volume):
                return "purchase-\(volume.persistentModelID)"
            case let .read(volume):
                return "read-\(volume.persistentModelID)"
            case let .release(volume):
                return "release-\(volume.persistentModelID)"
            }
        }
    }

    init(manga: Manga) {
        self.manga = manga
    }

    private var sortedVolumes: [Volume] {
        manga.volumes.sorted { $0.number < $1.number }
    }

    private var displayedVolumes: [Volume] {
        switch filterMode {
        case .all:
            return sortedVolumes
        case .missing:
            return sortedVolumes.filter { !$0.owned }
        case .unread:
            return sortedVolumes.filter { !($0.read ?? false) }
        }
    }

    private var ownedCount: Int {
        manga.volumes.filter(\.owned).count
    }

    private var readCount: Int {
        manga.volumes.filter { $0.read ?? false }.count
    }

    private var totalCount: Int {
        manga.volumes.count
    }

    private var aniListGenres: [String] {
        manga.aniListGenresRaw?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
    }

    private var completionValue: Double {
        guard totalCount > 0 else { return 0 }
        return Double(readCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroSection
            controlsSection
            volumesSection
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(backgroundGradient)
        .foregroundStyle(.primary)
        .navigationTitle(manga.title.isEmpty ? "Szczegóły" : manga.title)
        .confirmationDialog(
            "Zastosować także do poprzednich tomów?",
            isPresented: $showBulkConfirm,
            titleVisibility: .visible
        ) {
            Button("Tak — oznacz wszystkie do tego tomu") {
                applyPendingAction(markPrevious: true)
            }
            Button("Nie — tylko ten tom") {
                applyPendingAction(markPrevious: false)
            }
            Button("Anuluj", role: .cancel) {
                pendingBulkAction = nil
            }
        } message: {
            Text("Możesz oznaczyć tylko ten tom albo wszystkie wcześniejsze.")
        }
        .sheet(item: $editingDateTarget) { target in
            dateEditorSheet(target)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRecommendationsSheet) {
            recommendationsSheet
        }
    }
}

// MARK: - Sections

extension MangaDetailView {
    fileprivate var aniListInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let status = manga.aniListStatus {
                    MetadataPill(
                        icon: "dot.radiowaves.left.and.right",
                        text: formatAniListStatus(status),
                        tint: .green
                    )
                }

                if let score = manga.aniListAverageScore {
                    MetadataPill(
                        icon: "star.fill",
                        text: "\(score)% AniList",
                        tint: .yellow
                    )
                }

                if manga.aniListStartDate != nil || manga.aniListEndDate != nil {
                    MetadataPill(
                        icon: "calendar",
                        text:
                        "\(formattedAniListDate(manga.aniListStartDate)) / \(formattedAniListDate(manga.aniListEndDate))",
                        tint: .secondary
                    )
                }
            }

            if !aniListGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(aniListGenres, id: \.self) { genre in
                            Text(genre)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.06), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let aniListMessage {
                Text(aniListMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    fileprivate var heroSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 34) {
                coverSection
                    .frame(width: 230)
                    .shadow(
                        color: .black.opacity(0.55),
                        radius: 24,
                        x: 0,
                        y: 18
                    )

                VStack(alignment: .leading, spacing: 28) {
                    heroHeader
                    ratingStatsAndProgress
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 20) {
                noteCard
                    .frame(maxWidth: .infinity)

                summaryCard
                    .frame(maxWidth: .infinity)
            }

            //            coverURLSection
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 620, alignment: .topLeading)
        .background {
            heroBackground
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .green.opacity(0.28),
                            .white.opacity(0.08),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
    }

    private var heroBackground: some View {
        GeometryReader { proxy in
            ZStack {
                if let urlString = manga.bannerImage,
                   let url = URL(string: urlString)
                {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                                .clipped()
                                .opacity(0.55)

                        default:
                            Color.clear
                        }
                    }
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.92),
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.25),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.25),
                        Color.black.opacity(0.65),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        .green.opacity(0.12),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 80,
                    endRadius: 700
                )
            }
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Tytuł", text: $manga.title)
                        .font(
                            .system(size: 42, weight: .bold, design: .rounded)
                        )
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                        .frame(
                            minWidth: 420,
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .layoutPriority(2)
                        .focused($titleFocused)
                        .onChange(of: titleFocused) { _, focused in
                            if focused && manga.title == defaultTitle {
                                manga.title = ""
                            }
                        }

                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "Autor",
                            text: Binding(
                                get: { manga.aniListAuthor ?? "" },
                                set: {
                                    manga.aniListAuthor = $0.isEmpty ? nil : $0
                                }
                            )
                        )
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 20)

                Button {
                    Task {
                        await refreshAniListInfo()
                    }
                } label: {
                    if isRefreshingAniList {
                        ProgressView()
                            .scaleEffect(0.75)
                            .frame(width: 130)
                    } else {
                        Label(
                            "Odśwież z AniList",
                            systemImage: "arrow.clockwise"
                        )
                        .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(width: 150)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.green.opacity(0.18), lineWidth: 1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(10)
                .disabled(
                    isRefreshingAniList
                        || manga.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
            aniListInfoSection
            recommendationsActionRow
        }
    }

    private var recommendationsActionRow: some View {
        HStack(spacing: 12) {
            Button {
                if !recommendations.isEmpty {
                    showRecommendationsSheet = true
                } else {
                    Task {
                        await fetchRecommendations()
                    }
                }
            } label: {
                if isFetchingRecommendations {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 170)
                } else {
                    Label(
                        "Rekomendacje",
                        systemImage: "sparkles"
                    )
                    .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 170)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.green.opacity(0.18), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .disabled(isFetchingRecommendations || manga.aniListId == nil)

            if let recommendationsMessage {
                Text(recommendationsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var ratingStatsAndProgress: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Twoja ocena")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        StarRatingView(
                            rating: Binding(
                                get: { manga.rating ?? 0 },
                                set: { manga.rating = $0 }
                            ),
                            hoverRating: $hoveredRating,
                            maxRating: 5,
                            starSize: 26,
                            spacing: 6
                        )

                        let displayRating = hoveredRating ?? (manga.rating ?? 0)

                        Text(
                            displayRating == 0
                                ? "Brak"
                                : String(format: "%.1f / 5", displayRating)
                        )
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 14) {
                    StatBadge(
                        title: "Tomy",
                        value: "\(totalCount)",
                        systemImage: "books.vertical"
                    )

                    StatBadge(
                        title: "Kupione",
                        value: "\(ownedCount)",
                        systemImage: "checkmark.circle"
                    )

                    StatBadge(
                        title: "Przeczytane",
                        value: "\(readCount)",
                        systemImage: "book.closed"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Postęp czytania")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(
                        totalCount == 0
                            ? "0%" : "\(Int(completionValue * 100))%"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.08))

                        Capsule()
                            .fill(
                                Color.green
                            )
                            .frame(width: geo.size.width * completionValue)
                            .shadow(color: .green.opacity(0.55), radius: 8)
                    }
                }
                .frame(height: 10)
            }
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Notatka")
                    .font(.title3.weight(.bold))

                Image(systemName: "pencil")
                    .foregroundStyle(.green)
            }

            TextField(
                "Dodaj krótką notatkę",
                text: $manga.note,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(4 ... 8)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: 170)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "book")
                    .foregroundStyle(.green)

                Text("Opis")
                    .font(.title3.weight(.bold))
            }

            TextEditor(text: $manga.summary.orEmpty())
                .font(.body)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110, maxHeight: 160)
                .overlay(alignment: .topLeading) {
                    if (manga.summary ?? "").isEmpty {
                        Text("Dodaj krótki opis mangi")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(20)
        .frame(minHeight: 170)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    //    private var coverURLSection: some View {
    //        VStack(alignment: .leading, spacing: 8) {
    //            HStack {
    //                Label("URL okładki", systemImage: "link")
    //                    .font(.caption.weight(.semibold))
    //                    .foregroundStyle(.secondary)
    //
    //                Spacer()
    //
    //                Button {
    //                    Task {
    //                        await fetchCoverFromAniList()
    //                    }
    //                } label: {
    //                    if isFetchingCover {
    //                        ProgressView()
    //                            .scaleEffect(0.7)
    //                    } else {
    //                        Label("Pobierz z AniList", systemImage: "arrow.down")
    //                    }
    //                }
    //                .buttonStyle(.plain)
    //                .font(.caption.weight(.bold))
    //                .foregroundStyle(.green)
    //                .disabled(
    //                    isFetchingCover
    //                        || manga.title.trimmingCharacters(
    //                            in: .whitespacesAndNewlines
    //                        ).isEmpty
    //                )
    //            }
    //
    //            TextField(
    //                "https://...",
    //                text: Binding(
    //                    get: { manga.coverURL ?? "" },
    //                    set: { manga.coverURL = $0.isEmpty ? nil : $0 }
    //                )
    //            )
    //            .textFieldStyle(.plain)
    //            .padding(.horizontal, 16)
    //            .padding(.vertical, 13)
    //            .background(
    //                .white.opacity(0.055),
    //                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    //            )
    //            .overlay {
    //                RoundedRectangle(cornerRadius: 12, style: .continuous)
    //                    .stroke(.white.opacity(0.08), lineWidth: 1)
    //            }
    //
    //            Text(
    //                coverFetchMessage
    //                    ?? "Wklej link do obrazka jpg, png albo webp. Miniatura zostanie zcache’owana lokalnie."
    //            )
    //            .font(.caption)
    //            .foregroundStyle(.secondary)
    //        }
    //    }

    private var recommendationsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rekomendacje")
                        .font(.title2.weight(.bold))

                    Text("Znalezione: \(recommendations.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Zamknij") {
                    showRecommendationsSheet = false
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 180, maximum: 220),
                            spacing: 16
                        ),
                    ],
                    spacing: 16
                ) {
                    ForEach(recommendations) { recommendation in
                        recommendationCard(recommendation)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(24)
        .frame(minWidth: 1500, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func recommendationCard(_ recommendation: AniListRecommendation)
        -> some View
    {
        let title =
            recommendation.title.userPreferred
                ?? recommendation.title.english
                ?? recommendation.title.romaji
                ?? recommendation.title.native
                ?? ""
        let imageURL =
            recommendation.coverImageLarge
                ?? recommendation.coverImageMedium
        let scoreText =
            recommendation.averageScore
                .map { "\($0)%" } ?? "—"
        let ratingText =
            recommendation.rating
                .map { "\($0)" } ?? "—"
        let typeText = recommendation.type ?? "MANGA"

        return Button {
            if let urlString = recommendation.siteUrl,
               let url = URL(string: urlString)
            {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))

                    if let imageURL,
                       let url = URL(string: imageURL)
                    {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()

                            default:
                                Color.clear
                            }
                        }
                        .clipped()
                    }
                }
                .frame(width: 150, height: 215)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Label(scoreText, systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)

                        Label(ratingText, systemImage: "heart.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(typeText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            .green.opacity(0.12),
                            in: Capsule()
                        )
                }
                .frame(width: 150, alignment: .leading)
            }
            .padding(12)
            .background(
                .white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    fileprivate var coverSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.04))

            CachedAsyncImage(url: URL(string: manga.coverURL ?? ""))
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .padding(8)
        }
        .frame(width: 170, height: 245)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    fileprivate var controlsSection: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dodaj pojedynczy tom")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField("Nr tomu", text: $newVolumeNumber)
                                .premiumInput(width: 130)
                                .onChange(of: newVolumeNumber) { _, _ in
                                    volumeValidationMessage = nil
                                }
                            if let volumeValidationMessage {
                                Text(volumeValidationMessage)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }

                            Button {
                                addSingleVolume()
                            } label: {
                                Label("Dodaj tom", systemImage: "plus")
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        .green,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        Text("Dodaj zakres tomów")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField("Od", text: $bulkFrom)
                                .premiumInput(width: 90)

                            Text("—")

                            TextField("Do", text: $bulkTo)
                                .premiumInput(width: 90)

                            Button {
                                addBulkVolumes()
                            } label: {
                                Label(
                                    "Dodaj zakres",
                                    systemImage: "square.stack.3d.up"
                                )
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    .white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Tip: możesz dodać od razu np. 1–30")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    fileprivate var volumesSection: some View {
        PremiumCard(padding: 0) {
            VStack(spacing: 0) {
                volumesToolbar

                Divider()
                    .overlay(.white.opacity(0.06))

                if !selectedVolumeIDs.isEmpty {
                    bulkSelectionBar

                    Divider()
                        .overlay(.white.opacity(0.06))
                }

                volumesTableHeader

                Divider()
                    .overlay(.white.opacity(0.08))

                if displayedVolumes.isEmpty {
                    ContentUnavailableView(
                        filterMode == .all ? "Brak tomów" : "Nic do pokazania",
                        systemImage: "books.vertical",
                        description: Text(
                            filterMode == .all
                                ? "Dodaj tomy powyżej."
                                : "Żaden tom nie pasuje do filtra."
                        )
                    )
                    .frame(minHeight: 240)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedVolumes) { volume in
                                volumeRow(volume)

                                Divider()
                                    .overlay(.white.opacity(0.05))
                            }
                        }
                    }
                    .frame(minHeight: 360)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: manga.volumes.count) { _, _ in
            // Drop selections that point at deleted volumes.
            let existing = Set(manga.volumes.map(\.persistentModelID))
            selectedVolumeIDs = selectedVolumeIDs.intersection(existing)
        }
    }

    private var volumesToolbar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tomy")
                        .font(.title3.weight(.bold))

                    Text("\(totalCount) tomów · \(ownedCount) kupionych · \(readCount) przeczytanych")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Widoczne: \(displayedVolumes.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Picker("Filtr", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.green)
                .frame(width: 360)

                Spacer()

                Button {
                    markAllOwned()
                } label: {
                    Label("Kupione wszystkie", systemImage: "checkmark.circle")
                }
                .volumeActionButton()

                Button {
                    markAllRead()
                } label: {
                    Label("Przeczytane wszystkie", systemImage: "book.closed")
                }
                .volumeActionButton()

                Button(role: .destructive) {
                    clearReadProgress()
                } label: {
                    Label(
                        "Wyczyść czytanie",
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .volumeActionButton()
            }
        }
        .padding(20)
    }

    // MARK: Selection & bulk actions

    private var selectedVolumes: [Volume] {
        sortedVolumes.filter { selectedVolumeIDs.contains($0.persistentModelID) }
    }

    private var allDisplayedSelected: Bool {
        !displayedVolumes.isEmpty
            && displayedVolumes.allSatisfy { selectedVolumeIDs.contains($0.persistentModelID) }
    }

    private var bulkSelectionBar: some View {
        HStack(spacing: 8) {
            Text("Zaznaczono: \(selectedVolumeIDs.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            Button("Odznacz") {
                selectedVolumeIDs.removeAll()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                setOwned(true, for: selectedVolumes)
            } label: {
                Label("Kupione", systemImage: "checkmark.circle")
            }
            .volumeActionButton()

            Button {
                setRead(true, for: selectedVolumes)
            } label: {
                Label("Przeczytane", systemImage: "book.closed")
            }
            .volumeActionButton()

            Menu {
                Button("Oznacz jako nie kupione") {
                    setOwned(false, for: selectedVolumes)
                }
                Button("Oznacz jako nieprzeczytane") {
                    setRead(false, for: selectedVolumes)
                }
            } label: {
                Label("Cofnij", systemImage: "arrow.uturn.backward")
            }
            .menuStyle(.borderlessButton)
            .volumeActionButton()

            Button {
                bulkPriceText = ""
                showBulkPricePopover = true
            } label: {
                Label("Cena", systemImage: "banknote")
            }
            .volumeActionButton()
            .popover(isPresented: $showBulkPricePopover, arrowEdge: .bottom) {
                bulkPricePopover
            }

            Button {
                bulkPurchaseDate = .now
                showBulkPurchaseDatePopover = true
            } label: {
                Label("Data zakupu", systemImage: "calendar")
            }
            .volumeActionButton()
            .popover(isPresented: $showBulkPurchaseDatePopover, arrowEdge: .bottom) {
                bulkPurchaseDatePopover
            }

            Button(role: .destructive) {
                for volume in selectedVolumes {
                    deleteVolume(volume)
                }
                selectedVolumeIDs.removeAll()
            } label: {
                Label("Usuń", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .volumeActionButton()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.green.opacity(0.06))
    }

    private var bulkPricePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cena dla \(selectedVolumeIDs.count) tomów")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("0,00", text: $bulkPriceText)
                    .premiumInput(width: 120)
                    .onSubmit(applyBulkPrice)

                Text("PLN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("Tomy, które nie są kupione, zostaną oznaczone jako kupione.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Anuluj") {
                    showBulkPricePopover = false
                }

                Spacer()

                Button("Zastosuj", action: applyBulkPrice)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedBulkPrice == nil)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var parsedBulkPrice: Double? {
        let normalized = bulkPriceText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private func applyBulkPrice() {
        guard let price = parsedBulkPrice else { return }
        for volume in selectedVolumes {
            volume.price = price
            if !volume.owned {
                volume.owned = true
                if volume.purchaseDate == nil {
                    volume.purchaseDate = .now
                }
            }
        }
        showBulkPricePopover = false
    }

    private var bulkPurchaseDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data zakupu dla \(selectedVolumeIDs.count) tomów")
                .font(.headline)

            DatePicker(
                "Data zakupu",
                selection: $bulkPurchaseDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)

            HStack {
                Button("Anuluj") {
                    showBulkPurchaseDatePopover = false
                }

                Spacer()

                Button("Zastosuj") {
                    for volume in selectedVolumes {
                        volume.owned = true
                        volume.purchaseDate = bulkPurchaseDate
                    }
                    showBulkPurchaseDatePopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func setOwned(_ owned: Bool, for volumes: [Volume]) {
        for volume in volumes {
            if owned {
                volume.owned = true
                if volume.purchaseDate == nil {
                    volume.purchaseDate = .now
                }
            } else {
                volume.owned = false
                volume.purchaseDate = nil
                volume.read = false
                volume.readDate = nil
            }
        }
    }

    private func setRead(_ read: Bool, for volumes: [Volume]) {
        for volume in volumes {
            if read {
                volume.owned = true
                volume.read = true
                if volume.purchaseDate == nil {
                    volume.purchaseDate = .now
                }
                if volume.readDate == nil {
                    volume.readDate = .now
                }
            } else {
                volume.read = false
                volume.readDate = nil
            }
        }
    }

    private func toggleSelection(_ volume: Volume) {
        let id = volume.persistentModelID
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isShiftHeld,
           let anchor = lastSelectedVolumeID,
           let anchorIndex = displayedVolumes.firstIndex(where: { $0.persistentModelID == anchor }),
           let targetIndex = displayedVolumes.firstIndex(where: { $0.persistentModelID == id })
        {
            let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
            for volume in displayedVolumes[range] {
                selectedVolumeIDs.insert(volume.persistentModelID)
            }
        } else if selectedVolumeIDs.contains(id) {
            selectedVolumeIDs.remove(id)
        } else {
            selectedVolumeIDs.insert(id)
        }

        lastSelectedVolumeID = id
    }

    private func toggleSelectAllDisplayed() {
        if allDisplayedSelected {
            for volume in displayedVolumes {
                selectedVolumeIDs.remove(volume.persistentModelID)
            }
        } else {
            for volume in displayedVolumes {
                selectedVolumeIDs.insert(volume.persistentModelID)
            }
        }
    }

    private func selectionCheckbox(isOn: Bool, isMixed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(
                systemName: isOn
                    ? "checkmark.square.fill"
                    : (isMixed ? "minus.square.fill" : "square")
            )
            .font(.system(size: 16))
            .foregroundStyle(isOn || isMixed ? Color.green : Color.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Table

    private enum VolumeColumn {
        static let checkbox: CGFloat = 24
        static let number: CGFloat = 48
        static let status: CGFloat = 232
        static let price: CGFloat = 132
        static let date: CGFloat = 104
        static let menu: CGFloat = 28
        static let spacing: CGFloat = 12
    }

    private var volumesTableHeader: some View {
        HStack(spacing: VolumeColumn.spacing) {
            selectionCheckbox(
                isOn: allDisplayedSelected,
                isMixed: !allDisplayedSelected && !selectedVolumeIDs.isEmpty,
                action: toggleSelectAllDisplayed
            )
            .help("Zaznacz widoczne tomy")

            Text("Tom")
                .frame(width: VolumeColumn.number, alignment: .leading)

            Text("Status")
                .frame(width: VolumeColumn.status, alignment: .leading)

            Text("Cena")
                .frame(width: VolumeColumn.price, alignment: .leading)

            Spacer(minLength: 8)

            Text("Zakup")
                .frame(width: VolumeColumn.date, alignment: .leading)

            Text("Przeczytano")
                .frame(width: VolumeColumn.date, alignment: .leading)

            Text("Premiera")
                .frame(width: VolumeColumn.date, alignment: .leading)

            Color.clear
                .frame(width: VolumeColumn.menu, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func volumeRow(_ volume: Volume) -> some View {
        let isSelected = selectedVolumeIDs.contains(volume.persistentModelID)
        let isRead = volume.read ?? false

        return HStack(spacing: VolumeColumn.spacing) {
            selectionCheckbox(isOn: isSelected) {
                toggleSelection(volume)
            }

            Text("#\(volume.number)")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .frame(width: VolumeColumn.number, alignment: .leading)

            HStack(spacing: 6) {
                statusChip(
                    title: "Kupiony",
                    isActive: volume.owned,
                    icon: "checkmark.circle.fill"
                ) {
                    toggleOwned(volume)
                }

                statusChip(
                    title: "Przeczytany",
                    isActive: isRead,
                    icon: "book.closed.fill"
                ) {
                    toggleRead(volume)
                }
            }
            .frame(width: VolumeColumn.status, alignment: .leading)

            priceField(volume)
                .frame(width: VolumeColumn.price, alignment: .leading)

            Spacer(minLength: 8)

            dateCell(
                icon: "cart",
                date: volume.purchaseDate,
                help: "Data zakupu"
            ) {
                editingDateTarget = .purchase(volume)
            }

            dateCell(
                icon: "book.closed",
                date: volume.readDate,
                help: "Data przeczytania"
            ) {
                editingDateTarget = .read(volume)
            }

            dateCell(
                icon: "sparkles",
                date: volume.releaseDate,
                help: "Data premiery"
            ) {
                editingDateTarget = .release(volume)
            }

            Menu {
                Button("Ustaw datę zakupu") {
                    editingDateTarget = .purchase(volume)
                }

                Button("Ustaw datę przeczytania") {
                    editingDateTarget = .read(volume)
                }

                Button("Ustaw datę premiery") {
                    editingDateTarget = .release(volume)
                }

                Divider()

                Button(role: .destructive) {
                    deleteVolume(volume)
                } label: {
                    Text("Usuń tom")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: VolumeColumn.menu, height: 28)
                    .background(.white.opacity(0.05), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: VolumeColumn.menu)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(rowBackground(isSelected: isSelected, isRead: isRead, isOwned: volume.owned))
    }

    private func rowBackground(isSelected: Bool, isRead: Bool, isOwned: Bool) -> Color {
        if isSelected {
            return .green.opacity(0.10)
        }
        if isRead {
            return .green.opacity(0.045)
        }
        if isOwned {
            return .white.opacity(0.02)
        }
        return .clear
    }

    private func priceField(_ volume: Volume) -> some View {
        HStack(spacing: 6) {
            TextField(
                "0,00",
                value: Bindable(volume).price,
                format: .number.precision(.fractionLength(2))
            )
            .textFieldStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)

            Text("PLN")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            .white.opacity(volume.owned ? 0.06 : 0.02),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(volume.owned ? 1 : 0.45)
        .disabled(!volume.owned)
        .help(volume.owned ? "Cena tomu" : "Oznacz tom jako kupiony, aby wpisać cenę")
    }

    private func dateCell(
        icon: String,
        date: Date?,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(date == nil ? .tertiary : .secondary)
                    .frame(width: 14)

                Text(date?.yyyyMMdd() ?? "—")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(date == nil ? .tertiary : .primary)
            }
            .frame(width: VolumeColumn.date, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func statusChip(
        title: String,
        isActive: Bool,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))

                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? .black : .secondary)
            .background(
                isActive ? Color.green : Color.white.opacity(0.06),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isActive ? "Kliknij, aby cofnąć" : "Kliknij, aby oznaczyć")
    }

    private func toggleOwned(_ volume: Volume) {
        if volume.owned {
            volume.owned = false
            volume.purchaseDate = nil
            volume.read = false
            volume.readDate = nil
        } else {
            if shouldAskMarkPreviousOwned(upTo: volume) {
                pendingBulkAction = .markOwnedUpTo(volume)
                showBulkConfirm = true
                return
            }

            volume.owned = true
            if volume.purchaseDate == nil {
                volume.purchaseDate = .now
            }
        }
    }

    private func toggleRead(_ volume: Volume) {
        if volume.read ?? false {
            volume.read = false
            volume.readDate = nil
        } else {
            if shouldAskMarkPreviousRead(upTo: volume) {
                pendingBulkAction = .markReadUpTo(volume)
                showBulkConfirm = true
                return
            }

            volume.owned = true
            volume.read = true

            if volume.purchaseDate == nil {
                volume.purchaseDate = .now
            }

            if volume.readDate == nil {
                volume.readDate = .now
            }
        }
    }

    private func markAllOwned() {
        for volume in manga.volumes {
            volume.owned = true
            if volume.purchaseDate == nil {
                volume.purchaseDate = .now
            }
        }
    }

    private func markAllRead() {
        for volume in manga.volumes {
            volume.owned = true
            volume.read = true

            if volume.purchaseDate == nil {
                volume.purchaseDate = .now
            }

            if volume.readDate == nil {
                volume.readDate = .now
            }
        }
    }

    private func clearReadProgress() {
        for volume in manga.volumes {
            volume.read = false
            volume.readDate = nil
        }
    }
}

private struct StarRatingView: View {
    @Binding var rating: Double

    let maxRating: Int
    let starSize: CGFloat
    let spacing: CGFloat

    @Binding var hoverRating: Double?

    init(
        rating: Binding<Double>,
        hoverRating: Binding<Double?>,
        maxRating: Int = 5,
        starSize: CGFloat = 24,
        spacing: CGFloat = 8
    ) {
        _rating = rating
        _hoverRating = hoverRating
        self.maxRating = maxRating
        self.starSize = starSize
        self.spacing = spacing
    }

    private var displayedRating: Double {
        hoverRating ?? rating
    }

    private var totalWidth: CGFloat {
        CGFloat(maxRating) * starSize + CGFloat(maxRating - 1) * spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1 ... maxRating, id: \.self) { index in
                Image(
                    systemName: imageName(for: index, rating: displayedRating)
                )
                .resizable()
                .scaledToFit()
                .frame(width: starSize, height: starSize)
                .foregroundStyle(.yellow)
            }
        }
        .frame(width: totalWidth, height: starSize, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoverRating = ratingValue(at: location.x)
            case .ended:
                hoverRating = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    hoverRating = ratingValue(at: value.location.x)
                }
                .onEnded { value in
                    rating = ratingValue(at: value.location.x)
                    hoverRating = nil
                }
        )
    }

    private func ratingValue(at x: CGFloat) -> Double {
        let clampedX = min(max(0, x), totalWidth)

        for index in 1 ... maxRating {
            let starStart = CGFloat(index - 1) * (starSize + spacing)
            let starEnd = starStart + starSize

            let hitStart: CGFloat
            let hitEnd: CGFloat

            if index == 1 {
                hitStart = 0
            } else {
                let previousStarEnd = starStart - spacing
                hitStart = previousStarEnd + spacing / 2
            }

            if index == maxRating {
                hitEnd = totalWidth
            } else {
                hitEnd = starEnd + spacing / 2
            }

            guard clampedX >= hitStart && clampedX <= hitEnd else { continue }

            let localX = min(max(0, clampedX - starStart), starSize)

            if localX < starSize / 2 {
                return Double(index) - 0.5
            } else {
                return Double(index)
            }
        }

        return 0
    }

    private func imageName(for index: Int, rating: Double) -> String {
        let value = Double(index)

        if rating >= value {
            return "star.fill"
        } else if rating == value - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

private struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Components

extension MangaDetailView {
    private func dateEditorSheet(_ target: EditingDateTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch target {
            case let .purchase(volume):
                Text("Wybierz datę zakupu")
                    .font(.headline)

                glassyDatePicker(
                    title: "Data zakupu",
                    selection: Binding(
                        get: { volume.purchaseDate ?? .now },
                        set: {
                            volume.purchaseDate = $0
                            volume.owned = true
                        }
                    )
                )

                HStack {
                    Button("Anuluj", role: .cancel) {
                        editingDateTarget = nil
                    }

                    Button("Usuń datę", role: .destructive) {
                        volume.purchaseDate = nil
                        editingDateTarget = nil
                    }

                    Spacer()

                    Button("Gotowe") {
                        editingDateTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }

            case let .read(volume):
                Text("Wybierz datę przeczytania")
                    .font(.headline)

                glassyDatePicker(
                    title: "Data przeczytania",
                    selection: Binding(
                        get: { volume.readDate ?? .now },
                        set: {
                            volume.readDate = $0
                            volume.read = true
                        }
                    )
                )

                HStack {
                    Button("Anuluj", role: .cancel) {
                        editingDateTarget = nil
                    }

                    Button("Usuń datę", role: .destructive) {
                        volume.readDate = nil
                        editingDateTarget = nil
                    }

                    Spacer()

                    Button("Gotowe") {
                        editingDateTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }

            case let .release(volume):
                Text("Wybierz datę premiery")
                    .font(.headline)

                glassyDatePicker(
                    title: "Data premiery",
                    selection: Binding(
                        get: { volume.releaseDate ?? .now },
                        set: { volume.releaseDate = $0 }
                    )
                )

                HStack {
                    Button("Anuluj", role: .cancel) {
                        editingDateTarget = nil
                    }

                    Button("Usuń datę", role: .destructive) {
                        volume.releaseDate = nil
                        editingDateTarget = nil
                    }

                    Spacer()

                    Button("Gotowe") {
                        editingDateTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func glassyDatePicker(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DatePicker(
                title,
                selection: selection,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
        }
    }

    fileprivate var backgroundGradient: some View {
        AppBackgroundView()
    }
}

// MARK: - Actions

private extension MangaDetailView {
    func formattedAniListDate(_ date: Date?) -> String {
        guard let date else { return "Brak" }

        return date.yyyyMMdd()
    }

    func refreshAniListInfo() async {
        let title = manga.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            ToastService.shared.show(
                "Najpierw wpisz tytuł mangi.",
                type: .error
            )
            return
        }

        isRefreshingAniList = true
        aniListMessage = nil

        do {
            guard
                let info = try await AniListService.fetchMangaInfo(title: title)
            else {
                ToastService.shared.show(
                    "Nie znaleziono danych w AniList dla: \(title)",
                    type: .error
                )
                isRefreshingAniList = false
                return
            }

            manga.aniListId = info.id
            manga.aniListStatus = info.status
            manga.aniListGenresRaw = info.genres.joined(separator: ", ")
            manga.aniListAverageScore = info.averageScore
            manga.aniListStartDate = info.startDate
            manga.aniListEndDate = info.endDate
            manga.aniListAuthor = info.author
            manga.bannerImage = info.bannerImage
            manga.aniListParentId = info.parentId
            manga.isSpinOff = info.parentId != nil
            if let description = info.description {
                manga.summary = description
            }

            if let totalVolumes = info.volumes, totalVolumes > 0 {
                addAniListVolumes(total: totalVolumes)
            }

            if manga.coverURL == nil || manga.coverURL?.isEmpty == true {
                manga.coverURL = info.coverURL
            }

            ToastService.shared.show(
                "Dane z AniList odświeżone dla \(title).",
                type: .success
            )
        } catch {
            ToastService.shared.show(
                "Nie udało się odświeżyć danych z AniList.",
                type: .error
            )
            print("AniList refresh error:", error)
        }

        isRefreshingAniList = false
    }

    func addAniListVolumes(total: Int) {
        let existing = Set(manga.volumes.map { $0.number })

        for number in 1 ... total where !existing.contains(number) {
            manga.volumes.append(
                Volume(number: number, owned: false, manga: manga)
            )
        }
    }

    func fetchCoverFromAniList() async {
        let title = manga.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            ToastService.shared.show(
                "Najpierw wpisz tytuł mangi.",
                type: .error
            )
            return
        }

        isFetchingCover = true
        coverFetchMessage = nil

        do {
            if let url = try await AniListService.fetchMangaCoverURL(
                title: title
            ) {
                manga.coverURL = url
                ToastService.shared.show(
                    "Okładka pobrana z AniList.",
                    type: .success
                )
            } else {
                ToastService.shared.show(
                    "Nie znaleziono okładki dla: \(title)",
                    type: .error
                )
            }
        } catch {
            ToastService.shared.show(
                "Nie udało się pobrać okładki.",
                type: .error
            )
            print("AniList error:", error)
        }

        isFetchingCover = false
    }

    func fetchRecommendations() async {
        guard let mangaId = manga.aniListId else {
            ToastService.shared.show(
                "Najpierw odśwież dane z AniList.",
                type: .error
            )
            return
        }

        isFetchingRecommendations = true
        recommendationsMessage = nil

        do {
            if recommendations.isEmpty {
                let results =
                    try await AniListService.fetchMangaRecommendations(
                        mangaId: mangaId
                    )
                recommendations = results
                if results.isEmpty {
                    recommendationsMessage = "Brak rekomendacji do pokazania."
                }
                ToastService.shared.show(
                    "Rekomendacje z AniList pobrane.",
                    type: .success
                )
            }
            showRecommendationsSheet = true
        } catch {
            recommendationsMessage =
                "Nie udało się pobrać rekomendacji."
            ToastService.shared.show(
                "Nie udało się pobrać rekomendacji.",
                type: .error
            )
            print("AniList recommendations error:", error)
        }

        isFetchingRecommendations = false
    }

    func addSingleVolume() {
        volumeValidationMessage = nil

        guard let n = Int(newVolumeNumber.trimmingCharacters(in: .whitespaces)),
              n > 0
        else { return }

        guard !manga.volumes.contains(where: { $0.number == n }) else {
            ToastService.shared.show(
                "Błąd",
                description: "Tom \(n) już istnieje.",
                type: .error
            )
            return
        }

        let volume = Volume(number: n, owned: false, manga: manga)
        manga.volumes.append(volume)
        newVolumeNumber = ""
    }

    func addBulkVolumes() {
        guard let from = Int(bulkFrom.trimmingCharacters(in: .whitespaces)),
              let to = Int(bulkTo.trimmingCharacters(in: .whitespaces)),
              from >= 0, to >= 0
        else { return }

        let lower = min(from, to)
        let upper = max(from, to)
        let existing = Set(manga.volumes.map { $0.number })

        for number in lower ... upper where !existing.contains(number) {
            manga.volumes.append(
                Volume(number: number, owned: false, manga: manga)
            )
        }

        bulkFrom = ""
        bulkTo = ""
    }

    func deleteVolume(_ volume: Volume) {
        manga.volumes.removeAll {
            $0.persistentModelID == volume.persistentModelID
        }
        modelContext.delete(volume)
    }

    func applyPendingAction(markPrevious: Bool) {
        guard let action = pendingBulkAction else { return }
        defer { pendingBulkAction = nil }

        switch action {
        case let .markOwnedUpTo(target):
            let maxNumber = target.number
            for volume in manga.volumes {
                if markPrevious {
                    if volume.number <= maxNumber {
                        volume.owned = true
                        if volume.purchaseDate == nil {
                            volume.purchaseDate = .now
                        }
                    }
                } else if volume.persistentModelID == target.persistentModelID {
                    volume.owned = true
                    if volume.purchaseDate == nil { volume.purchaseDate = .now }
                }
            }

        case let .markReadUpTo(target):
            let targetNumber = target.number

            if markPrevious {
                let lastPreviouslyReadNumber =
                    manga.volumes
                        .filter { $0.number < targetNumber && ($0.read ?? false) }
                        .map(\.number)
                        .max() ?? 0

                for volume in manga.volumes {
                    guard volume.number > lastPreviouslyReadNumber,
                          volume.number <= targetNumber
                    else { continue }

                    if !(volume.read ?? false) {
                        volume.read = true
                    }

                    if volume.readDate == nil {
                        volume.readDate = .now
                    }
                }
            } else {
                if !(target.read ?? false) {
                    target.read = true
                }
                if target.readDate == nil {
                    target.readDate = .now
                }
            }
        }
    }

    func shouldAskMarkPreviousOwned(upTo target: Volume) -> Bool {
        guard
            let previous = manga.volumes.first(where: {
                $0.number == target.number - 1
            })
        else {
            return false
        }
        return !previous.owned
    }

    func shouldAskMarkPreviousRead(upTo target: Volume) -> Bool {
        guard
            let previous = manga.volumes.first(where: {
                $0.number == target.number - 1
            })
        else {
            return false
        }
        return previous.owned && !(previous.read ?? false)
    }

    func formatAniListStatus(_ status: String) -> String {
        switch status {
        case "FINISHED":
            return "Zakończona"
        case "RELEASING":
            return "Wydawana"
        case "NOT_YET_RELEASED":
            return "Jeszcze niewydana"
        case "CANCELLED":
            return "Anulowana"
        case "HIATUS":
            return "Wstrzymana"
        default:
            return status
        }
    }
}

// MARK: - Reusable Views

private struct PremiumCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                .white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private extension View {
    func premiumInput(width: CGFloat) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width)
            .background(
                .white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }

    func volumeActionButton() -> some View {
        buttonStyle(.plain)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension Binding where Value == String? {
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

private struct MetadataPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }
}
