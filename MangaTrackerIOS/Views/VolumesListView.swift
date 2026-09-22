import SwiftData
import SwiftUI

/// The series' volumes: filter chips and one row per volume with
/// owned/read toggles, plus a row per part under a split volume. Tapping a
/// volume opens the full editor, where the split is set up.
struct VolumesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var manga: Manga

    @State private var filterMode: FilterMode = .all
    @State private var pendingBulkAction: BulkAction?
    @State private var editingVolume: Volume?

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

    private enum BulkAction: Identifiable {
        case markOwnedUpTo(Volume)
        case markReadUpTo(Volume)

        var id: String {
            switch self {
            case let .markOwnedUpTo(volume): "owned-\(volume.persistentModelID)"
            case let .markReadUpTo(volume): "read-\(volume.persistentModelID)"
            }
        }
    }

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

    var body: some View {
        let displayedVolumes = displayedVolumes

        DetailCard(padding: 0) {
            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                Divider().overlay(Color.white.opacity(0.06))

                if displayedVolumes.isEmpty {
                    ContentUnavailableView(
                        filterMode == .all ? "Brak tomów" : "Nic do pokazania",
                        systemImage: "books.vertical",
                        description: Text(
                            filterMode == .all
                                ? "Dodaj tomy w sekcji poniżej."
                                : "Żaden tom nie pasuje do filtra."
                        )
                    )
                    .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(displayedVolumes.enumerated()), id: \.element.persistentModelID) { index, volume in
                            VolumeRow(
                                volume: volume,
                                isAlternate: index.isMultiple(of: 2),
                                onToggleOwned: { toggleOwned(volume) },
                                onToggleRead: { toggleRead(volume) },
                                onOpen: { editingVolume = volume }
                            )
                            .contextMenu {
                                Button("Edytuj tom…", systemImage: "pencil") { editingVolume = volume }
                                Divider()
                                Button("Usuń tom", systemImage: "trash", role: .destructive) { deleteVolume(volume) }
                            }
                            ForEach(volume.sortedParts, id: \.persistentModelID) { part in
                                VolumePartRow(
                                    part: part,
                                    partCount: volume.parts.count,
                                    isAlternate: index.isMultiple(of: 2),
                                    onToggleRead: { volume.markPart(part, read: !part.read) }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .confirmationDialog(
            "Zastosować także do poprzednich tomów?",
            isPresented: Binding(
                get: { pendingBulkAction != nil },
                set: {
                    if !$0 {
                        pendingBulkAction = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingBulkAction
        ) { action in
            Button("Tak — oznacz wszystkie do tego tomu") { apply(action, markPrevious: true) }
            Button("Nie — tylko ten tom") { apply(action, markPrevious: false) }
            Button("Anuluj", role: .cancel) {}
        } message: { _ in
            Text("Możesz oznaczyć tylko ten tom albo wszystkie wcześniejsze.")
        }
        .sheet(item: $editingVolume) { volume in
            VolumeEditSheet(volume: volume, onDelete: { deleteVolume(volume) })
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tomy")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Oznacz wszystkie jako kupione", systemImage: "cart") { setOwned(true, for: manga.volumes) }
                    Button("Oznacz wszystkie jako przeczytane", systemImage: "checkmark.circle") { setRead(true, for: manga.volumes) }
                    Divider()
                    Button("Wyczyść postęp czytania", systemImage: "arrow.counterclockwise", role: .destructive) {
                        setRead(false, for: manga.volumes)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FilterMode.allCases) { mode in
                        FilterChip(title: mode.label, count: count(for: mode), isSelected: filterMode == mode) {
                            filterMode = mode
                        }
                    }
                }
            }
            .scrollClipDisabled()
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
        } else if let previous = manga.volumes.first(where: { $0.number == volume.number - 1 }), !previous.owned {
            pendingBulkAction = .markOwnedUpTo(volume)
        } else {
            setOwned(true, for: [volume])
        }
    }

    private func toggleRead(_ volume: Volume) {
        if volume.read ?? false {
            setRead(false, for: [volume])
        } else if let previous = manga.volumes.first(where: { $0.number == volume.number - 1 }),
                  previous.owned, !(previous.read ?? false)
        {
            pendingBulkAction = .markReadUpTo(volume)
        } else {
            setRead(true, for: [volume])
        }
    }

    private func apply(_ action: BulkAction, markPrevious: Bool) {
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

    private func deleteVolume(_ volume: Volume) {
        editingVolume = nil
        manga.volumes.removeAll { $0.persistentModelID == volume.persistentModelID }
        modelContext.delete(volume)
    }
}

// MARK: - Row

private struct VolumeRow: View {
    let volume: Volume
    let isAlternate: Bool
    let onToggleOwned: () -> Void
    let onToggleRead: () -> Void
    let onOpen: () -> Void

    private var isRead: Bool {
        volume.read ?? false
    }

    /// "2/3" while a split volume is under way; nothing otherwise.
    private var partsProgress: String? {
        guard volume.isSplit, !isRead else { return nil }
        return "\(volume.readPartCount)/\(volume.parts.count)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(volume.number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(volume.owned ? .primary : .secondary)
                .frame(width: 40, alignment: .leading)

            StatusChip(icon: "cart.fill", title: "Kupiony", isActive: volume.owned, action: onToggleOwned)
            StatusChip(icon: "checkmark.circle.fill", title: "Przeczytany", isActive: isRead, detail: partsProgress, action: onToggleRead)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if volume.owned, let price = volume.price, price > 0 {
                    Text(price, format: .currency(code: "PLN"))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var rowBackground: Color {
        if isRead {
            return .green.opacity(isAlternate ? 0.05 : 0.03)
        }
        return .white.opacity(isAlternate ? 0.025 : 0)
    }
}

/// One part of a split volume, indented under its volume's row.
private struct VolumePartRow: View {
    let part: VolumePart
    let partCount: Int
    let isAlternate: Bool
    let onToggleRead: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("\(part.index)/\(partCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, alignment: .leading)
            .padding(.leading, 6)

            StatusChip(icon: "checkmark.circle.fill", title: "Przeczytana", isActive: part.read, action: onToggleRead)

            Spacer(minLength: 4)

            if let readDate = part.readDate {
                Text(readDate.yyyyMMdd())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(part.read ? Color.green.opacity(isAlternate ? 0.05 : 0.03) : Color.white.opacity(isAlternate ? 0.025 : 0))
    }
}

private struct StatusChip: View {
    let icon: String
    let title: LocalizedStringKey
    let isActive: Bool
    /// Shown instead of the title when set — how many parts are read;
    /// the row is too narrow for both next to the price.
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                if let detail {
                    Text(detail)
                        .monospacedDigit()
                        .foregroundStyle(Color.green)
                } else {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : .secondary)
            .background(isActive ? Color.green : Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(isActive ? Color.clear : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

/// Everything about one volume: status, price, the three dates, and the
/// split into parts with each part's own read state.
private struct VolumeEditSheet: View {
    @Bindable var volume: Volume
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Kupiony", isOn: Binding(
                        get: { volume.owned },
                        set: { volume.markOwned($0) }
                    ))
                    Toggle("Przeczytany", isOn: Binding(
                        get: { volume.read ?? false },
                        set: { volume.markRead($0) }
                    ))
                }

                Section {
                    Stepper(value: Binding(
                        get: { volume.unitCount },
                        set: { volume.setPartCount($0) }
                    ), in: 1 ... 50) {
                        HStack {
                            Text("Liczba części")
                            Spacer()
                            Text(volume.isSplit ? "\(volume.parts.count)" : "—")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    ForEach(volume.sortedParts, id: \.persistentModelID) { part in
                        Toggle(isOn: Binding(
                            get: { part.read },
                            set: { volume.markPart(part, read: $0) }
                        )) {
                            HStack {
                                Text("Część \(part.index)")
                                Spacer()
                                if let readDate = part.readDate {
                                    Text(readDate.yyyyMMdd())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                } header: {
                    Text("Części")
                } footer: {
                    Text("Wydanie zbiorcze (np. deluxe) mieści kilka oryginalnych tomów. Każdą część oznaczysz jako przeczytaną osobno, a postęp liczy się częściami.")
                }

                Section("Cena") {
                    HStack {
                        TextField("0,00", value: $volume.price, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                        Text("PLN")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!volume.owned)
                    .foregroundStyle(volume.owned ? .primary : .secondary)
                }

                Section("Daty") {
                    OptionalDateRow(title: "Zakup", date: $volume.purchaseDate) { volume.markOwned(true) }
                    OptionalDateRow(title: "Przeczytano", date: $volume.readDate) { volume.markRead(true) }
                    OptionalDateRow(title: "Premiera", date: $volume.releaseDate)
                }

                Section {
                    Button("Usuń tom", role: .destructive) { showDeleteConfirm = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackgroundView())
            .navigationTitle("Tom \(volume.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .confirmationDialog("Usunąć ten tom?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Usuń", role: .destructive) {
                    dismiss()
                    onDelete()
                }
                Button("Anuluj", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }
}

/// A date that can be unset: a toggle reveals the picker.
private struct OptionalDateRow: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var onSet: () -> Void = {}

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { isOn in
                date = isOn ? .now : nil
                if isOn {
                    onSet()
                }
            }
        ))
        if let current = date {
            DatePicker(
                title,
                selection: Binding(
                    get: { current },
                    set: { date = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }
}
