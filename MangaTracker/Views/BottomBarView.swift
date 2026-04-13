import SwiftUI

struct BottomBarView: View {
    let mangas: [Manga]

    var body: some View {
        let stats = MangaLibraryStats(mangas: mangas)

        HStack(spacing: 8) {
            Image(systemName: stats.didReadToday ? "flame.fill" : "flame")
                .foregroundStyle(stats.didReadToday ? .orange : .secondary)

            Text("Streak:")
                .foregroundStyle(.secondary)

            Text("\(stats.currentReadStreak) dni")
                .fontWeight(.semibold)

            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
