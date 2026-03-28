import SwiftData
import SwiftUI

struct MangaDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var manga: Manga

    @State private var newVolumeNumber = ""
    @State private var bulkFrom = ""
    @State private var bulkTo = ""
    @State private var showOnlyMissing = false
    @State private var showOnlyNonRead = false
    @State private var showBulkConfirm = false
    @State private var pendingBulkAction: BulkAction?
    @State private var editingDateTarget: EditingDateTarget?
    @FocusState private var titleFocused: Bool

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

    private var defaultTitle = "Nowa manga"

    private var pendingVolumeNumber: Int? {
        switch pendingBulkAction {
        case .markOwnedUpTo(let v): return v.number
        case .markReadUpTo(let v): return v.number
        case nil: return nil
        }
    }

    var sortedVolumes: [Volume] {
        manga.volumes.sorted { $0.number < $1.number }
    }

    var displayedVolumes: [Volume] {
        if showOnlyMissing {
            return sortedVolumes.filter { !$0.owned }
        } else if showOnlyNonRead {
            return sortedVolumes.filter { !($0.read ?? false) }
        }

        return sortedVolumes
    }

    init(manga: Manga) {
        self.manga = manga
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Tytuł", text: $manga.title)
                    .font(.title2)
                    .focused($titleFocused)
                    .onChange(of: titleFocused) { _, focused in
                        if focused && manga.title == defaultTitle {
                            manga.title = ""
                        }
                    }
                Spacer()
            }

            TextField("Notatka (opcjonalnie)", text: $manga.note)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .top, spacing: 16) {
                CachedAsyncImage(url: URL(string: manga.coverURL ?? ""))
                    .frame(width: 140, height: 200)
                    .shadow(radius: 2)
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "URL okładki",
                        text: Binding(
                            get: { manga.coverURL ?? "" },
                            set: { manga.coverURL = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(
                        "Wklej link do obrazka (jpg/png/webp). Cache zapisze go na dysku."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }

            HStack(alignment: .center, spacing: 12) {
                Toggle("Pokaż tylko brakujące", isOn: $showOnlyMissing).tint(
                    .green
                )
                Toggle("Pokaż nieprzeczytane", isOn: $showOnlyNonRead).tint(
                    .green
                )

                Spacer()

                TextField("Nr tomu", text: $newVolumeNumber)
                    .frame(width: 110)
                    .textFieldStyle(.roundedBorder)

                Button("Dodaj tom") { addSingleVolume() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            GroupBox("Dodaj zakres tomów") {
                HStack {
                    TextField("Od", text: $bulkFrom)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                    Text("—")
                    TextField("Do", text: $bulkTo)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)

                    Button("Dodaj") { addBulkVolumes() }

                    Spacer()

                    Text("Tip: dodaj np. 1–30 na start.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Divider()

            Table(displayedVolumes) {
                TableColumn("Tom") { v in
                    Text("#\(v.number)")
                }
                .width(80)

                TableColumn("Kupiony") { v in
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
                    .tint(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(90)

                TableColumn("Przeczytany") { v in
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
                    .tint(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(90)

                TableColumn("Data zakupu") { v in
                    HStack(spacing: 6) {
                        if let d = v.purchaseDate {
                            Text(d, format: .dateTime.day().month().year())
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            editingDateTarget = .purchase(v)
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .width(140)

                TableColumn("Data przeczytania") { v in
                    HStack(spacing: 6) {
                        if let d = v.readDate {
                            Text(d, format: .dateTime.day().month().year())
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            editingDateTarget = .read(v)
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .width(140)

                TableColumn("Cena") { v in
                    HStack {
                        TextField(
                            "",
                            value: Bindable(v).price,
                            format: .number.precision(.fractionLength(2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Text("PLN").foregroundStyle(.secondary).fontWeight(
                            .bold
                        )
                    }
                }
                .width(140)

                TableColumn("") { v in
                    Button(role: .destructive) {
                        deleteVolume(v)
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .width(40)
            }
            .frame(minHeight: 300)

            Spacer()
        }
        .padding()
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
            .padding()
            .frame(minWidth: 320, minHeight: 320)
        }
    }

    private func addSingleVolume() {
        guard let n = Int(newVolumeNumber.trimmingCharacters(in: .whitespaces)),
            n > 0
        else { return }

        guard !manga.volumes.contains(where: { $0.number == n }) else { return }

        let v = Volume(number: n, owned: false, manga: manga)
        manga.volumes.append(v)
        newVolumeNumber = ""
    }

    private func addBulkVolumes() {
        guard let from = Int(bulkFrom.trimmingCharacters(in: .whitespaces)),
            let to = Int(bulkTo.trimmingCharacters(in: .whitespaces)),
            from >= 0, to >= 0
        else { return }

        let a = min(from, to)
        let b = max(from, to)

        let existing = Set(manga.volumes.map { $0.number })
        for n in a...b where !existing.contains(n) {
            manga.volumes.append(Volume(number: n, owned: false, manga: manga))
        }

        bulkFrom = ""
        bulkTo = ""
    }

    private func deleteVolume(_ v: Volume) {
        manga.volumes.removeAll { $0.persistentModelID == v.persistentModelID }
        modelContext.delete(v)
    }

    private func applyPendingAction(markPrevious: Bool) {
        guard let action = pendingBulkAction else { return }
        defer { pendingBulkAction = nil }

        switch action {
        case .markOwnedUpTo(let target):
            let maxNumber = target.number
            for vol in manga.volumes {
                if markPrevious {
                    if vol.number <= maxNumber {
                        vol.owned = true
                        if vol.purchaseDate == nil { vol.purchaseDate = .now }
                    }
                } else if vol.persistentModelID == target.persistentModelID {
                    vol.owned = true
                    if vol.purchaseDate == nil { vol.purchaseDate = .now }
                }
            }

        case .markReadUpTo(let target):
            let maxNumber = target.number
            for vol in manga.volumes {
                if markPrevious {
                    if vol.number <= maxNumber {
                        vol.read = true
                    }
                } else if vol.persistentModelID == target.persistentModelID {
                    vol.read = true
                }
            }
        }
    }

    private func shouldAskMarkPreviousOwned(upTo target: Volume) -> Bool {
        guard
            let previous = manga.volumes.first(where: {
                $0.number == target.number - 1
            })
        else {
            return false
        }

        return !previous.owned
    }

    private func shouldAskMarkPreviousRead(upTo target: Volume) -> Bool {
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
