import SwiftUI

/// Everything ordered and not arrived yet, on the library's home screen:
/// one row per series with its volumes, and a button that marks the whole
/// lot as bought when the parcel comes. Hidden while nothing is on its way.
struct OnTheirWayCard: View {
    /// Series with at least one volume on its way, in display order.
    let mangas: [Manga]
    let onOpen: (Manga) -> Void

    private var volumeCount: Int {
        mangas.reduce(0) { $0 + $1.volumesOnTheirWay.count }
    }

    var body: some View {
        DetailCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                // The button drops under the heading when the row is too
                // narrow for both (a phone).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        heading
                        Spacer(minLength: 8)
                        deliveredButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heading
                        deliveredButton
                    }
                }

                VStack(spacing: 2) {
                    ForEach(mangas) { manga in
                        row(manga)
                    }
                }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("W drodze")
                    .font(.headline)
                Text("Nie liczą się do statystyk, dopóki nie dotrą.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deliveredButton: some View {
        SubtleButton(title: "Wszystko dostarczone (\(volumeCount))", systemImage: "shippingbox", tint: .orange) {
            markAllDelivered()
        }
    }

    private func row(_ manga: Manga) -> some View {
        Button {
            onOpen(manga)
        } label: {
            HStack(spacing: 10) {
                CoverImageView(url: URL(string: manga.coverURL ?? ""), cornerRadius: 3)
                    .frame(width: 22, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(manga.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(manga.volumesOnTheirWay.map { "#\($0.number)" }.joined(separator: ", "))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func markAllDelivered() {
        let count = mangas.reduce(0) { $0 + $1.markOrderDelivered() }
        ToastService.shared.show(L("Dostarczono %lld tomów — oznaczone jako kupione.", count), type: .success)
    }
}
