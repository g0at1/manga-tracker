import Foundation
import Observation
import SwiftData

enum SyncStatus: Equatable {
    /// The app was built without backend credentials; sync can't be turned on.
    case unavailable
    /// No library key: everything stays on this device.
    case disconnected
    case connecting
    /// The server confirmed the latest snapshot.
    case online(lastSync: Date?)
    /// Working from the local cache; changes queue until a connection returns.
    case offline(lastSync: Date?)
    case error(String)

    var isConnected: Bool {
        switch self {
        case .connecting, .online, .offline, .error: true
        case .unavailable, .disconnected: false
        }
    }
}

/// Keeps the SwiftData library and the backend in step.
///
/// Local side: every save of the main context reports which models it
/// touched. Those are mapped to series (a changed volume marks its series)
/// and pushed as whole documents after a short debounce. Remote side: the
/// backend streams documents; each one that isn't a version this device
/// already knows is written into SwiftData, volumes reconciled by number.
///
/// Conflicts are resolved per series, not per field: the version that
/// reaches the server last wins everywhere, except that a series with an
/// unsent local change keeps that change until it's pushed.
@MainActor
@Observable
final class SyncEngine {
    private(set) var status: SyncStatus
    /// Series changed locally and not yet handed to the backend.
    private(set) var pendingCount = 0

    var libraryKey: String? {
        state.libraryKey
    }

    var isAvailable: Bool {
        backend != nil
    }

    private let container: ModelContainer
    private let backend: (any SyncBackend)?
    private let state: SyncState
    /// Debounce before a batch of local changes goes out.
    private let pushDelay: Duration

    /// Lets a delete be mapped back to its series: by the time `didSave`
    /// reports a deleted identifier the model is gone.
    private var syncIDsByIdentifier: [PersistentIdentifier: String] = [:]
    /// Series being written from a remote snapshot right now, so the save
    /// that follows doesn't push them straight back.
    private var applyingIDs: Set<String> = []
    private var pushTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    private var didStart = false

    private var context: ModelContext {
        container.mainContext
    }

    init(
        container: ModelContainer,
        backend: (any SyncBackend)?,
        state: SyncState? = nil,
        pushDelay: Duration = .seconds(1)
    ) {
        let state = state ?? SyncState()
        self.container = container
        self.backend = backend
        self.state = state
        self.pushDelay = pushDelay
        status = backend == nil ? .unavailable : (state.libraryKey == nil ? .disconnected : .connecting)
        pendingCount = state.pendingUpserts.count + state.pendingDeletes.count
    }

    // MARK: - Lifecycle

    /// Assigns identities to series that predate sync, starts watching the
    /// context and, when a library key is set, connects.
    func start() {
        guard !didStart else { return }
        didStart = true

        let mangas = (try? context.fetch(FetchDescriptor<Manga>())) ?? []
        for manga in mangas {
            if manga.syncID == nil {
                manga.syncID = UUID().uuidString
            }
            syncIDsByIdentifier[manga.persistentModelID] = manga.syncID
        }
        if context.hasChanges {
            try? context.save()
        }

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // The main context saves on the main thread.
            MainActor.assumeIsolated {
                self?.handleDidSave(notification)
            }
        }

