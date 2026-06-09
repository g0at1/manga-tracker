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

        WindowGroup("Nadchodzące", id: "upcoming") {
            UpcomingWindowView()
        }
        .defaultSize(width: 1280, height: 920)
        .modelContainer(for: [Manga.self, Volume.self])

        WindowGroup("Dashboard", id: "dashboard") {
            DashboardWindowView()
        }
        .defaultSize(width: 1920, height: 1080)
        .modelContainer(for: [Manga.self, Volume.self])
    }
}
