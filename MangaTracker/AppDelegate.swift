import AppKit

/// Hooks the quit sequence, which SwiftUI doesn't expose: the sync engine
/// closes its connection before AppKit calls `exit()`, so the process
/// doesn't sit in gRPC's exit-time wait after the window is gone.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Handed over by the app once the engine is running.
    var syncEngine: SyncEngine?

    /// Longest a quit waits for the backend to close; past this the app
    /// exits regardless rather than hang on a stuck connection.
    private static let shutdownTimeout: Duration = .seconds(3)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let syncEngine else { return .terminateNow }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await syncEngine.shutDown() }
                group.addTask { try? await Task.sleep(for: Self.shutdownTimeout) }
                // Whichever finishes first ends the wait.
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
