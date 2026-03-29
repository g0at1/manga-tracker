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

        var id: String {
            switch self {
            case .purchase(let volume):
                return "purchase-\(volume.persistentModelID)"
            case .read(let volume):
                return "read-\(volume.persistentModelID)"
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
    fileprivate var heroSection: some View {
        PremiumCard {
            HStack(alignment: .top, spacing: 22) {
                coverSection

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Tytuł", text: $manga.title)
                            .font(.system(size: 30, weight: .bold))
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .onChange(of: titleFocused) { _, focused in
                                if focused && manga.title == defaultTitle {
                                    manga.title = ""
                                }
                            }

                        TextField(
                            "Notatka (opcjonalnie)",
                            text: $manga.note,
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .foregroundStyle(.secondary)
                        .lineLimit(2...4)
                    }

                    HStack(spacing: 12) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Postęp czytania")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                totalCount == 0
                                    ? "0%" : "\(Int(completionValue * 100))%"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }

                        ProgressView(value: completionValue)
                            .tint(.green)
                            .scaleEffect(y: 1.4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL okładki")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "https://...",
                            text: Binding(
                                get: { manga.coverURL ?? "" },
                                set: { manga.coverURL = $0.isEmpty ? nil : $0 }
                            )
                        )
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            .white.opacity(0.05),
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                        )

                        Text(
                            "Wklej link do obrazka jpg, png albo webp. Miniatura zostanie zcache’owana lokalnie."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tomy")
                            .font(.title3.weight(.bold))
                        Text("Zarządzaj stanem, ceną i datami w jednym miejscu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Widoczne: \(displayedVolumes.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(20)

                Divider().overlay(.white.opacity(0.06))

                VStack(spacing: 0) {
                    volumesHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(displayedVolumes) { volume in
                                volumeRow(volume)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    fileprivate func addSingleVolume() {
        guard let n = Int(newVolumeNumber.trimmingCharacters(in: .whitespaces)),
            n > 0
        else { return }
        guard !manga.volumes.contains(where: { $0.number == n }) else { return }

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
            let maxNumber = target.number
            for volume in manga.volumes {
                if markPrevious {
                    if volume.number <= maxNumber {
                        volume.read = true
                        if volume.readDate == nil { volume.readDate = .now }
                    }
                } else if volume.persistentModelID == target.persistentModelID {
                    volume.read = true
                    if volume.readDate == nil { volume.readDate = .now }
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
}
