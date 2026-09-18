import SwiftUI

/// Wide card in the "Kontynuuj czytanie" row: cover, next volume, progress.
struct ContinueReadingCardView: View {
    let manga: Manga
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        let stats = manga.volumeStats
        let percent = stats.readPercent

        HStack(alignment: .top, spacing: 14) {
            Color.clear
                .frame(width: 96, height: 136)
                .overlay(
                    CoverImageView(
                        url: URL(string: manga.coverURL ?? ""),
                        cornerRadius: 8
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(1)

                Group {
                    if let next = stats.nextUnread {
                        Text("Tom \(next.number) z \(stats.total)")
                    } else {
                        Text(verbatim: "")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ProgressView(value: percent, total: 100)
                        .tint(.green)
                        .scaleEffect(y: 0.8)
                    Text("\(Int(percent.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Spacer(minLength: 0)

                Button(action: onOpen) {
                    Text("Czytaj dalej")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.green.opacity(isHovered ? 0.32 : 0.22))
                        )
                        .foregroundStyle(Color.green)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 320, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.16 : 0.07), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}
