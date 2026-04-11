import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Manga.sortOrder, order: .forward)
    private var mangas: [Manga]

    @State private var selectedManga: Manga?
    @State private var searchText = ""
    @State private var showDashboard = false

    var filteredMangas: [Manga] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mangas
        }
        return mangas.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var mangaCount: Int {
        mangas.count
    }

    private var totalPaid: Double {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    private var ownedVolumesCount: Int {
        mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }
            .count
    }

    private var totalReadPercent: Double {
        let ownedVolumes =
            mangas
            .flatMap { $0.volumes }
            .filter { $0.owned }

        guard !ownedVolumes.isEmpty else { return 0 }

        let readCount =
            ownedVolumes
            .filter { $0.read == true }
            .count

        return (Double(readCount) / Double(ownedVolumes.count)) * 100
    }

    private func readPercent(for manga: Manga) -> Double {
        let total = manga.volumes.count
        guard total > 0 else { return 0 }

        let readCount = manga.volumes.filter { $0.read == true }.count
        return (Double(readCount) / Double(total)) * 100
    }

    private func totalPaidForManga(for manga: Manga) -> Double {
        manga.volumes
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {

                HStack(spacing: 12) {
                    Text("Serie: \(mangaCount)")

                    Text("•")

                    Text("Tomy: \(ownedVolumesCount)")

                    Text("•")

                    Text("Wydano:")
                    Text(
                        totalPaid,
                        format: .currency(
                            code: Locale.current.currency?.identifier ?? "PLN"
                        )
                    )
                    .monospacedDigit()

                    Text("•")

                    Text("Przeczytano:")
                    Text("\(totalReadPercent, specifier: "%.1f")%")

                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()

                List(selection: $selectedManga) {
                    ForEach(filteredMangas) { manga in
                        HStack(spacing: 10) {
                            CachedAsyncImage(
                                url: URL(string: manga.coverURL ?? ""),
                                cornerRadius: 6
                            )
                            .frame(width: 40, height: 56)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(manga.title)
                                        .font(.headline)

                                    Spacer()

                                    let percent = readPercent(for: manga)
                                    let allVolumes = manga.volumes.count
                                    let read = manga.volumes.filter {
                                        $0.read == true
                                    }.count

                                    if percent >= 100 {
                                        Image(
                                            systemName: "checkmark.circle.fill"
                                        )
                                        .foregroundStyle(.green)
                                    } else {
                                        Text("\(read)/\(allVolumes)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if !manga.note.isEmpty {
                                    Text(manga.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                ProgressView(
                                    value: readPercent(for: manga),
                                    total: 100
                                )
                                .tint(.green)
                                .scaleEffect(y: 0.6)

                                Text(
                                    totalPaidForManga(for: manga),
                                    format: .currency(code: "PLN")
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                                Spacer()
                            }
                        }
                        .tag(manga)
                        .contextMenu {
                            Button("Przesuń wyżej") { moveMangaUp(manga) }
                            Button("Przesuń niżej") { moveMangaDown(manga) }
                            Divider()
                            Button("Usuń", role: .destructive) {
                                deleteManga(manga)
                            }
                        }
                    }
                    .onMove(perform: moveMangas)
                }
            }.navigationTitle("Mangi")
                .searchable(text: $searchText, prompt: "Szukaj tytułu…")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showDashboard = true
                        } label: {
                            Label("Dashboard", systemImage: "chart.xyaxis.line")
                        }
                        .help("Otworz dashboard")

                        Button {
                            addManga()
                        } label: {
                            Label("Dodaj", systemImage: "plus")
                        }
                    }
                }
                .onAppear {
                    if selectedManga == nil {
                        selectedManga = filteredMangas.first
                    }
                }
                .onChange(of: mangas) { _, newValue in
                    if selectedManga == nil {
                        selectedManga = newValue.first
                    }
                }
        } detail: {
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
                    .id(selectedManga.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Wybierz mangę",
                    systemImage: "books.vertical",
                    description: Text("Albo dodaj nową po lewej.")
                )
            }
        }
        .sheet(isPresented: $showDashboard) {
            DashboardView(mangas: mangas)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func addManga() {
        let nextOrder = (mangas.compactMap(\.sortOrder).max() ?? -1) + 1
        let m = Manga(title: "Nowa manga", sortOrder: nextOrder)
        modelContext.insert(m)
        selectedManga = m
    }

    private func deleteManga(_ manga: Manga) {
        if selectedManga?.persistentModelID == manga.persistentModelID {
            selectedManga = nil
        }
        modelContext.delete(manga)
    }

    private func moveMangas(from source: IndexSet, to destination: Int) {
        var reordered = mangas

        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, manga) in reordered.enumerated() {
            manga.sortOrder = index
        }

        do {
            try modelContext.save()
        } catch {
            print("Error while saving sort order: \(error)")
        }
    }

    private func moveMangaUp(_ manga: Manga) {
        guard
            let index = mangas.firstIndex(where: {
                $0.persistentModelID == manga.persistentModelID
            }),
            index > 0
        else { return }

        swapSortOrder(at: index, and: index - 1)
    }

    private func moveMangaDown(_ manga: Manga) {
        guard
            let index = mangas.firstIndex(where: {
                $0.persistentModelID == manga.persistentModelID
            }),
            index < mangas.count - 1
        else { return }

        swapSortOrder(at: index, and: index + 1)
    }

    private func swapSortOrder(at firstIndex: Int, and secondIndex: Int) {
        let first = mangas[firstIndex]
        let second = mangas[secondIndex]

        let temp = first.sortOrder
        first.sortOrder = second.sortOrder
        second.sortOrder = temp

        do {
            try modelContext.save()
        } catch {
            print("Error while changing sort order: \(error)")
        }
    }
}
