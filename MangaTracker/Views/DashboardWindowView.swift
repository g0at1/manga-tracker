import SwiftData
import SwiftUI

struct DashboardWindowView: View {
    @Query(sort: \Manga.sortOrder, order: .forward)
    private var mangas: [Manga]

    var body: some View {
        DashboardView(mangas: mangas)
    }
}
