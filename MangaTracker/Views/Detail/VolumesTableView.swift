import AppKit
import SwiftData
import SwiftUI

/// The series' volumes: filter chips, bulk selection, and one row per volume
/// with owned/read toggles, price and dates. A volume split into parts (a
/// collected edition) gets a row per part underneath, each read on its own.
struct VolumesTableView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var manga: Manga

    @State private var filterMode: FilterMode = .all
    @State private var selectedVolumeIDs: Set<PersistentIdentifier> = []
    @State private var lastSelectedVolumeID: PersistentIdentifier?
    @State private var showBulkConfirm = false
    @State private var pendingBulkAction: BulkAction?
    @State private var editingDateTarget: EditingDateTarget?
    @State private var editingPartsTarget: PartsEditTarget?
    @State private var showBulkPricePopover = false
    @State private var bulkPriceText = ""
    @State private var isFetchingCovers = false
    @State private var showBulkPurchaseDatePopover = false
    @State private var bulkPurchaseDate: Date = .now

    enum FilterMode: String, CaseIterable, Identifiable {
        case all
        case missing
        case unread

        var id: String {
            rawValue
        }

        var label: LocalizedStringKey {
            switch self {
            case .all: "Wszystkie"
            case .missing: "Brakujące"
            case .unread: "Nieprzeczytane"
            }
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
        case partRead(VolumePart)

        var id: String {
            switch self {
            case let .purchase(volume): "purchase-\(volume.persistentModelID)"
            case let .read(volume): "read-\(volume.persistentModelID)"
            case let .release(volume): "release-\(volume.persistentModelID)"
            case let .partRead(part): "part-read-\(part.persistentModelID)"
            }
        }
    }

    /// The volumes the split sheet is about: one from its row menu, or the
    /// whole selection from the bulk bar.
    private struct PartsEditTarget: Identifiable {
        let volumes: [Volume]

        var id: String {
            volumes.map { "\($0.persistentModelID)" }.joined(separator: ",")
        }
    }

    fileprivate enum Column {
        static let checkbox: CGFloat = 24
        /// Only laid out once the series has volume covers.
        static let cover: CGFloat = 26
        static let number: CGFloat = 44
        static let status: CGFloat = 224
        static let price: CGFloat = 124
        static let date: CGFloat = 100
        static let menu: CGFloat = 26
        static let spacing: CGFloat = 12
    }

    // MARK: - Derived

    private var sortedVolumes: [Volume] {
        manga.volumes.sorted { $0.number < $1.number }
    }

    private var displayedVolumes: [Volume] {
        switch filterMode {
        case .all: sortedVolumes
        case .missing: sortedVolumes.filter { !$0.owned }
        case .unread: sortedVolumes.filter { !($0.read ?? false) }
        }
    }

    private func count(for mode: FilterMode) -> Int {
        switch mode {
        case .all: manga.volumes.count
        case .missing: manga.volumes.filter { !$0.owned }.count
        case .unread: manga.volumes.filter { !($0.read ?? false) }.count
        }
    }

    /// The cover column only appears once there's something to put in it,
    /// so a series whose covers were never fetched keeps its old density.
    private var showsCovers: Bool {
        manga.hasVolumeCovers
    }

    private var selectedVolumes: [Volume] {
        sortedVolumes.filter { selectedVolumeIDs.contains($0.persistentModelID) }
    }

    private func allSelected(in volumes: [Volume]) -> Bool {
        !volumes.isEmpty
            && volumes.allSatisfy { selectedVolumeIDs.contains($0.persistentModelID) }
    }

    // MARK: - Body

    var body: some View {
        // Sorted and filtered once per render; the header, empty state and
        // rows all read this instead of re-sorting.
        let displayedVolumes = displayedVolumes
        let allDisplayedSelected = allSelected(in: displayedVolumes)

        DetailCard(padding: 0) {
            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                if !selectedVolumeIDs.isEmpty {
                    bulkSelectionBar
                }

                if displayedVolumes.isEmpty {
                    Divider().overlay(Color.white.opacity(0.06))
                    ContentUnavailableView(
                        filterMode == .all ? "Brak tomów" : "Nic do pokazania",
                        systemImage: "books.vertical",
                        description: Text(
                            filterMode == .all
                                ? "Dodaj tomy w panelu po prawej."
                                : "Żaden tom nie pasuje do filtra."
                        )
                    )
                    .frame(minHeight: 220)
                } else {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(displayedVolumes.enumerated()), id: \.element.persistentModelID) { index, volume in
                                VolumeRow(
                                    volume: volume,
                                    isSelected: selectedVolumeIDs.contains(volume.persistentModelID),
                                    isAlternate: index.isMultiple(of: 2),
                                    showsCover: showsCovers,
                                    onToggleSelection: { toggleSelection(volume) },
                                    onToggleOwned: { toggleOwned(volume) },
                                    onToggleRead: { toggleRead(volume) },
                                    onEditDate: { field in
                                        switch field {
                                        case .purchase: editingDateTarget = .purchase(volume)
                                        case .read: editingDateTarget = .read(volume)
                                        case .release: editingDateTarget = .release(volume)
                                        }
                                    },
                                    onEditParts: { editingPartsTarget = PartsEditTarget(volumes: [volume]) },
                                    onJoinParts: { volume.setPartCount(1) },
                                    onDelete: { deleteVolume(volume) }
                                )
                                ForEach(volume.sortedParts, id: \.persistentModelID) { part in
                                    VolumePartRow(
                                        part: part,
                                        partCount: volume.parts.count,
                                        isAlternate: index.isMultiple(of: 2),
                                        showsCover: showsCovers,
                                        onToggleRead: { volume.markPart(part, read: !part.read) },
                                        onEditReadDate: { editingDateTarget = .partRead(part) }
                                    )
                                }
                            }
                        } header: {
                            columnHeader(allDisplayedSelected: allDisplayedSelected)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .onChange(of: manga.volumes.count) { _, _ in
            // Drop selections that point at deleted volumes.
            let existing = Set(manga.volumes.map(\.persistentModelID))
            selectedVolumeIDs = selectedVolumeIDs.intersection(existing)
        }
        .confirmationDialog(
            "Zastosować także do poprzednich tomów?",
            isPresented: $showBulkConfirm,
            titleVisibility: .visible
        ) {
            Button("Tak — oznacz wszystkie do tego tomu") { applyPendingAction(markPrevious: true) }
            Button("Nie — tylko ten tom") { applyPendingAction(markPrevious: false) }
            Button("Anuluj", role: .cancel) { pendingBulkAction = nil }
        } message: {
            Text("Możesz oznaczyć tylko ten tom albo wszystkie wcześniejsze.")
        }
        .sheet(item: $editingDateTarget) { target in
            dateEditorSheet(target)
        }
        .sheet(item: $editingPartsTarget) { target in
            PartsEditorSheet(volumes: target.volumes)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Tomy")
                .font(.headline)

            ForEach(FilterMode.allCases) { mode in
                FilterChip(title: mode.label, count: count(for: mode), isSelected: filterMode == mode) {
                    filterMode = mode
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button("Oznacz wszystkie jako kupione", systemImage: "cart") { markAllOwned() }
                Button("Oznacz wszystkie jako przeczytane", systemImage: "checkmark.circle") { markAllRead() }
                Divider()
                Button("Pobierz okładki tomów", systemImage: "photo.on.rectangle") {
                    Task { await fetchVolumeCovers() }
                }
                .disabled(isFetchingCovers || manga.volumes.isEmpty)
                Divider()
                Button("Wyczyść postęp czytania", systemImage: "arrow.counterclockwise", role: .destructive) {
                    clearReadProgress()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Akcje dla wszystkich tomów")
        }
    }

    private func columnHeader(allDisplayedSelected: Bool) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: Column.spacing) {
                SelectionCheckbox(
                    isOn: allDisplayedSelected,
                    isMixed: !allDisplayedSelected && !selectedVolumeIDs.isEmpty,
                    action: toggleSelectAllDisplayed
                )
                .help("Zaznacz widoczne tomy")

                if showsCovers {
                    Color.clear.frame(width: Column.cover, height: 1)
                }

                Text("Tom").frame(width: Column.number, alignment: .leading)
                Text("Status").frame(width: Column.status, alignment: .leading)
                Text("Cena").frame(width: Column.price, alignment: .leading)
                Spacer(minLength: 8)
                Text("Zakup").frame(width: Column.date, alignment: .leading)
                Text("Przeczytano").frame(width: Column.date, alignment: .leading)
                Text("Premiera").frame(width: Column.date, alignment: .leading)
                Color.clear.frame(width: Column.menu, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.08))
        }
        .background(Color(red: 0.075, green: 0.08, blue: 0.09))
    }

    // MARK: - Bulk selection

    private var bulkSelectionBar: some View {
        HStack(spacing: 8) {
            Text("Zaznaczono: \(selectedVolumeIDs.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            Button("Odznacz") { selectedVolumeIDs.removeAll() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            SubtleButton(title: "Kupione", systemImage: "cart") { setOwned(true, for: selectedVolumes) }
            SubtleButton(title: "Przeczytane", systemImage: "checkmark.circle") { setRead(true, for: selectedVolumes) }

            Menu {
                Button("Oznacz jako nie kupione") { setOwned(false, for: selectedVolumes) }
                Button("Oznacz jako nieprzeczytane") { setRead(false, for: selectedVolumes) }
            } label: {
                Label("Cofnij", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            SubtleButton(title: "Cena", systemImage: "banknote") {
                bulkPriceText = ""
                showBulkPricePopover = true
            }
            .popover(isPresented: $showBulkPricePopover, arrowEdge: .bottom) { bulkPricePopover }

            SubtleButton(title: "Data zakupu", systemImage: "calendar") {
                bulkPurchaseDate = .now
                showBulkPurchaseDatePopover = true
            }
            .popover(isPresented: $showBulkPurchaseDatePopover, arrowEdge: .bottom) { bulkPurchaseDatePopover }

            SubtleButton(title: "Części", systemImage: "square.split.1x2") {
                editingPartsTarget = PartsEditTarget(volumes: selectedVolumes)
            }

            SubtleButton(title: "Usuń", systemImage: "trash", tint: .red) {
                for volume in selectedVolumes {
                    deleteVolume(volume)
                }
                selectedVolumeIDs.removeAll()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.07))
    }

    private var bulkPricePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cena dla \(selectedVolumeIDs.count) tomów")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("0,00", text: $bulkPriceText)
                    .detailInput(width: 120)
                    .onSubmit(applyBulkPrice)
                Text("PLN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("Tomy, które nie są kupione, zostaną oznaczone jako kupione.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Anuluj") { showBulkPricePopover = false }
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
            volume.markOwned(true)
        }
        showBulkPricePopover = false
    }

    private var bulkPurchaseDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data zakupu dla \(selectedVolumeIDs.count) tomów")
                .font(.headline)

            CalendarPickerView(selection: $bulkPurchaseDate)

            HStack {
                Button("Anuluj") { showBulkPurchaseDatePopover = false }
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
        .frame(width: 330)
    }

    // MARK: - Date editor

    private func dateEditorSheet(_ target: EditingDateTarget) -> some View {
        let title: LocalizedStringKey
        let selection: Binding<Date>
        let clear: () -> Void

        switch target {
        case let .purchase(volume):
            title = "Data zakupu"
            selection = Binding(
                get: { volume.purchaseDate ?? .now },
                set: {
                    volume.purchaseDate = $0
                    volume.owned = true
                }
            )
            clear = { volume.purchaseDate = nil }
        case let .read(volume):
            title = "Data przeczytania"
            selection = Binding(
                get: { volume.readDate ?? .now },
                set: {
                    volume.readDate = $0
                    volume.read = true
                }
            )
            clear = { volume.readDate = nil }
        case let .release(volume):
            title = "Data premiery"
            selection = Binding(
                get: { volume.releaseDate ?? .now },
                set: { volume.releaseDate = $0 }
            )
            clear = { volume.releaseDate = nil }
        case let .partRead(part):
            title = "Data przeczytania"
            selection = Binding(
                get: { part.readDate ?? .now },
                set: { date in
                    part.readDate = date
                    part.volume?.markPart(part, read: true, on: date)
                }
            )
            clear = {
                part.readDate = nil
                part.volume?.refreshReadFromParts()
            }
        }

        return VStack(alignment: .leading, spacing: 16) {
            DetailCardTitle(title: title, systemImage: "calendar")

            CalendarPickerView(selection: selection)

            HStack(spacing: 8) {
                SubtleButton(title: "Usuń datę", systemImage: "trash", tint: .red) {
                    clear()
                    editingDateTarget = nil
                }
                Spacer()
                Button("Anuluj", role: .cancel) { editingDateTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Gotowe") { editingDateTarget = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(AppBackgroundView())
    }

    // MARK: - Selection

    private func toggleSelection(_ volume: Volume) {
        let id = volume.persistentModelID
        let isShiftHeld = NSEvent.modifierFlags.contains(.shift)

        if isShiftHeld,
           let anchor = lastSelectedVolumeID,
           let anchorIndex = displayedVolumes.firstIndex(where: { $0.persistentModelID == anchor }),
           let targetIndex = displayedVolumes.firstIndex(where: { $0.persistentModelID == id })
        {
            for volume in displayedVolumes[min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)] {
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
        let displayed = displayedVolumes
        let ids = displayed.map(\.persistentModelID)
        if allSelected(in: displayed) {
            selectedVolumeIDs.subtract(ids)
        } else {
            selectedVolumeIDs.formUnion(ids)
        }
    }

    // MARK: - Mutations

    private func setOwned(_ owned: Bool, for volumes: [Volume]) {
        for volume in volumes {
            volume.markOwned(owned)
        }
    }

    private func setRead(_ read: Bool, for volumes: [Volume]) {
        for volume in volumes {
            volume.markRead(read)
        }
    }

    private func toggleOwned(_ volume: Volume) {
        if volume.owned {
            setOwned(false, for: [volume])
        } else if shouldAskMarkPreviousOwned(upTo: volume) {
            pendingBulkAction = .markOwnedUpTo(volume)
            showBulkConfirm = true
        } else {
            setOwned(true, for: [volume])
        }
    }

    private func toggleRead(_ volume: Volume) {
        if volume.read ?? false {
            setRead(false, for: [volume])
        } else if shouldAskMarkPreviousRead(upTo: volume) {
            pendingBulkAction = .markReadUpTo(volume)
            showBulkConfirm = true
        } else {
            setRead(true, for: [volume])
        }
    }

    private func markAllOwned() {
        setOwned(true, for: manga.volumes)
    }

    private func markAllRead() {
        setRead(true, for: manga.volumes)
    }

    private func clearReadProgress() {
        setRead(false, for: manga.volumes)
    }

    // MARK: - MangaDex

    /// Pulls this series' per-volume covers. AniList only has a cover for the
    /// series, so the volume rows are filled from MangaDex instead, matched
    /// through the AniList id the series already carries.
    private func fetchVolumeCovers() async {
        guard !isFetchingCovers else { return }
        isFetchingCovers = true
        defer { isFetchingCovers = false }

        do {
            let applied = try await manga.fetchVolumeCovers()
            if applied > 0 {
                ToastService.shared.show(L("Pobrano okładki dla %lld tomów.", applied), type: .success)
            } else {
                ToastService.shared.show(L("Wszystkie tomy mają już okładki."), type: .info)
            }
        } catch MangaDexService.ServiceError.seriesNotFound {
            ToastService.shared.show(L("Nie znaleziono serii w MangaDex dla: %@", manga.title), type: .error)
        } catch {
            ToastService.shared.show(L("Nie udało się pobrać okładek tomów."), type: .error)
            print("MangaDex covers error:", error)
        }
    }

    private func deleteVolume(_ volume: Volume) {
        manga.volumes.removeAll { $0.persistentModelID == volume.persistentModelID }
        modelContext.delete(volume)
    }

    private func applyPendingAction(markPrevious: Bool) {
        guard let action = pendingBulkAction else { return }
        defer { pendingBulkAction = nil }

        switch action {
        case let .markOwnedUpTo(target):
            let volumes = markPrevious
                ? manga.volumes.filter { $0.number <= target.number }
                : [target]
            setOwned(true, for: volumes)

        case let .markReadUpTo(target):
            if markPrevious {
                let lastPreviouslyRead = manga.volumes
                    .filter { $0.number < target.number && ($0.read ?? false) }
                    .map(\.number)
                    .max() ?? 0
                let volumes = manga.volumes.filter {
                    $0.number > lastPreviouslyRead && $0.number <= target.number
                }
                setRead(true, for: volumes)
            } else {
                setRead(true, for: [target])
            }
        }
    }

    private func shouldAskMarkPreviousOwned(upTo target: Volume) -> Bool {
        guard let previous = manga.volumes.first(where: { $0.number == target.number - 1 }) else {
            return false
        }
        return !previous.owned
    }

    private func shouldAskMarkPreviousRead(upTo target: Volume) -> Bool {
        guard let previous = manga.volumes.first(where: { $0.number == target.number - 1 }) else {
            return false
        }
        return previous.owned && !(previous.read ?? false)
    }
}

// MARK: - Row

private enum DateField {
    case purchase, read, release
}

private struct VolumeRow: View {
    let volume: Volume
    let isSelected: Bool
    let isAlternate: Bool
    let showsCover: Bool
    let onToggleSelection: () -> Void
    let onToggleOwned: () -> Void
    let onToggleRead: () -> Void
    let onEditDate: (DateField) -> Void
    let onEditParts: () -> Void
    let onJoinParts: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private typealias Column = VolumesTableView.Column

    private var isRead: Bool {
        volume.read ?? false
    }

    /// "2/3" while a split volume is under way; nothing otherwise.
    private var partsProgress: String? {
        guard volume.isSplit, !isRead else { return nil }
        return "\(volume.readPartCount)/\(volume.parts.count)"
    }

    var body: some View {
        HStack(spacing: Column.spacing) {
            SelectionCheckbox(isOn: isSelected, action: onToggleSelection)

            if showsCover {
                CoverImageView(url: volume.coverURL.flatMap(URL.init(string:)), cornerRadius: 3)
                    .frame(width: Column.cover, height: Column.cover * 1.46)
            }

            Text("#\(volume.number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(volume.owned ? .primary : .secondary)
                .frame(width: Column.number, alignment: .leading)

            HStack(spacing: 6) {
                StatusChip(title: "Kupiony", icon: "cart.fill", isActive: volume.owned, action: onToggleOwned)
                StatusChip(title: "Przeczytany", icon: "checkmark.circle.fill", isActive: isRead, detail: partsProgress, action: onToggleRead)
            }
            .frame(width: Column.status, alignment: .leading)

            priceField
                .frame(width: Column.price, alignment: .leading)

            Spacer(minLength: 8)

            dateCell(icon: "cart", date: volume.purchaseDate, help: "Data zakupu") { onEditDate(.purchase) }
            dateCell(icon: "checkmark.circle", date: volume.readDate, help: "Data przeczytania") { onEditDate(.read) }
            dateCell(icon: "sparkles", date: volume.releaseDate, help: "Data premiery") { onEditDate(.release) }

            Menu {
                Button("Ustaw datę zakupu") { onEditDate(.purchase) }
                Button("Ustaw datę przeczytania") { onEditDate(.read) }
                Button("Ustaw datę premiery") { onEditDate(.release) }
                Divider()
                Button(volume.isSplit ? "Zmień podział na części…" : "Podziel na części…", action: onEditParts)
                if volume.isSplit {
                    Button("Usuń podział", action: onJoinParts)
                }
                Divider()
                Button("Usuń tom", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Column.menu, height: 26)
                    .background(Color.white.opacity(isHovered ? 0.08 : 0), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Column.menu)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return .green.opacity(0.12)
        }
        if isHovered {
            return .white.opacity(0.05)
        }
        if isRead {
            return .green.opacity(isAlternate ? 0.05 : 0.03)
        }
        return .white.opacity(isAlternate ? 0.025 : 0)
    }

    private var priceField: some View {
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
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(volume.owned ? 0.06 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(volume.owned ? 1 : 0.45)
        .disabled(!volume.owned)
        .help(volume.owned ? "Cena tomu" : "Oznacz tom jako kupiony, aby wpisać cenę")
    }

    private func dateCell(icon: String, date: Date?, help: String, action: @escaping () -> Void) -> some View {
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
            .frame(width: Column.date, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// One part of a split volume, under its volume's row: index, read toggle
/// and read date, in the columns of the row above.
private struct VolumePartRow: View {
    let part: VolumePart
    let partCount: Int
    let isAlternate: Bool
    let showsCover: Bool
    let onToggleRead: () -> Void
    let onEditReadDate: () -> Void

    @State private var isHovered = false

    private typealias Column = VolumesTableView.Column

    var body: some View {
        HStack(spacing: Column.spacing) {
            Color.clear.frame(width: Column.checkbox, height: 1)

            if showsCover {
                Color.clear.frame(width: Column.cover, height: 1)
            }

            HStack(spacing: 3) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("\(part.index)/\(partCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: Column.number, alignment: .leading)

            StatusChip(title: "Przeczytana", icon: "checkmark.circle.fill", isActive: part.read, action: onToggleRead)
                .frame(width: Column.status, alignment: .leading)

            Color.clear.frame(width: Column.price, height: 1)

            Spacer(minLength: 8)

            Color.clear.frame(width: Column.date, height: 1)

            Button(action: onEditReadDate) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(part.readDate == nil ? .tertiary : .secondary)
                        .frame(width: 14)
                    Text(part.readDate?.yyyyMMdd() ?? "—")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(part.readDate == nil ? .tertiary : .primary)
                }
                .frame(width: Column.date, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Data przeczytania")

            Color.clear.frame(width: Column.date, height: 1)

            Menu {
                Button("Ustaw datę przeczytania", action: onEditReadDate)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Column.menu, height: 26)
                    .background(Color.white.opacity(isHovered ? 0.08 : 0), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Column.menu)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHovered {
            return .white.opacity(0.05)
        }
        if part.read {
            return .green.opacity(isAlternate ? 0.05 : 0.03)
        }
        return .white.opacity(isAlternate ? 0.025 : 0)
    }
}

// MARK: - Parts editor

/// How many original volumes the selected volumes bind together. One part
/// joins a split volume back.
private struct PartsEditorSheet: View {
    let volumes: [Volume]

    @Environment(\.dismiss) private var dismiss
    @State private var partCount: Int

    init(volumes: [Volume]) {
        self.volumes = volumes
        // Opens on the largest split among the volumes, or two parts.
        _partCount = State(initialValue: max(volumes.map(\.parts.count).max() ?? 0, 2))
    }

    private var anySplit: Bool {
        volumes.contains(where: \.isSplit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailCardTitle(title: "Podziel na części", systemImage: "square.split.1x2")

            if volumes.count == 1, let volume = volumes.first {
                Text("Tom \(volume.number)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Zaznaczono: \(volumes.count)")
                    .font(.subheadline.weight(.semibold))
            }

            Stepper(value: $partCount, in: 2 ... 50) {
                HStack {
                    Text("Liczba części")
                    Spacer()
                    Text("\(partCount)")
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                }
            }

            Text("Wydanie zbiorcze (np. deluxe) mieści kilka oryginalnych tomów. Każdą część oznaczysz jako przeczytaną osobno, a postęp liczy się częściami.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if anySplit {
                    SubtleButton(title: "Usuń podział", systemImage: "arrow.triangle.merge", tint: .red) {
                        for volume in volumes {
                            volume.setPartCount(1)
                        }
                        dismiss()
                    }
                }
                Spacer()
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Zastosuj") {
                    for volume in volumes {
                        volume.setPartCount(partCount)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(AppBackgroundView())
    }
}

private struct StatusChip: View {
    let title: LocalizedStringKey
    let icon: String
    let isActive: Bool
    /// Small trailing note, e.g. how many parts are read.
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.green)
                }
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : .secondary)
            .background(isActive ? Color.green : Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(isActive ? Color.clear : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Kliknij, aby cofnąć" : "Kliknij, aby oznaczyć")
    }
}

private struct SelectionCheckbox: View {
    let isOn: Bool
    var isMixed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.square.fill" : (isMixed ? "minus.square.fill" : "square"))
                .font(.system(size: 15))
                .foregroundStyle(isOn || isMixed ? Color.green : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
