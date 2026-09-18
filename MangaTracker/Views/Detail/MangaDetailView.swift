import SwiftData
import SwiftUI

/// One series: banner hero, stats, then the volumes table beside a side
/// panel with the add-volumes form, note and synopsis.
struct MangaDetailView: View {
    @Bindable var manga: Manga

    private let horizontalPadding: CGFloat = 28

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                DetailHeroView(manga: manga)

                DetailStatsView(manga: manga)
                    .padding(.horizontal, horizontalPadding)

                HStack(alignment: .top, spacing: 18) {
                    VolumesTableView(manga: manga)
                        .frame(maxWidth: .infinity)

                    DetailSidePanelView(manga: manga)
                        .frame(width: 320)
                }
                .padding(.horizontal, horizontalPadding)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
        .navigationTitle(manga.title.isEmpty ? "Szczegóły" : manga.title)
    }
}
