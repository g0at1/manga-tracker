import AVFoundation
import SwiftData
import SwiftUI

/// Adding a bought volume by its barcode: scan (or type) the ISBN, look it
/// up in the National Library's catalogue and on AniList, then confirm the
/// series, number and price before anything is saved. Stays open after
/// saving so a whole stack can be scanned in one go.
struct ScanVolumeSheet: View {
    let mangas: [Manga]
    let nextSortOrder: Int
    /// Opens a series after the sheet closes.
    let onOpen: (Manga) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var draft = ScanDraft()
    @State private var manualISBN = ""
    @State private var cameraAvailable = false
    @State private var cameraChecked = false
    @State private var isSaving = false
    /// The last save, shown above the camera with a way to open the series.
    @State private var lastSaved: (message: String, manga: Manga)?
    @FocusState private var manualFocused: Bool

    enum Phase: Equatable {
        case scanning
        case lookingUp(String)
        case confirming
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    scanningView
                case let .lookingUp(isbn):
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Szukam ISBN \(ISBN.formatted(isbn))…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .confirming:
                    ScanConfirmationForm(draft: $draft, mangas: sortedMangas)
                }
            }
            .background(AppBackgroundView())
            .navigationTitle(phase == .confirming ? "Potwierdź tom" : "Skanuj tom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
        }
        .task {
            guard !cameraChecked else { return }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            cameraAvailable = ISBNScannerView.isAvailable
            cameraChecked = true
        }
    }

    private var sortedMangas: [Manga] {
        mangas.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if phase == .confirming {
            ToolbarItem(placement: .cancellationAction) {
                Button("Wstecz") { phase = .scanning }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else if case let .alreadyOwned(manga) = draft.outcome {
                    Button("Otwórz serię") { open(manga) }
                } else {
                    Button("Zapisz", action: save)
                        .disabled(!draft.canSave)
                }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Zamknij") { dismiss() }
            }
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lastSaved {
                    HStack {
                        Label(lastSaved.message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Otwórz") { open(lastSaved.manga) }
                            .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if cameraAvailable {
                    ISBNScannerView(isActive: phase == .scanning) { isbn, price in
                        Task { await lookUp(isbn, scannedPrice: price) }
                    }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("Skieruj aparat na kod kreskowy z tyłu tomu. Cena z okładki („CENA: …”) zostanie odczytana, jeśli będzie widoczna.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if cameraChecked {
                    ContentUnavailableView(
                        "Skaner niedostępny",
                        systemImage: "barcode.viewfinder",
                        description: Text("To urządzenie nie ma aparatu albo aplikacja nie ma do niego dostępu. Wpisz ISBN ręcznie.")
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("ISBN ręcznie")
                        .font(.headline)
                    HStack {
                        TextField("978-83-…", text: $manualISBN)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($manualFocused)
                            .submitLabel(.search)
                            .onSubmit(lookUpManual)
                            .textFieldStyle(.roundedBorder)
                        Button("Szukaj", action: lookUpManual)
                            .buttonStyle(.borderedProminent)
                            .disabled(ISBN.normalized(manualISBN) == nil)
                    }
                    if !manualISBN.isEmpty, ISBN.normalized(manualISBN) == nil {
                        Text("To nie jest poprawny numer ISBN.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
    }

    private func lookUpManual() {
        guard let isbn = ISBN.normalized(manualISBN) else { return }
        manualFocused = false
        Task { await lookUp(isbn, scannedPrice: nil) }
    }

    // MARK: - Lookup

    private func lookUp(_ isbn: String, scannedPrice: Double?) async {
        guard phase == .scanning else { return }
        phase = .lookingUp(isbn)

        var lookupFailed = false
        let book: CataloguedBook?
        do {
            book = try await NationalLibraryService.lookup(isbn: isbn)
        } catch {
            book = nil
            lookupFailed = true
        }

        // A volume already carrying this ISBN settles it without AniList.
        let exactSeries = ScanMatcher.series(isbn: isbn, titles: [], aniListId: nil, in: mangas)
        var aniList: AniListMangaInfo?
        if exactSeries == nil, let book {
            aniList = await Self.searchAniList(for: book)
        }

        let titles = [book?.seriesTitle, book?.originalTitle, aniList?.englishTitle, aniList?.romajiTitle]
            .compactMap { $0 }
        let series = exactSeries ?? ScanMatcher.series(isbn: isbn, titles: titles, aniListId: aniList?.id, in: mangas)
        let existingVolume = series.flatMap { ScanMatcher.volume(in: $0, isbn: isbn, number: book?.volumeNumber) }

        let newTitle = aniList?.englishTitle ?? aniList?.romajiTitle ?? book?.seriesTitle ?? ""
        let price = scannedPrice ?? existingVolume?.price

        draft = ScanDraft(
            isbn: isbn,
            book: book,
            lookupFailed: lookupFailed,
            aniList: aniList,
            aniListSearchTitle: newTitle,
            seriesID: series?.persistentModelID,
            newSeriesTitle: newTitle,
            volumeNumber: existingVolume?.number ?? book?.volumeNumber,
            priceText: price.map(Self.formatPrice) ?? "",
            priceWasScanned: scannedPrice != nil,
            purchaseDate: .now
        )
        draft.refreshOutcome(in: mangas)
        phase = .confirming
    }

    /// The series on AniList under its Polish title, then its original
    /// title, then the Polish title before any subtitle ("Frieren").
    private static func searchAniList(for book: CataloguedBook) async -> AniListMangaInfo? {
        var queries = [book.seriesTitle]
        if let original = book.originalTitle {
            queries.append(original)
        }
        if let main = book.seriesTitle.split(separator: ":").first.map(String.init), main != book.seriesTitle {
            queries.append(main)
        }
        for query in queries {
            if let info = try? await AniListService.fetchMangaInfo(title: query) {
                return info
            }
        }
        return nil
    }

    static func formatPrice(_ price: Double) -> String {
        price.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "pl_PL")))
    }

    // MARK: - Saving

    private func save() {
        guard draft.canSave, let number = draft.volumeNumber, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }

            let manga: Manga
            if let id = draft.seriesID, let existing = mangas.first(where: { $0.persistentModelID == id }) {
                manga = existing
            } else {
                let title = draft.newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                manga = Manga(title: title, sortOrder: nextSortOrder)
                var info = draft.aniList
                if info == nil || title != draft.aniListSearchTitle {
                    info = try? await AniListService.fetchMangaInfo(title: title)
                }
                if let info {
                    manga.applyAniListInfo(info)
                    _ = try? await manga.fetchVolumeCovers()
                }
                if manga.aniListAuthor == nil {
                    manga.aniListAuthor = draft.book?.author
                }
                modelContext.insert(manga)
            }

            let result = manga.addScannedVolume(
                number: number,
                isbn: draft.isbn,
                price: draft.price,
                purchaseDate: draft.purchaseDate
            )
            let message = switch result {
            case .added, .markedOwned: L("Dodano: %@ — tom %lld", manga.title, number)
            case .alreadyOwned: L("%@ — tom %lld już jest w bibliotece", manga.title, number)
            }
            lastSaved = (message, manga)
            manualISBN = ""
            phase = .scanning
        }
    }

    private func open(_ manga: Manga) {
        dismiss()
        onOpen(manga)
    }
}

/// What the confirmation screen edits, and what saving it would do.
struct ScanDraft {
    var isbn = ""
    var book: CataloguedBook?
    /// The catalogue couldn't be reached (offline), as opposed to having no
    /// record for the ISBN.
    var lookupFailed = false
    var aniList: AniListMangaInfo?
    /// The title `aniList` was found for: a new series under another title
    /// is looked up again.
    var aniListSearchTitle = ""
    /// The series it goes into; nil creates `newSeriesTitle`.
    var seriesID: PersistentIdentifier?
    var newSeriesTitle = ""
    var volumeNumber: Int?
    var priceText = ""
    var priceWasScanned = false
    var purchaseDate = Date.now
    private(set) var outcome: Outcome = .newSeries

    enum Outcome {
        case newSeries
        case addVolume(Manga)
        case markOwned(Manga, onItsWay: Bool)
        case alreadyOwned(Manga)
    }

    var price: Double? {
        let text = priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(text)
    }

    var canSave: Bool {
        guard let volumeNumber, volumeNumber > 0 else { return false }
        if priceText.trimmingCharacters(in: .whitespaces).isEmpty == false, price == nil {
            return false
        }
        if case .alreadyOwned = outcome {
            return false
        }
        return seriesID != nil || !newSeriesTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Works out `outcome` again after the series or number changed.
    mutating func refreshOutcome(in mangas: [Manga]) {
        guard let seriesID, let manga = mangas.first(where: { $0.persistentModelID == seriesID }) else {
            outcome = .newSeries
            return
        }
        // The same lookup saving uses, so what's shown is what happens.
        guard let volumeNumber, let volume = ScanMatcher.volume(in: manga, isbn: isbn, number: volumeNumber) else {
            outcome = .addVolume(manga)
            return
        }
        if volume.owned {
            outcome = .alreadyOwned(manga)
        } else {
            outcome = .markOwned(manga, onItsWay: volume.isOnItsWay)
        }
    }
}

/// Series, number, price and date of a scanned volume, with what was found
/// for it and what saving will do.
private struct ScanConfirmationForm: View {
    @Binding var draft: ScanDraft
    let mangas: [Manga]

    var body: some View {
        Form {
            foundSection

            Section("Seria") {
                Picker("Seria", selection: $draft.seriesID) {
                    Text("Nowa seria").tag(PersistentIdentifier?.none)
                    ForEach(mangas) { manga in
                        Text(manga.title).tag(Optional(manga.persistentModelID))
                    }
                }
                if draft.seriesID == nil {
                    TextField("Tytuł nowej serii", text: $draft.newSeriesTitle)
                }
            }

            Section {
                HStack {
                    Text("Numer tomu")
                    Spacer()
                    TextField("np. 1", value: $draft.volumeNumber, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                HStack {
                    Text("Cena")
                    Spacer()
                    TextField("0,00", text: $draft.priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                    Text("zł")
                        .foregroundStyle(.secondary)
                }
                DatePicker("Data zakupu", selection: $draft.purchaseDate, displayedComponents: .date)
            } header: {
                Text("Tom")
            } footer: {
                if draft.priceWasScanned {
                    Text("Cena odczytana z okładki — popraw, jeśli zapłacono inaczej.")
                } else {
                    Text("Ceny nie odczytano z okładki. Możesz ją wpisać albo zostawić puste.")
                }
            }

            Section {
                outcomeLabel
            }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: draft.seriesID) { draft.refreshOutcome(in: mangas) }
        .onChange(of: draft.volumeNumber) { draft.refreshOutcome(in: mangas) }
    }

    @ViewBuilder
    private var foundSection: some View {
        Section {
            LabeledContent("ISBN", value: ISBN.formatted(draft.isbn))
            if let book = draft.book {
                LabeledContent("W katalogu", value: book.seriesTitle + (book.volumeNumber.map { " · tom \($0)" } ?? ""))
                if let volumeTitle = book.volumeTitle {
                    LabeledContent("Tytuł tomu", value: volumeTitle)
                }
                if let publisher = book.publisher {
                    LabeledContent("Wydawca", value: publisher)
                }
            }
            if let aniList = draft.aniList, let title = aniList.englishTitle ?? aniList.romajiTitle {
                LabeledContent("AniList", value: title)
            }
        } header: {
            Text("Znaleziono")
        } footer: {
            if draft.lookupFailed {
                Text("Nie udało się połączyć z katalogiem Biblioteki Narodowej. Uzupełnij dane ręcznie.")
            } else if draft.book == nil {
                Text("Tego ISBN nie ma w katalogu Biblioteki Narodowej. Uzupełnij dane ręcznie.")
            }
        }
    }

    @ViewBuilder
    private var outcomeLabel: some View {
        switch draft.outcome {
        case .newSeries:
            Label("Zostanie utworzona nowa seria (z danymi z AniList) z tym tomem.", systemImage: "plus.rectangle.on.rectangle")
        case let .addVolume(manga):
            Label(L("Tom zostanie dodany do serii „%@”.", manga.title), systemImage: "plus.circle")
        case let .markOwned(manga, onItsWay):
            if onItsWay {
                Label(L("Tom jest w drodze — w serii „%@” zostanie oznaczony jako dostarczony.", manga.title), systemImage: "shippingbox")
            } else {
                Label(L("Tom zostanie oznaczony jako kupiony w serii „%@”.", manga.title), systemImage: "checkmark.circle")
            }
        case let .alreadyOwned(manga):
            Label(L("Ten tom już jest w bibliotece („%@”). Nic nie zostanie dodane.", manga.title), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
