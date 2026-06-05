import SwiftData
import SwiftUI

struct UpcomingWindowView: View {
    @Query(sort: \Manga.sortOrder, order: .forward)
    private var mangas: [Manga]

    var body: some View {
        UpcomingView(mangas: mangas)
    }
}
