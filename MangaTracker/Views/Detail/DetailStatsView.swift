import SwiftUI

/// Stat tiles (same as the library header), your rating, and the reading
/// progress bar with the tracker's main action: mark the next volume read.
struct DetailStatsView: View {
    @Bindable var manga: Manga

    @State private var hoveredRating: Double?
    @Environment(\.locale) private var locale

    private enum NextStep {
        /// The part is set when the volume is split: the one to pick up.
        case read(Volume, VolumePart?)
        /// Nothing left to read until the ordered volumes arrive.
        case arriving(Int)
        case buy(Volume)
        case allRead
        case noVolumes
    }

    private func nextStep(_ stats: MangaVolumeStats) -> NextStep {
        if let next = stats.nextUnread {
            return .read(next, stats.nextUnreadPart)
        }
        if stats.onItsWay > 0 {
            return .arriving(stats.onItsWay)
        }
        if let missing = stats.firstMissing {
            return .buy(missing)
        }
        return stats.total == 0 ? .noVolumes : .allRead
    }

    var body: some View {
        let stats = manga.volumeStats

        VStack(alignment: .leading, spacing: 14) {
            // One row when it fits, otherwise the counts on one line and
            // money and rating on the next.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    countTiles(stats)
                    otherTiles(stats)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) { countTiles(stats) }
                    HStack(spacing: 12) { otherTiles(stats) }
                }
            }

            progressCard(stats)
        }
    }

    @ViewBuilder
    private func countTiles(_ stats: MangaVolumeStats) -> some View {
        StatCardView(title: "tomów", value: "\(stats.total)", systemImage: "books.vertical.fill", accentColor: .blue)
        StatCardView(title: "kupionych", value: "\(stats.owned)", systemImage: "cart.fill", accentColor: .green)
        StatCardView(title: "przeczytanych", value: "\(stats.read)", systemImage: "checkmark.circle.fill", accentColor: .green)
    }

    @ViewBuilder
    private func otherTiles(_ stats: MangaVolumeStats) -> some View {
        StatCardView(
            title: "wydano",
            value: stats.totalPaid.formatted(.number.precision(.fractionLength(2)).locale(locale)),
            systemImage: "wallet.pass.fill",
            accentColor: .yellow,
            unit: "PLN"
        )
        ratingTile
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
                        Text("\(stats.readUnits) / \(stats.totalUnits) · \(Int(stats.readPercent.rounded()))%")
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
        case let .read(volume, part):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Następny do przeczytania")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let part {
                        Text("Tom \(volume.number) · część \(part.index)/\(volume.parts.count)")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Tom \(volume.number)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                AccentButton(title: "Oznacz jako przeczytany", systemImage: "checkmark") {
                    volume.markNextUnitRead()
                }
            }

        case let .arriving(count):
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Wszystko przeczytane — czekasz na dostawę")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("W drodze: \(count)")
                        .font(.subheadline.weight(.semibold))
                }
                SubtleButton(title: "Dostarczone", systemImage: "shippingbox", tint: .orange) {
                    manga.markOrderDelivered()
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
                    volume.markOwned(true)
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
