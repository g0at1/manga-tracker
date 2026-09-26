import SwiftData
import SwiftUI

struct ShelfWindowView: View {
    @Query(sort: \Manga.sortOrder, order: .forward)
    private var mangas: [Manga]

    var body: some View {
        ShelfView(mangas: mangas)
    }
}

/// Every owned volume, one shelf per series, drawn as covers side by side.
struct ShelfView: View {
    let mangas: [Manga]

    @AppStorage("shelfHideSpinOffs") private var hideSpinOffs = false
    @AppStorage("shelfCoverHeight") private var coverHeight: Double = 150
    @State private var isFetchingCovers = false

    /// Series with something on the shelf, in library order, each with its
    /// owned volumes by number. Sold and planned series have nothing there.
    private var shelves: [(manga: Manga, volumes: [Volume])] {
        mangas.compactMap { manga in
            guard manga.isSold != true, manga.isPlanned != true,
                  !hideSpinOffs || manga.isSpinOff != true
            else { return nil }
            let owned = manga.volumes.filter(\.owned).sorted { $0.number < $1.number }
            return owned.isEmpty ? nil : (manga, owned)
        }
    }

    var body: some View {
        let shelves = shelves
        let volumes = shelves.flatMap(\.volumes)
        let withCover = volumes.count { !($0.coverURL ?? "").isEmpty }

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header(missingCovers: volumes.count - withCover)
                tiles(volumes: volumes, series: shelves.count, withCover: withCover)

                if shelves.isEmpty {
                    DetailCard {
                        ContentUnavailableView(
                            "Półka jest pusta",
                            systemImage: "books.vertical",
                            description: Text("Oznacz tomy jako posiadane, aby pojawiły się na półce.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                } else {
                    ForEach(shelves, id: \.manga.persistentModelID) { shelf in
                        ShelfRow(manga: shelf.manga, volumes: shelf.volumes, coverHeight: coverHeight)
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(AppBackgroundView())
        .navigationTitle("Półka")
        .onAppear {
            WindowManager.ensureComfortableSize(windowID: "shelf", minWidth: 1100, minHeight: 820)
        }
    }

    // MARK: - Header & tiles

    private func header(missingCovers: Int) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Półka")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Twoja kolekcja, tom po tomie")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            Toggle("Ukryj spin-offy", isOn: $hideSpinOffs)
                .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $coverHeight, in: 100 ... 240)
                    .frame(width: 120)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await fetchMissingCovers() }
            } label: {
                if isFetchingCovers {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Pobierz brakujące okładki", systemImage: "arrow.down.circle")
                }
            }
            .disabled(isFetchingCovers || missingCovers == 0)
        }
    }

    private func tiles(volumes: [Volume], series: Int, withCover: Int) -> some View {
        HStack(spacing: 12) {
            StatCardView(
                title: "tomów na półce",
                value: "\(volumes.count)",
                systemImage: "books.vertical.fill",
                accentColor: .green
            )
            StatCardView(
                title: "serii",
                value: "\(series)",
                systemImage: "square.stack.3d.up.fill",
                accentColor: .blue
            )
            StatCardView(
                title: "przeczytanych",
                value: "\(volumes.count { $0.read == true })",
                systemImage: "checkmark.circle.fill",
                accentColor: .teal
            )
            StatCardView(
                title: "z własną okładką",
                value: "\(withCover)/\(volumes.count)",
                systemImage: "photo.fill",
                accentColor: .orange
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: - Covers

    /// Asks MangaDex for every series that has an owned volume without art.
    /// One series at a time to stay polite to the API; series MangaDex
    /// doesn't know keep their drawn covers.
    private func fetchMissingCovers() async {
        guard !isFetchingCovers else { return }
        isFetchingCovers = true
        defer { isFetchingCovers = false }

        let targets = shelves
            .filter { $0.volumes.contains { ($0.coverURL ?? "").isEmpty } }
            .map(\.manga)
        var applied = 0
        var failed = 0
        for manga in targets {
            do {
                applied += try await manga.fetchVolumeCovers()
            } catch {
                failed += 1
            }
        }

        if applied > 0 {
            ToastService.shared.show(L("Pobrano okładki dla %lld tomów.", applied), type: .success)
        } else {
            ToastService.shared.show(L("MangaDex nie ma więcej okładek dla tych tomów."), type: .info)
        }
        if failed > 0 {
            ToastService.shared.show(L("Nie udało się pobrać okładek dla %lld serii.", failed), type: .error)
        }
    }
}

/// One series: its title, then its volumes standing in a row on a plank.
private struct ShelfRow: View {
    let manga: Manga
    let volumes: [Volume]
    let coverHeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(volumes.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 6) {
                        ForEach(volumes) { volume in
                            ShelfVolume(volume: volume, height: coverHeight)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                // The plank.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brown.opacity(0.55), Color.brown.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
            }
        }
    }
}

private struct ShelfVolume: View {
    let volume: Volume
    let height: Double

    @State private var isHovered = false

    var body: some View {
        VolumeCoverView(volume: volume, cornerRadius: 4)
            .frame(width: height * 0.68, height: height)
            .overlay(alignment: .topTrailing) {
                if volume.read == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .green)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 3, x: 1, y: 2)
            .offset(y: isHovered ? -8 : 0)
            .onHover { isHovered = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .tooltip(Text("\(volume.manga?.title ?? "") — tom \(volume.number)"))
    }
}
