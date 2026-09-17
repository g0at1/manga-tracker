import SwiftUI

struct StatsSidebarView: View {
    let mangas: [Manga]

    var body: some View {
        let stats = MangaLibraryStats(mangas: mangas)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("MangaTracker")
                        .font(.title3)
                        .fontWeight(.bold)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

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

                StatCardView(
                    title: "Streak",
                    value: "\(stats.currentReadStreak) dni",
                    systemImage: stats.didReadToday ? "flame.fill" : "flame",
                    accentColor: stats.didReadToday ? .orange : .gray
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
    }
}
