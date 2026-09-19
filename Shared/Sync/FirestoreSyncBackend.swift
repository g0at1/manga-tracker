import FirebaseCore
import FirebaseFirestore
import Foundation

/// `SyncBackend` on Cloud Firestore. Each library is a collection at
/// `libraries/{key}/mangas`, one document per series keyed by `syncID`.
/// Firestore keeps its own offline cache and write queue, so writes made
/// without a connection are delivered when one comes back.
@MainActor
final class FirestoreSyncBackend: SyncBackend {
    private let database: Firestore
    private var registration: ListenerRegistration?

    /// Firestore caps a batch at 500 operations.
    private static let batchLimit = 400

    init(database: Firestore) {
        self.database = database
    }

    private func mangas(in libraryKey: String) -> CollectionReference {
        database.collection("libraries").document(libraryKey).collection("mangas")
    }

    func listen(
        libraryKey: String,
        onSnapshot: @escaping @MainActor (Result<RemoteSnapshot, Error>) -> Void
    ) {
        stopListening()
        // Metadata changes included so the "server confirmed" flip after a
        // cached snapshot is reported; the engine's revision check makes the
        // extra events harmless.
        registration = mangas(in: libraryKey).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            // Firestore calls back on the main queue.
            MainActor.assumeIsolated {
                if let error {
                    onSnapshot(.failure(error))
                } else if let snapshot {
                    onSnapshot(.success(Self.remoteSnapshot(from: snapshot)))
                }
            }
        }
    }

    private static func remoteSnapshot(from snapshot: QuerySnapshot) -> RemoteSnapshot {
        var changes: [RemoteChange] = []
        for change in snapshot.documentChanges(includeMetadataChanges: true) {
            let document = change.document
            switch change.type {
            case .added, .modified:
                // Our own unacknowledged write echoing back.
                guard !document.metadata.hasPendingWrites else { continue }
                do {
                    let remote = try document.data(as: RemoteManga.self)
                    changes.append(.upsert(id: document.documentID, remote))
                } catch {
                    // A document another version of the app wrote in a shape
                    // this one can't read; skip it rather than fail the batch.
                    print("Sync: skipping unreadable document \(document.documentID): \(error)")
                }
            case .removed:
                changes.append(.delete(id: document.documentID))
            }
        }
        return RemoteSnapshot(changes: changes, isFromCache: snapshot.metadata.isFromCache)
    }

    func stopListening() {
        registration?.remove()
        registration = nil
    }

    func write(
        libraryKey: String,
        upserts: [String: RemoteManga],
        deletes: [String],
        completion: @escaping @MainActor (Error?) -> Void
    ) {
        let collection = mangas(in: libraryKey)
        var operations: [(WriteBatch) throws -> Void] = []
        for (id, remote) in upserts {
            operations.append { batch in
                try batch.setData(from: remote, forDocument: collection.document(id))
            }
        }
        for id in deletes {
            operations.append { batch in
                batch.deleteDocument(collection.document(id))
            }
        }
        guard !operations.isEmpty else {
            completion(nil)
            return
        }

        var batches: [WriteBatch] = []
        do {
            for chunk in stride(from: 0, to: operations.count, by: Self.batchLimit) {
                let batch = database.batch()
                for operation in operations[chunk ..< min(chunk + Self.batchLimit, operations.count)] {
                    try operation(batch)
                }
                batches.append(batch)
            }
        } catch {
            completion(error)
            return
        }

        var remaining = batches.count
        var firstError: Error?
        for batch in batches {
            batch.commit { error in
                MainActor.assumeIsolated {
                    if let error, firstError == nil {
                        firstError = error
                    }
                    remaining -= 1
                    if remaining == 0 {
                        completion(firstError)
                    }
                }
            }
        }
    }
}

// MARK: - Setup

enum FirebaseSetup {
    /// Environment variable (or `defaults` key) naming a local Firestore
    /// emulator, `host:port`. Lets both apps be tested against
    /// `firebase emulators:start` without a Firebase project.
    static let emulatorEnvironmentKey = "MANGATRACKER_FIRESTORE_EMULATOR"
    static let emulatorDefaultsKey = "firestoreEmulatorHost"
    /// Any id in Firebase's `1:<digits>:ios:<hex>` shape; an invalid one
    /// makes `configure` throw an Objective-C exception.
    private static let emulatorAppID = "1:123456789012:ios:0123456789abcdef"

    /// Configures Firebase once and returns the backend, or `nil` when the
    /// app has no `GoogleService-Info.plist` (and no emulator is named) —
    /// the app then runs local-only.
    @MainActor
    static func makeBackend() -> FirestoreSyncBackend? {
        if FirebaseApp.app() == nil {
            if let emulator = emulatorHost {
                // Demo project ids are accepted by the emulator without
                // credentials; nothing here reaches Google's servers.
                let options = FirebaseOptions(googleAppID: Self.emulatorAppID, gcmSenderID: "123456789012")
                options.projectID = "demo-mangatracker"
                options.apiKey = "demo-api-key"
                FirebaseApp.configure(options: options)

                let parts = emulator.split(separator: ":")
                let host = parts.first.map(String.init) ?? "127.0.0.1"
                let port = parts.count > 1 ? Int(parts[1]) ?? 8080 : 8080
                pointToEmulator(Firestore.firestore(), host: host, port: port)
            } else if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                      let options = FirebaseOptions(contentsOfFile: path)
            {
                FirebaseApp.configure(options: options)
            } else {
                return nil
            }
        }
        return FirestoreSyncBackend(database: Firestore.firestore())
    }

    /// A backend on its own Firebase app, talking to a local emulator.
    /// Several of these in one process act as several devices, which is
    /// how the sync tests exercise the engine.
    @MainActor
    static func makeEmulatorBackend(appName: String, host: String, port: Int) -> FirestoreSyncBackend {
        if let app = FirebaseApp.app(name: appName) {
            // Settings can only be applied before first use, so an existing
            // app keeps the emulator it was created with.
            return FirestoreSyncBackend(database: Firestore.firestore(app: app))
        }
        let options = FirebaseOptions(googleAppID: Self.emulatorAppID, gcmSenderID: "123456789012")
        options.projectID = "demo-mangatracker"
        options.apiKey = "demo-api-key"
        FirebaseApp.configure(name: appName, options: options)
        let database = Firestore.firestore(app: FirebaseApp.app(name: appName)!)
        pointToEmulator(database, host: host, port: port)
        return FirestoreSyncBackend(database: database)
    }

    /// `useEmulator` only swaps the host; the emulator speaks plain HTTP,
    /// so SSL has to go too. Must run before the instance is first used.
    @MainActor
    private static func pointToEmulator(_ database: Firestore, host: String, port: Int) {
        let settings = database.settings
        settings.host = "\(host):\(port)"
        settings.isSSLEnabled = false
        database.settings = settings
    }

    private static var emulatorHost: String? {
        let environment = ProcessInfo.processInfo.environment[emulatorEnvironmentKey]
        let defaults = UserDefaults.standard.string(forKey: emulatorDefaultsKey)
        guard let host = environment ?? defaults, !host.isEmpty else { return nil }
        return host
    }
}
