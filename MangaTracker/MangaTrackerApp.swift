import SwiftData
import SwiftUI

@main
struct MangaTrackerApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue

    /// One store for every window. Separate `.modelContainer(for:)` calls
    /// would each open their own container, so edits in the library wouldn't
    /// reach the dashboard until relaunch.
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Manga.self, Volume.self)
        } catch {
            fatalError("Failed to open the manga store: \(error)")
        }
    }()

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
        .modelContainer(container)

        WindowGroup("Nadchodzące", id: "upcoming") {
            UpcomingWindowView()
                .localized(language)
        }
        .defaultSize(width: 1200, height: 880)
        .modelContainer(container)

        WindowGroup("Statystyki", id: "dashboard") {
            DashboardWindowView()
                .localized(language)
        }
        .defaultSize(width: 1500, height: 960)
        .modelContainer(container)
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
