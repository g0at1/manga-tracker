import SwiftData
import SwiftUI

@main
struct MangaTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WindowManager.maximizeMainWindow()
                }
        }
        .modelContainer(for: [Manga.self, Volume.self])
    }
}
