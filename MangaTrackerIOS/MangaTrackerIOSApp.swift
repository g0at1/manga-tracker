import SwiftData
import SwiftUI

@main
struct MangaTrackerIOSApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    /// Mirrors the store to the backend (and back). Without Firebase
    /// credentials in the bundle it stays in the `unavailable` state and
    /// the app is local-only.
    @State private var syncEngine: SyncEngine

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Manga.self, Volume.self)
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
            RootView()
                // The `id` rebuilds the tree on a language change so strings
                // assembled in code pick up the new language too.
                .environment(\.locale, language.locale)
                .id(language)
                .environment(syncEngine)
                // The palette is built for the Mac app's dark surface.
                .preferredColorScheme(.dark)
                .onAppear {
                    syncEngine.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Send what's queued before iOS suspends the app.
                    if phase != .active {
                        syncEngine.flush()
                    }
                }
        }
        .modelContainer(container)
    }
}
