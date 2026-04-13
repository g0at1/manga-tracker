import SwiftUI

struct MangaListRowView: View {
    let manga: Manga

    private var readPercent: Double {
        let total = manga.volumes.count
        guard total > 0 else { return 0 }
        let readCount = manga.volumes.filter { $0.read == true }.count
        return (Double(readCount) / Double(total)) * 100
    }

    private var totalPaid: Double {
        manga.volumes
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    var body: some View {
        let percent = readPercent
        let allVolumes = manga.volumes.count
        let read = manga.volumes.filter { $0.read == true }.count

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

                    if percent >= 100 {
                        Image(systemName: "checkmark.circle.fill")
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

                ProgressView(value: percent, total: 100)
                    .tint(.green)
                    .scaleEffect(y: 0.6)

                Text(totalPaid, format: .currency(code: "PLN"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }
}
