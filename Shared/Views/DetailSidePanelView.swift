import SwiftUI

/// Add volumes, personal note, synopsis. The right column of the detail
/// page on the Mac; stacked under the volumes on the phone.
struct DetailSidePanelView: View {
    @Bindable var manga: Manga

    @State private var newVolumeNumber = ""
    @State private var bulkFrom = ""
    @State private var bulkTo = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            addVolumesCard
            noteCard
            summaryCard
        }
    }

    // MARK: - Add volumes

    private var addVolumesCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Dodaj tomy", systemImage: "plus.square.on.square")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pojedynczy tom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Nr", text: $newVolumeNumber)
                            .detailInput()
                            .numericKeyboard()
                            .onSubmit(addSingleVolume)
                            .onChange(of: newVolumeNumber) { _, _ in validationMessage = nil }
                        AccentButton(title: "Dodaj", systemImage: "plus", action: addSingleVolume)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Zakres")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Od", text: $bulkFrom)
                            .detailInput()
                            .numericKeyboard()
                        Text("–")
                            .foregroundStyle(.tertiary)
                        TextField("Do", text: $bulkTo)
                            .detailInput()
                            .numericKeyboard()
                            .onSubmit(addBulkVolumes)
                        SubtleButton(title: "Dodaj", systemImage: "square.stack.3d.up", action: addBulkVolumes)
                    }
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("Tip: zakres 1–30 doda wszystkie brakujące numery.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func addSingleVolume() {
        validationMessage = nil
        guard let number = Int(newVolumeNumber.trimmingCharacters(in: .whitespaces)), number > 0 else {
            validationMessage = L("Podaj numer tomu.")
            return
        }
        guard !manga.volumes.contains(where: { $0.number == number }) else {
            validationMessage = L("Tom %lld już istnieje.", number)
            return
        }
        manga.volumes.append(Volume(number: number, owned: false, manga: manga))
        newVolumeNumber = ""
    }

    private func addBulkVolumes() {
        validationMessage = nil
        guard let from = Int(bulkFrom.trimmingCharacters(in: .whitespaces)),
              let to = Int(bulkTo.trimmingCharacters(in: .whitespaces)),
              from > 0, to > 0
        else {
            validationMessage = L("Podaj zakres, np. 1–30.")
            return
        }

        let existing = Set(manga.volumes.map(\.number))
        var added = 0
        for number in min(from, to) ... max(from, to) where !existing.contains(number) {
            manga.volumes.append(Volume(number: number, owned: false, manga: manga))
            added += 1
        }

        bulkFrom = ""
        bulkTo = ""
        if added == 0 {
            validationMessage = L("Wszystkie tomy z tego zakresu już są.")
        }
    }

    // MARK: - Note & summary

    private var noteCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailCardTitle(title: "Notatka", systemImage: "pencil.line")

                TextField("Dodaj krótką notatkę…", text: $manga.note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(3 ... 8)
            }
        }
    }

    private var summaryCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 12) {
                DetailCardTitle(title: "Opis", systemImage: "text.book.closed")

                TextEditor(text: $manga.summary.orEmpty())
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 320)
                    .overlay(alignment: .topLeading) {
                        if (manga.summary ?? "").isEmpty {
                            Text("Dodaj opis albo odśwież dane z AniList.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}

private extension View {
    /// Number pad on the phone; no-op on the Mac.
    func numericKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
        #else
            self
        #endif
    }
}
