import SwiftUI

struct SummaryHeaderView: View {
    let mangas: [Manga]

    var body: some View {
        let stats = MangaLibraryStats(mangas: mangas)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCardView(
                    title: "Serie",
                    value: "\(stats.mangaCount)",
                    systemImage: "books.vertical.fill",
                    accentColor: .blue
                )

                StatCardView(
                    title: "Tomy",
                    value: "\(stats.ownedVolumesCount)",
                    systemImage: "book.fill"
                )

                StatCardView(
                    title: "Wydano",
                    value: stats.totalPaid.formatted(
                        .currency(
                            code: Locale.current.currency?.identifier ?? "PLN"
                        )
                    ),
                    systemImage: "creditcard.fill",
                    accentColor: .yellow,
                    monospaced: true
                )

                StatCardView(
                    title: "Przeczytano",
                    value: stats.totalReadPercent.formatted(
                        .number.precision(.fractionLength(1))
                    ) + "%",
                    systemImage: "checkmark.circle.fill",
                    accentColor: .green
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
