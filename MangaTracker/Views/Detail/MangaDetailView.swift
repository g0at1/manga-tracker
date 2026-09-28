import SwiftData
import SwiftUI

/// One series: banner hero, stats, then the volumes table beside a side
/// panel with the add-volumes form, note and synopsis. On a narrow window
/// the side panel moves under the table so the table keeps its columns.
struct MangaDetailView: View {
    @Bindable var manga: Manga

    @State private var contentWidth: CGFloat = .infinity

    private let horizontalPadding: CGFloat = 28
    private let sidePanelWidth: CGFloat = 320
    private let columnSpacing: CGFloat = 18

    /// The side panel stays beside the table while the table still fits
    /// its purchase and read dates next to it.
    private var isSidePanelBeside: Bool {
        let table = VolumesTableView.rowWidth(dateColumns: 2, showsCovers: manga.hasVolumeCovers)
        return table + columnSpacing + sidePanelWidth <= contentWidth
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                DetailHeroView(manga: manga)

                DetailStatsView(manga: manga)
                    .padding(.horizontal, horizontalPadding)

                // One layout that switches, so the table keeps its filter
                // and selection while the window is resized across it.
                let isBeside = isSidePanelBeside
                let layout = isBeside
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: columnSpacing))
                    : AnyLayout(VStackLayout(spacing: columnSpacing))

                layout {
                    VolumesTableView(manga: manga)
                        .frame(maxWidth: .infinity)

                    DetailSidePanelView(manga: manga, isWide: !isBeside)
                        .frame(width: isBeside ? sidePanelWidth : nil)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .padding(.horizontal, horizontalPadding)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
        .navigationTitle(manga.title.isEmpty ? "Szczegóły" : manga.title)
    }
}
