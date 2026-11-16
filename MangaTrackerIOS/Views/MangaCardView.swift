import SwiftUI

/// A single series in the library grid: cover, title, reading progress.
struct MangaCardView: View {
    let manga: Manga

    private static let cornerRadius: CGFloat = 14

    var body: some View {
        let stats = manga.volumeStats

        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                HStack(alignment: .firstTextBaseline) {
                    if stats.allRead {
                        Label("\(stats.total)", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(stats.read)/\(stats.total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text("\(Int(stats.readPercent.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                ProgressView(value: stats.readPercent, total: 100)
                    .tint(.green)
                    .scaleEffect(y: 0.7)

                Text(stats.totalPaid, format: .currency(code: "PLN"))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    /// 2:3 cover with status badges pinned to the corners.
    private var cover: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay(
                CoverImageView(
                    url: URL(string: manga.coverURL ?? ""),
                    cornerRadius: 10
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if manga.isSold ?? false {
                        StatusBadge(text: "Sprzedane", color: .red)
                    }
                    if manga.isSpinOff ?? false {
                        StatusBadge(text: "Spin-off", color: .gray)
                    }
                    if manga.isPlanned ?? false {
                        StatusBadge(text: "Planowana", color: .blue)
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if manga.isFavorite ?? false {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.45))
                                .background(.ultraThinMaterial, in: Circle())
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .padding(8)
                }
            }
    }
}

/// Small capsule pinned on a cover: "Sprzedane", "Spin-off", "Planowana".
struct StatusBadge: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}