        if state.libraryKey != nil {
            connect()
        }
    }

    /// Joins the library `key` names: everything already there comes down,
    /// everything local goes up, and the two are merged by series identity.
    func connect(libraryKey key: String) {
        guard backend != nil else { return }
        if key != state.libraryKey {
            state.resetLibraryBookkeeping()
            state.libraryKey = key
        }
        connect()
    }

    /// A fresh, empty library with a new key; the local collection seeds it.
    @discardableResult
    func createLibrary() -> String? {
        guard backend != nil else { return nil }
        let key = LibraryKey.generate()
        connect(libraryKey: key)
        return key
    }

    /// Stops syncing and forgets the key. Local data stays.
    func disconnect() {
        pushTask?.cancel()
        pushTask = nil
        backend?.stopListening()
        state.libraryKey = nil
        state.resetLibraryBookkeeping()
        pendingCount = 0
        status = backend == nil ? .unavailable : .disconnected
    }

    /// Re-sends the whole library, for when the two sides look out of step.
    func pushEverything() {
        guard status.isConnected else { return }
        let mangas = (try? context.fetch(FetchDescriptor<Manga>())) ?? []
        state.pendingUpserts.formUnion(mangas.compactMap(\.syncID))
        flush()
    }

    /// Sends pending changes now instead of after the debounce — for when
    /// the app is about to go to the background.
    func flush() {
        pushTask?.cancel()
        pushTask = nil
        pushPending()
    }

    private func connect() {
        guard let backend, let key = state.libraryKey else { return }
        status = .connecting

        // Anything the backend has never heard of from this device goes up
        // with the first push — a fresh key, or a library that predates sync.
        let mangas = (try? context.fetch(FetchDescriptor<Manga>())) ?? []
        let unsynced = mangas.compactMap { manga -> String? in
            guard let id = manga.syncID, state.appliedRevisions[id] == nil else { return nil }
            return id
        }
        state.pendingUpserts.formUnion(unsynced)
        updatePendingCount()

        backend.listen(libraryKey: key) { [weak self] result in
            self?.handleSnapshot(result)
        }
        schedulePush()
    }

    // MARK: - Local → remote

    private func handleDidSave(_ notification: Notification) {
        guard let saved = notification.object as? ModelContext, saved === context else { return }
        let info = notification.userInfo ?? [:]
        let inserted = info[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
        let updated = info[ModelContext.NotificationKey.updatedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []
        let deleted = info[ModelContext.NotificationKey.deletedIdentifiers.rawValue] as? [PersistentIdentifier] ?? []

        var touched = Set<String>()
        for identifier in inserted + updated {
            let manga: Manga?
            switch context.model(for: identifier) {
            case let model as Manga: manga = model
            case let model as Volume: manga = model.manga
            default: manga = nil
            }
            guard let manga else { continue }
            if manga.syncID == nil {
                manga.syncID = UUID().uuidString
            }
            guard let id = manga.syncID else { continue }
            syncIDsByIdentifier[manga.persistentModelID] = id
            touched.insert(id)
        }

        var removed = Set<String>()
        for identifier in deleted {
            if let id = syncIDsByIdentifier.removeValue(forKey: identifier) {
                removed.insert(id)
            }
        }
        touched.subtract(removed)

        // Changes this engine just wrote from a remote snapshot aren't news
        // to the backend; anything else in the same save still is.
        touched.subtract(applyingIDs)
        removed.subtract(applyingIDs)
        guard !touched.isEmpty || !removed.isEmpty else { return }

        state.pendingUpserts.formUnion(touched)
        state.pendingUpserts.subtract(removed)
        state.pendingDeletes.formUnion(removed)
        state.pendingDeletes.subtract(touched)
        updatePendingCount()
        schedulePush()
    }

    private func schedulePush() {
        guard state.libraryKey != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self, pushDelay] in
            try? await Task.sleep(for: pushDelay)
            guard !Task.isCancelled else { return }
            self?.pushPending()
        }
    }

    private func pushPending() {
        guard let backend, let key = state.libraryKey, status.isConnected else { return }
        let upsertIDs = state.pendingUpserts
        let deleteIDs = state.pendingDeletes
        guard !upsertIDs.isEmpty || !deleteIDs.isEmpty else { return }

        let now = Date()
        let revision = Int((now.timeIntervalSince1970 * 1000).rounded())
        let updatedAt = Date(timeIntervalSince1970: Double(revision) / 1000)
        var upserts: [String: RemoteManga] = [:]
        for id in upsertIDs {
            // Deleted since it was queued; nothing to send.
            guard let manga = fetchManga(syncID: id) else { continue }
            upserts[id] = RemoteManga(
                revision: revision,
                updatedAt: updatedAt,
                device: state.deviceID,
                manga: ExportedManga(manga)
            )
            state.appliedRevisions[id] = revision
        }
        for id in deleteIDs {
            state.appliedRevisions[id] = nil
        }

        // Handed off: the backend queues durably, so these aren't pending
        // even before the server acknowledges them.
        state.pendingUpserts = []
        state.pendingDeletes = []
        updatePendingCount()

        backend.write(libraryKey: key, upserts: upserts, deletes: Array(deleteIDs)) { [weak self] error in
            guard let self, let error else { return }
            // Rejected (rules, quota…): queue again so a later attempt retries.
            state.pendingUpserts.formUnion(upserts.keys)
            state.pendingDeletes.formUnion(deleteIDs)
            updatePendingCount()
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Remote → local

    private func handleSnapshot(_ result: Result<RemoteSnapshot, Error>) {
        let snapshot: RemoteSnapshot
        switch result {
        case let .success(value):
            snapshot = value
        case let .failure(error):
            status = .error(error.localizedDescription)
            return
        }

        for change in snapshot.changes {
            switch change {
            case let .upsert(id, remote):
                // A local edit that hasn't gone out yet wins; it will
                // overwrite this version when it's pushed.
                guard !state.pendingUpserts.contains(id),
                      state.appliedRevisions[id] != remote.revision
                else { continue }
                applyingIDs.insert(id)
                if let manga = fetchManga(syncID: id) {
                    manga.apply(remote.manga)
                } else {
                    context.insert(Manga(exported: remote.manga, syncID: id))
                }
                state.appliedRevisions[id] = remote.revision

            case let .delete(id):
                guard !state.pendingUpserts.contains(id) else { continue }
                state.appliedRevisions[id] = nil
                guard let manga = fetchManga(syncID: id) else { continue }
                applyingIDs.insert(id)
                syncIDsByIdentifier[manga.persistentModelID] = nil
                context.delete(manga)
            }
        }

        if context.hasChanges {
            do {
                // Saving here posts `didSave` synchronously, while
                // `applyingIDs` still says what not to push back.
                try context.save()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
        // Series inserted from a snapshot need to be mappable when deleted later.
        for id in applyingIDs {
            if let manga = fetchManga(syncID: id) {
                syncIDsByIdentifier[manga.persistentModelID] = id
            }
        }
        applyingIDs = []

        let lastSync = snapshot.isFromCache ? status.lastSync : Date()
        status = snapshot.isFromCache ? .offline(lastSync: lastSync) : .online(lastSync: lastSync)
    }

    // MARK: - Helpers

    private func fetchManga(syncID: String) -> Manga? {
        var descriptor = FetchDescriptor<Manga>(predicate: #Predicate { $0.syncID == syncID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func updatePendingCount() {
        pendingCount = state.pendingUpserts.count + state.pendingDeletes.count
    }
}

private extension SyncStatus {
    var lastSync: Date? {
        switch self {
        case let .online(lastSync), let .offline(lastSync): lastSync
        default: nil
        }
    }
}
