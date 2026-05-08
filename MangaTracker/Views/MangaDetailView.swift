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
    @State private var volumeValidationMessage: String?
    @State private var isFetchingCover = false
    @State private var coverFetchMessage: String?
    @State private var isRefreshingAniList = false
    @State private var aniListMessage: String?
    @State private var summaryHeight: CGFloat = 140
    @FocusState private var titleFocused: Bool

    private let defaultTitle = "Nowa manga"

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "Wszystkie"
        case missing = "Brakujące"
        case unread = "Nieprzeczytane"

        var id: String { rawValue }
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
            case .purchase(let volume):
                return "purchase-\(volume.persistentModelID)"
            case .read(let volume):
                return "read-\(volume.persistentModelID)"
            case .release(let volume):
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

                if manga.aniListStartDate != nil || manga.aniListEndDate != nil
                {
                    MetadataPill(
                        icon: "calendar",
                        text:
                            "\(formattedAniListDate(manga.aniListStartDate)) – \(formattedAniListDate(manga.aniListEndDate))",
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

            coverURLSection
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
                        case .success(let image):
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
                            maxRating: 5,
                            starSize: 26,
                            spacing: 6
                        )

                        Text(
                            manga.rating == 0
                                ? "Brak"
                                : String(format: "%.1f / 5", manga.rating ?? 0)
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
            .lineLimit(4...8)

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

    private var coverURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("URL okładki", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await fetchCoverFromAniList()
                    }
                } label: {
                    if isFetchingCover {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Pobierz z AniList", systemImage: "arrow.down")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .disabled(
                    isFetchingCover
                        || manga.title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }

            TextField(
                "https://...",
                text: Binding(
                    get: { manga.coverURL ?? "" },
                    set: { manga.coverURL = $0.isEmpty ? nil : $0 }
                )
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            Text(
                coverFetchMessage
                    ?? "Wklej link do obrazka jpg, png albo webp. Miniatura zostanie zcache’owana lokalnie."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filtruj widok")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Filtr", selection: $filterMode) {
                            ForEach(FilterMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(.green)
                        .frame(width: 360)
                    }

                    Spacer()
                }

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

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 260, maximum: 320),
                                spacing: 16
                            )
                        ],
                        spacing: 16
                    ) {
                        ForEach(displayedVolumes) { volume in
                            volumeTile(volume)
                        }
                    }
                    .padding(18)
                }
                .frame(minHeight: 360)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var volumesToolbar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tomy")
                        .font(.title3.weight(.bold))

                    Text("Szybkie zarządzanie kupionymi i przeczytanymi tomami")
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

    private func statusChip(
        title: String,
        isActive: Bool,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isActive ? .black : .secondary)
            .background(
                isActive ? Color.green : Color.white.opacity(0.06),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func tileBackground(for volume: Volume) -> Color {
        if volume.read ?? false {
            return .green.opacity(0.13)
        }

        if volume.owned {
            return .white.opacity(0.07)
        }

        return .white.opacity(0.035)
    }

    private func tileBorder(for volume: Volume) -> Color {
        if volume.read ?? false {
            return .green.opacity(0.35)
        }

        if volume.owned {
            return .green.opacity(0.18)
        }

        return .white.opacity(0.07)
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

    private func volumeTile(_ volume: Volume) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("#\(volume.number)")
                    .font(.title3.weight(.bold))

                Spacer()

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
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                statusChip(
                    title: "Kupiony",
                    isActive: volume.owned,
                    icon: "checkmark.circle.fill"
                ) {
                    toggleOwned(volume)
                }

                statusChip(
                    title: "Przeczytany",
                    isActive: volume.read ?? false,
                    icon: "book.closed.fill"
                ) {
                    toggleRead(volume)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                dateLine(
                    icon: "calendar",
                    title: "Zakup",
                    date: volume.purchaseDate,
                    placeholder: "Brak daty zakupu"
                ) {
                    editingDateTarget = .purchase(volume)
                }

                dateLine(
                    icon: "book.closed",
                    title: "Czytanie",
                    date: volume.readDate,
                    placeholder: "Brak daty przeczytania"
                ) {
                    editingDateTarget = .read(volume)
                }

                dateLine(
                    icon: "sparkles",
                    title: "Premiera",
                    date: volume.releaseDate,
                    placeholder: "Brak daty premiery"
                ) {
                    editingDateTarget = .release(volume)
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "0.00",
                    value: Bindable(volume).price,
                    format: .number.precision(.fractionLength(2))
                )
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    .white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

                Text("PLN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minHeight: 190)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tileBackground(for: volume))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tileBorder(for: volume), lineWidth: 1)
        }
    }

    private func dateLine(
        icon: String,
        title: String,
        date: Date?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(
                    date?.formatted(.dateTime.day().month().year())
                        ?? placeholder
                )
                .font(.caption)
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    fileprivate var volumesHeader: some View {
        HStack(spacing: 12) {
            Text("Tom")
                .frame(width: 70, alignment: .leading)

            Text("Kupiony")
                .frame(width: 80, alignment: .center)

            Text("Przeczytany")
                .frame(width: 100, alignment: .center)

            Text("Data zakupu")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            Text("Data przeczytania")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            Text("Data premiery")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            Text("Cena")
                .frame(width: 150, alignment: .leading)

            Text("")
                .frame(width: 44)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    fileprivate func volumeRow(_ v: Volume) -> some View {
        HStack(spacing: 12) {
            Text("#\(v.number)")
                .font(.body.weight(.semibold))
                .frame(width: 70, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { v.owned },
                    set: { newValue in
                        if newValue == false {
                            v.owned = false
                            v.purchaseDate = nil
                            return
                        }

                        if v.owned == false
                            && shouldAskMarkPreviousOwned(upTo: v)
                        {
                            pendingBulkAction = .markOwnedUpTo(v)
                            showBulkConfirm = true
                            return
                        }

                        v.owned = true
                        if v.purchaseDate == nil {
                            v.purchaseDate = .now
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .tint(.green)
            .frame(width: 80, alignment: .center)

            Toggle(
                "",
                isOn: Binding(
                    get: { v.read ?? false },
                    set: { newValue in
                        if newValue == false {
                            v.read = false
                            v.readDate = nil
                            return
                        }

                        let current = v.read ?? false
                        if current == false
                            && shouldAskMarkPreviousRead(upTo: v)
                        {
                            pendingBulkAction = .markReadUpTo(v)
                            showBulkConfirm = true
                            return
                        }

                        v.read = true
                        if v.readDate == nil {
                            v.readDate = .now
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .tint(.green)
            .frame(width: 100, alignment: .center)

            dateButton(
                date: v.purchaseDate,
                placeholder: "Ustaw datę",
                action: { editingDateTarget = .purchase(v) }
            )
            .frame(minWidth: 150, maxWidth: .infinity)

            dateButton(
                date: v.readDate,
                placeholder: "Ustaw datę",
                action: { editingDateTarget = .read(v) }
            )
            .frame(minWidth: 150, maxWidth: .infinity)

            dateButton(
                date: v.releaseDate,
                placeholder: "Ustaw datę",
                action: { editingDateTarget = .release(v) }
            )
            .frame(minWidth: 150, maxWidth: .infinity)

            HStack(spacing: 8) {
                TextField(
                    "0.00",
                    value: Bindable(v).price,
                    format: .number.precision(.fractionLength(2))
                )
                .premiumInput(width: 85)

                Text("PLN")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            Button(role: .destructive) {
                deleteVolume(v)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        .red.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct StarRatingView: View {
    @Binding var rating: Double

    let maxRating: Int
    let starSize: CGFloat
    let spacing: CGFloat

    @State private var hoverRating: Double?

    init(
        rating: Binding<Double>,
        maxRating: Int = 5,
        starSize: CGFloat = 24,
        spacing: CGFloat = 8
    ) {
        self._rating = rating
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
            ForEach(1...maxRating, id: \.self) { index in
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
            case .active(let location):
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

        for index in 1...maxRating {
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
    fileprivate func dateButton(
        date: Date?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)

                if let date {
                    Text(date, format: .dateTime.day().month().year())
                        .foregroundStyle(.primary)
                } else {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dateEditorSheet(_ target: EditingDateTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch target {
            case .purchase(let volume):
                Text("Wybierz datę zakupu")
                    .font(.headline)

                DatePicker(
                    "Data zakupu",
                    selection: Binding(
                        get: { volume.purchaseDate ?? .now },
                        set: { volume.purchaseDate = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

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

            case .read(let volume):
                Text("Wybierz datę przeczytania")
                    .font(.headline)

                DatePicker(
                    "Data przeczytania",
                    selection: Binding(
                        get: { volume.readDate ?? .now },
                        set: { volume.readDate = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

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

            case .release(let volume):
                Text("Wybierz datę premiery")
                    .font(.headline)

                DatePicker(
                    "Data premiery",
                    selection: Binding(
                        get: { volume.releaseDate ?? .now },
                        set: { volume.releaseDate = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

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

    fileprivate var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.96),
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color.black.opacity(0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Actions
extension MangaDetailView {
    fileprivate func formattedAniListDate(_ date: Date?) -> String {
        guard let date else { return "Brak" }

        return date.formatted(
            .dateTime
                .day()
                .month()
                .year()
        )
    }

    fileprivate func refreshAniListInfo() async {
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
            if let description = info.description {
                manga.summary = description
            }

            if manga.coverURL == nil || manga.coverURL?.isEmpty == true {
                manga.coverURL = info.coverURL
            }

            ToastService.shared.show(
                "Dane z AniList odświeżone.",
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

    fileprivate func fetchCoverFromAniList() async {
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

    fileprivate func addSingleVolume() {
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

    fileprivate func addBulkVolumes() {
        guard let from = Int(bulkFrom.trimmingCharacters(in: .whitespaces)),
            let to = Int(bulkTo.trimmingCharacters(in: .whitespaces)),
            from >= 0, to >= 0
        else { return }

        let lower = min(from, to)
        let upper = max(from, to)
        let existing = Set(manga.volumes.map { $0.number })

        for number in lower...upper where !existing.contains(number) {
            manga.volumes.append(
                Volume(number: number, owned: false, manga: manga)
            )
        }

        bulkFrom = ""
        bulkTo = ""
    }

    fileprivate func deleteVolume(_ volume: Volume) {
        manga.volumes.removeAll {
            $0.persistentModelID == volume.persistentModelID
        }
        modelContext.delete(volume)
    }

    fileprivate func applyPendingAction(markPrevious: Bool) {
        guard let action = pendingBulkAction else { return }
        defer { pendingBulkAction = nil }

        switch action {
        case .markOwnedUpTo(let target):
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

        case .markReadUpTo(let target):
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

    fileprivate func shouldAskMarkPreviousOwned(upTo target: Volume) -> Bool {
        guard
            let previous = manga.volumes.first(where: {
                $0.number == target.number - 1
            })
        else {
            return false
        }
        return !previous.owned
    }

    fileprivate func shouldAskMarkPreviousRead(upTo target: Volume) -> Bool {
        guard
            let previous = manga.volumes.first(where: {
                $0.number == target.number - 1
            })
        else {
            return false
        }
        return previous.owned && !(previous.read ?? false)
    }

    fileprivate func formatAniListStatus(_ status: String) -> String {
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

extension View {
    fileprivate func premiumInput(width: CGFloat) -> some View {
        self
            .textFieldStyle(.plain)
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

    fileprivate func volumeActionButton() -> some View {
        self
            .buttonStyle(.plain)
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
