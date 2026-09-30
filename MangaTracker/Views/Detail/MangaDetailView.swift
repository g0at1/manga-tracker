import SwiftData
import SwiftUI

/// One series: banner hero, stats, then the volumes table beside a side
/// panel with the add-volumes form, note and synopsis. On a narrow window
/// the side panel moves under the table so the table keeps its columns.
struct MangaDetailView: View {
    @Bindable var manga: Manga

    @State private var contentWidth: CGFloat = .infinity
    /// Past the top: the toolbar gets a backdrop so the breadcrumb and the
    /// table's pinned header don't float over the rows scrolling under them.
    @State private var isScrolled = false

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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 4
        } action: { _, scrolled in
            isScrolled = scrolled
        }
        .overlay(alignment: .top) {
            ToolbarBackdrop()
                .opacity(isScrolled ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isScrolled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackgroundView())
        .navigationTitle(manga.title.isEmpty ? "Szczegóły" : manga.title)
    }
}

/// Opaque strip behind the window toolbar, which is otherwise transparent
/// so the hero banner runs up under it. Covers exactly the toolbar's height.
private struct ToolbarBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color(red: 0.055, green: 0.06, blue: 0.07)
                    .frame(height: proxy.safeAreaInsets.top)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                    }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}
