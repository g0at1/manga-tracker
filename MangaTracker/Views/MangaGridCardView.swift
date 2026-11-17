import SwiftUI

/// A single series in the library grid: cover, title, reading progress.
/// Lifts and glows on hover so it reads as clickable.
struct MangaGridCardView: View {
    let manga: Manga
    /// From the library's one pass over every series; walking
    /// `manga.volumes` here would fault them in as each card scrolls in.
    let stats: MangaVolumeStats

    @State private var isHovered = false
    @Environment(\.scrollActivity) private var scrollActivity

    /// Cards sliding under a still pointer mid-scroll don't light up:
    /// each would animate its lift, shadow and heart button.
    private var showsHover: Bool {
        isHovered && !(scrollActivity?.isScrolling ?? false)
    }

    private static let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)

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

                ReadingProgressBar(fraction: stats.readPercent / 100)

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
                .fill(Color.white.opacity(showsHover ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(
                    Color.white.opacity(showsHover ? 0.18 : 0.07),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(showsHover ? 0.35 : 0),
            radius: showsHover ? 14 : 0,
            y: showsHover ? 8 : 0
        )
        .scaleEffect(showsHover ? 1.02 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.16), value: showsHover)
    }

    /// 2:3 cover with status badges pinned to the top-right corner.
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
                        badge("Sprzedane", color: .red)
                    }
                    if manga.isSpinOff ?? false {
                        badge("Spin-off", color: .gray)
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if showsHover || manga.isFavorite ?? false {
                    FavoriteHeartButton(manga: manga)
                        .padding(8)
                        .transition(.opacity)
                }
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

/// Round heart that toggles `isFavorite`. Filled red once hearted; sits on
/// top of the cover so it works without opening the series.
struct FavoriteHeartButton: View {
    let manga: Manga
    var size: CGFloat = 28

    @State private var isHovered = false

    private var isFavorite: Bool {
        manga.isFavorite ?? false
    }

    var body: some View {
        Button {
            manga.isFavorite = !isFavorite
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(isFavorite ? Color.red : .white.opacity(0.92))
                .frame(width: size, height: size)
                .background(
                    // A flat fill rather than a material: a blur on every
                    // favourite card is re-sampled each frame while scrolling.
                    Circle()
                        .fill(Color.black.opacity(isHovered ? 0.72 : 0.6))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .scaleEffect(isHovered ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tooltip(isFavorite ? "Usuń z ulubionych" : "Dodaj do ulubionych")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isFavorite)
    }
}
