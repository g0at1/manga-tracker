import SwiftData
import SwiftUI

@main
struct MangaTrackerApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .polish
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .localized(language)
                .onAppear {
                    WindowManager.maximizeMainWindow()
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .modelContainer(for: [Manga.self, Volume.self])

        WindowGroup("Nadchodzące", id: "upcoming") {
            UpcomingWindowView()
                .localized(language)
        }
        .defaultSize(width: 1200, height: 880)
        .modelContainer(for: [Manga.self, Volume.self])

        WindowGroup("Statystyki", id: "dashboard") {
            DashboardWindowView()
                .localized(language)
        }
        .defaultSize(width: 1500, height: 960)
        .modelContainer(for: [Manga.self, Volume.self])
    }
}

private extension View {
    /// Applies the chosen UI language. The `id` rebuilds the tree on change so
    /// strings assembled in code pick up the new language too.
    func localized(_ language: AppLanguage) -> some View {
        environment(\.locale, language.locale)
            .id(language)
    }
}
