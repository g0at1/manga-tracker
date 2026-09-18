import SwiftUI

/// Stat tiles (same as the library header), your rating, and the reading
/// progress bar with the tracker's main action: mark the next volume read.
struct DetailStatsView: View {
    @Bindable var manga: Manga

    @State private var hoveredRating: Double?
    @Environment(\.locale) private var locale

    private enum NextStep {
        case read(Volume)
        case buy(Volume)
        case allRead
        case noVolumes
    }

    private func nextStep(_ stats: MangaVolumeStats) -> NextStep {
        if let next = stats.nextUnread {
            return .read(next)
        }
        if let missing = stats.firstMissing {
            return .buy(missing)
        }
        return stats.total == 0 ? .noVolumes : .allRead
    }

    var body: some View {
        let stats = manga.volumeStats

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatCardView(title: "tomów", value: "\(stats.total)", systemImage: "books.vertical.fill", accentColor: .blue)
                StatCardView(title: "kupionych", value: "\(stats.owned)", systemImage: "cart.fill", accentColor: .green)
                StatCardView(title: "przeczytanych", value: "\(stats.read)", systemImage: "checkmark.circle.fill", accentColor: .green)
                StatCardView(
                    title: "wydano",
                    value: stats.totalPaid.formatted(.number.precision(.fractionLength(2)).locale(locale)),
                    systemImage: "wallet.pass.fill",
                    accentColor: .yellow,
                    unit: "PLN"
                )
                ratingTile
                Spacer(minLength: 0)
            }

            progressCard(stats)
        }
    }

    private var ratingTile: some View {
        let displayed = hoveredRating ?? (manga.rating ?? 0)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.yellow.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "star.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StarRatingView(
                        rating: Binding(
                            get: { manga.rating ?? 0 },
                            set: { manga.rating = $0 }
                        ),
                        hoverRating: $hoveredRating,
                        starSize: 16,
                        spacing: 3
                    )
                    Text(displayed == 0 ? "—" : String(format: "%.1f", displayed))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 28, alignment: .leading)
                }
                Text("twoja ocena")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func progressCard(_ stats: MangaVolumeStats) -> some View {
        let completion = stats.readPercent / 100

        return DetailCard(padding: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Postęp czytania")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(stats.read) / \(stats.total) · \(Int(stats.readPercent.rounded()))%")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Color.green)
                                .frame(width: max(0, geo.size.width * completion))
                                .shadow(color: .green.opacity(0.5), radius: 6)
                        }
                    }
                    .frame(height: 8)
                    .animation(.easeOut(duration: 0.25), value: completion)
                }

                Divider()
                    .frame(height: 36)
                    .overlay(Color.white.opacity(0.08))

                nextStepView(nextStep(stats))
                    .frame(minWidth: 300, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func nextStepView(_ step: NextStep) -> some View {
        switch step {
        case let .read(volume):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Następny do przeczytania")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tom \(volume.number)")
                        .font(.subheadline.weight(.semibold))
                }
                AccentButton(title: "Oznacz jako przeczytany", systemImage: "checkmark") {
                    volume.read = true
                    if volume.readDate == nil {
                        volume.readDate = .now
                    }
                }
            }

        case let .buy(volume):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Wszystko przeczytane — następny do kupienia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tom \(volume.number)")
                        .font(.subheadline.weight(.semibold))
                }
                SubtleButton(title: "Oznacz jako kupiony", systemImage: "cart") {
                    volume.owned = true
                    if volume.purchaseDate == nil {
                        volume.purchaseDate = .now
                    }
                }
            }

        case .allRead:
            Label("Wszystkie tomy przeczytane", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

        case .noVolumes:
            Text("Dodaj tomy w panelu po prawej")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
