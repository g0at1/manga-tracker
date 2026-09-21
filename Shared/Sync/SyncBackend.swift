import Foundation

/// One series as stored in the backend: the same snapshot the JSON backup
/// uses, plus who wrote it and when.
struct RemoteManga: Codable {
    /// Milliseconds since 1970 when the writing device saved this version.
    /// Devices compare it to what they last applied; equal means "already
    /// seen", anything else is applied — the backend's version is truth.
    var revision: Int
    /// The same instant as `revision`, readable in the console.
    var updatedAt: Date
    var device: String
    var manga: ExportedManga
}

enum RemoteChange {
    case upsert(id: String, RemoteManga)
    case delete(id: String)
}

struct RemoteSnapshot {
    var changes: [RemoteChange]
    /// The backend served this from its local cache; the server hasn't
    /// confirmed it yet (offline, or still connecting).
    var isFromCache: Bool
}

/// The store a library is synced through. `SyncEngine` owns the local side;
/// the backend only moves documents and reports what changed.
@MainActor
protocol SyncBackend: AnyObject {
    /// Starts delivering changes for `libraryKey`, first everything the
    /// backend has, then each change as it happens. Documents written by
    /// this device that the server hasn't acknowledged are left out.
    func listen(
        libraryKey: String,
        onSnapshot: @escaping @MainActor (Result<RemoteSnapshot, Error>) -> Void
    )

    func stopListening()

    /// Writes and deletes in one atomic batch. `completion` fires when the
    /// server has accepted the batch — which, offline, can be much later;
    /// the backend queues it durably in the meantime.
    func write(
        libraryKey: String,
        upserts: [String: RemoteManga],
        deletes: [String],
        completion: @escaping @MainActor (Error?) -> Void
    )

    /// Delivers the library document itself (reminder settings and the
    /// server's log), first as it is, then on every change. `nil` means
    /// the document doesn't exist yet.
    func listenLibrary(
        libraryKey: String,
        onSnapshot: @escaping @MainActor (Result<RemoteLibrary?, Error>) -> Void
    )

    func stopListeningLibrary()

    /// Replaces the `reminders` field of the library document, creating
    /// the document if needed; nothing else on it is touched.
    func writeReminderSettings(
        libraryKey: String,
        _ settings: ReminderSettings,
        completion: @escaping @MainActor (Error?) -> Void
    )
}
