import SwiftUI

struct MangaGridCardView: View {
    let manga: Manga
    let isSelected: Bool

    private var readPercent: Double {
        let total = manga.volumes.count
        guard total > 0 else { return 0 }
        let readCount = manga.volumes.filter { $0.read == true }.count
        return (Double(readCount) / Double(total)) * 100
    }

    private var totalPaid: Double {
        return manga.volumes
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    var body: some View {
        let percent = readPercent
        let allVolumes = manga.volumes.count
        let read = manga.volumes.filter { $0.read == true }.count

        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))

                CachedAsyncImage(
                    url: URL(string: manga.coverURL ?? ""),
                    cornerRadius: 12
                )
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()

                if manga.isSold ?? false {
                    Text("Sprzedane")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.95), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.85), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .padding(10)
                }

                if manga.isSpinOff ?? false {
                    Text("Spin-off")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.gray.opacity(0.95), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.85), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !manga.note.isEmpty {
                    Text(manga.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(alignment: .firstTextBaseline) {
                    if percent >= 100 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(read)/\(allVolumes)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(totalPaid, format: .currency(code: "PLN"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: percent, total: 100)
                    .tint(.green)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
