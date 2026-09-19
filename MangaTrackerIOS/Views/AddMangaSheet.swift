import SwiftData
import SwiftUI

/// New series: a title, optionally filled in from AniList (volumes, cover,
/// author, synopsis…) before it's saved. Calls `onAdded` with the new
/// series so the caller can open it.
struct AddMangaSheet: View {
    let nextSortOrder: Int
    let onAdded: (Manga) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var fetchFromAniList = true
    @State private var addAsPlanned = false
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tytuł", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    Text("Najlepiej tytuł angielski albo romaji — tak, jak w AniList.")
                }

                Section {
                    Toggle("Pobierz dane z AniList", isOn: $fetchFromAniList)
                    Toggle("Dodaj jako planowaną", isOn: $addAsPlanned)
                } footer: {
                    Text("AniList uzupełni okładkę, autora, opis i listę tomów. Zawsze możesz to odświeżyć później.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackgroundView())
            .navigationTitle("Nowa manga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Dodaj", action: add)
                            .disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .onAppear { titleFocused = true }
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }

            let manga = Manga(title: trimmedTitle, sortOrder: nextSortOrder, isPlanned: addAsPlanned)
            if fetchFromAniList {
                do {
                    if let info = try await AniListService.fetchMangaInfo(title: trimmedTitle) {
                        manga.applyAniListInfo(info)
                    } else {
                        ToastService.shared.show(L("Nie znaleziono danych w AniList dla: %@", trimmedTitle), type: .info)
                    }
                } catch {
                    ToastService.shared.show(L("Nie udało się pobrać danych z AniList."), type: .error)
                }
            }

            modelContext.insert(manga)
            dismiss()
            onAdded(manga)
        }
    }
}

/// Title, author and cover of an existing series.
struct EditMangaSheet: View {
    @Bindable var manga: Manga

    @Environment(\.dismiss) private var dismiss
    @State private var isFetchingCover = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tytuł") {
                    TextField("Tytuł", text: $manga.title)
                }

                Section("Autor") {
                    TextField(
                        "Autor",
                        text: Binding(
                            get: { manga.aniListAuthor ?? "" },
                            set: { manga.aniListAuthor = $0.isEmpty ? nil : $0 }
                        )
                    )
                }

                Section {
                    TextField(
                        "https://…",
                        text: Binding(
                            get: { manga.coverURL ?? "" },
                            set: { manga.coverURL = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        Task { await fetchCoverFromAniList() }
                    } label: {
                        HStack {
                            Label("Pobierz z AniList", systemImage: "arrow.down.circle")
                            if isFetchingCover {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isFetchingCover || manga.title.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Okładka")
                } footer: {
                    Text("Wklej link do obrazka (jpg, png, webp). Miniatura zostanie zapisana lokalnie.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackgroundView())
            .navigationTitle("Edytuj serię")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
    }

    private func fetchCoverFromAniList() async {
        let title = manga.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

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
        }
    }
}
