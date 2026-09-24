import SwiftData
import SwiftUI

@main
struct MangaTrackerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue
    @Environment(\.scenePhase) private var scenePhase

    /// One store for every window. Separate `.modelContainer(for:)` calls
    /// would each open their own container, so edits in the library wouldn't
    /// reach the dashboard until relaunch.
    private let container: ModelContainer

    /// Mirrors the store to the backend (and back). Without Firebase
    /// credentials in the bundle it stays in the `unavailable` state and
    /// the app is local-only, as before.
    @State private var syncEngine: SyncEngine

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Manga.self, Volume.self, VolumePart.self)
        } catch {
            fatalError("Failed to open the manga store: \(error)")
        }
        self.container = container
        _syncEngine = State(initialValue: SyncEngine(
            container: container,
            backend: FirebaseSetup.makeBackend()
        ))
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .polish
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .localized(language)
                .environment(syncEngine)
                .onAppear {
                    WindowManager.maximizeMainWindow()
                    syncEngine.start()
                    appDelegate.syncEngine = syncEngine
                }
                .onChange(of: scenePhase) { _, phase in
                    // Send what's queued before the app goes quiet.
                    if phase != .active {
                        syncEngine.flush()
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .modelContainer(container)

        WindowGroup("Nadchodzące", id: "upcoming") {
            UpcomingWindowView()
                .localized(language)
                .environment(syncEngine)
        }
        .defaultSize(width: 1200, height: 880)
        .modelContainer(container)

        WindowGroup("Półka", id: "shelf") {
            ShelfWindowView()
                .localized(language)
                .environment(syncEngine)
        }
        .defaultSize(width: 1300, height: 900)
        .modelContainer(container)

        WindowGroup("Statystyki", id: "dashboard") {
            DashboardWindowView()
                .localized(language)
                .environment(syncEngine)
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
