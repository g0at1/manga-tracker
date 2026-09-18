import SwiftUI

/// A single series in the library grid: cover, title, reading progress.
/// Lifts and glows on hover so it reads as clickable.
struct MangaGridCardView: View {
    let manga: Manga

    @State private var isHovered = false

    private static let cornerRadius: CGFloat = 14

    private var readCount: Int {
        manga.volumes.filter { $0.read == true }.count
    }

    private var totalCount: Int {
        manga.volumes.count
    }

    private var readPercent: Double {
        guard totalCount > 0 else { return 0 }
        return Double(readCount) / Double(totalCount) * 100
    }

    private var totalPaid: Double {
        manga.volumes
            .filter { $0.owned }
            .compactMap { $0.price }
            .reduce(0, +)
    }

    private var isComplete: Bool {
        totalCount > 0 && readCount == totalCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)

                HStack(alignment: .firstTextBaseline) {
                    if isComplete {
                        Label("\(totalCount)", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(readCount)/\(totalCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text("\(Int(readPercent.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                ProgressView(value: readPercent, total: 100)
                    .tint(.green)
                    .scaleEffect(y: 0.7)

                Text(totalPaid, format: .currency(code: "PLN"))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(
                    Color.white.opacity(isHovered ? 0.18 : 0.07),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.35 : 0),
            radius: isHovered ? 14 : 0,
            y: isHovered ? 8 : 0
        )
        .scaleEffect(isHovered ? 1.02 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    /// 2:3 cover with status badges pinned to the top-right corner.
    private var cover: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay(
                CachedAsyncImage(
                    url: URL(string: manga.coverURL ?? ""),
                    cornerRadius: 10
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    if manga.isSold ?? false {
                        badge("Sprzedane", color: .red)
                    }
                    if manga.isSpinOff ?? false {
                        badge("Spin-off", color: .gray)
                    }
                }
                .padding(8)
            }
    }

    private func badge(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.95), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}
