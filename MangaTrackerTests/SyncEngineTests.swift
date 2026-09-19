@testable import MangaTrackerIOS
import SwiftData
import XCTest

/// Two engines in one process stand in for two devices, each with its own
/// store, bookkeeping and Firebase app, all talking to a local Firestore
/// emulator. Start it first (see README, "Synchronizacja"):
///
///     npx firebase-tools emulators:start --only firestore --project demo-mangatracker
///
/// The tests skip when the emulator isn't reachable.
@MainActor
final class SyncEngineTests: XCTestCase {
    private struct Device {
        let container: ModelContainer
        let engine: SyncEngine
        let state: SyncState

        var context: ModelContext {
            container.mainContext
        }

        func mangas() throws -> [Manga] {
            try context.fetch(FetchDescriptor<Manga>(sortBy: [SortDescriptor(\.title)]))
        }
    }

    private static let emulator: (host: String, port: Int) = {
        let raw = ProcessInfo.processInfo.environment[FirebaseSetup.emulatorEnvironmentKey] ?? "127.0.0.1:8080"
        let parts = raw.split(separator: ":")
        return (String(parts[0]), parts.count > 1 ? Int(parts[1]) ?? 8080 : 8080)
    }()

    override func setUp() async throws {
        try await super.setUp()
        let url = URL(string: "http://\(Self.emulator.host):\(Self.emulator.port)/")!
        var reachable = false
        if let (_, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200
        {
            reachable = true
        }
        try XCTSkipUnless(reachable, "Firestore emulator not running at \(url)")
    }

    private var devices: [Device] = []

    override func tearDown() async throws {
        for device in devices {
            device.engine.disconnect()
        }
        devices = []
        try await super.tearDown()
    }

    /// A "device": empty in-memory store, fresh bookkeeping, its own
    /// Firebase app. Starts the engine; connects when `key` is given.
    private func makeDevice(_ name: String, key: String?) throws -> Device {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Manga.self, Volume.self, configurations: configuration)
        let defaults = UserDefaults(suiteName: "SyncEngineTests.\(name).\(UUID().uuidString)")!
        let state = SyncState(defaults: defaults)
        state.libraryKey = key
        let backend = FirebaseSetup.makeEmulatorBackend(
            appName: "device-\(name)",
            host: Self.emulator.host,
            port: Self.emulator.port
        )
        let engine = SyncEngine(container: container, backend: backend, state: state, pushDelay: .milliseconds(100))
        engine.start()
        let device = Device(container: container, engine: engine, state: state)
        devices.append(device)
        return device
    }

    /// Polls `condition` until it holds or `timeout` passes. The main run
    /// loop keeps turning while this awaits, so Firestore callbacks arrive.
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(20),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () throws -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while try !condition() {
            if ContinuousClock.now - start > timeout {
                XCTFail("Timed out waiting for: \(description)", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Tests

    func testChangesFlowBothWaysAndDeletesPropagate() async throws {
        let key = LibraryKey.generate()
        let a = try makeDevice("A", key: key)
        let b = try makeDevice("B", key: key)

        // A adds a series with three volumes.
        let berserk = Manga(title: "Berserk", sortOrder: 0)
        berserk.volumes = (1 ... 3).map { Volume(number: $0, owned: $0 < 3, manga: berserk) }
        a.context.insert(berserk)
        try a.context.save()

        try await waitUntil("B receives Berserk") {
            try b.mangas().contains { $0.title == "Berserk" && $0.volumes.count == 3 }
        }
        let onB = try XCTUnwrap(b.mangas().first { $0.title == "Berserk" })
        XCTAssertEqual(onB.syncID, berserk.syncID)
        XCTAssertEqual(onB.volumes.filter(\.owned).count, 2)

        // B reads a volume, adds one, renames — and A follows.
        let readDate = Date(timeIntervalSince1970: 1_700_000_000)
        onB.volumes.first { $0.number == 1 }?.read = true
        onB.volumes.first { $0.number == 1 }?.readDate = readDate
        onB.volumes.append(Volume(number: 4, owned: false, manga: onB))
        onB.title = "Berserk (Deluxe)"
        onB.isFavorite = true
        try b.context.save()

        try await waitUntil("A sees B's edits") {
            berserk.title == "Berserk (Deluxe)" && berserk.volumes.count == 4
        }
        XCTAssertEqual(berserk.isFavorite, true)
        let volume1 = try XCTUnwrap(berserk.volumes.first { $0.number == 1 })
        XCTAssertEqual(volume1.read, true)
        XCTAssertEqual(volume1.readDate.map { $0.timeIntervalSince1970.rounded() }, readDate.timeIntervalSince1970.rounded())

        // Nothing is left queued and nothing ping-pongs.
        try await waitUntil("queues drain") {
            a.engine.pendingCount == 0 && b.engine.pendingCount == 0
        }
        let syncID = try XCTUnwrap(berserk.syncID)
        let revisionOnA = a.state.appliedRevisions[syncID]
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(a.state.appliedRevisions[syncID], revisionOnA, "the series kept being re-pushed")
        XCTAssertEqual(a.state.appliedRevisions[syncID], b.state.appliedRevisions[syncID])

        // A deletes the series; it disappears on B.
        a.context.delete(berserk)
        try a.context.save()
        try await waitUntil("B deletes Berserk") {
            try b.mangas().isEmpty
        }
    }

    func testLibraryThatPredatesSyncIsPushedOnConnect() async throws {
        // A has been used offline; B is a fresh install joining later.
        let a = try makeDevice("A", key: nil)
        for (index, title) in ["Vagabond", "Monster"].enumerated() {
            let manga = Manga(title: title, sortOrder: index)
            manga.volumes = [Volume(number: 1, owned: true, manga: manga)]
            a.context.insert(manga)
        }
        try a.context.save()
        XCTAssertEqual(a.engine.status, .disconnected)

        let key = LibraryKey.generate()
        a.engine.connect(libraryKey: key)
        let b = try makeDevice("B", key: key)

        try await waitUntil("B receives both series") {
            try Set(b.mangas().map(\.title)) == ["Monster", "Vagabond"]
        }
        XCTAssertTrue(try b.mangas().allSatisfy { $0.volumes.count == 1 && $0.volumes[0].owned })

        // Joining an existing library merges rather than replaces: a series
        // B adds shows up on A next to the ones it already had.
        let mine = Manga(title: "Vinland Saga", sortOrder: 2)
        b.context.insert(mine)
        try b.context.save()
        try await waitUntil("A receives Vinland Saga") {
            try a.mangas().count == 3
        }
    }

    func testUnsentLocalEditWinsOverIncomingVersion() async throws {
        let key = LibraryKey.generate()
        let a = try makeDevice("A", key: key)
        let b = try makeDevice("B", key: key)

        let manga = Manga(title: "Dorohedoro", sortOrder: 0)
        a.context.insert(manga)
        try a.context.save()
        try await waitUntil("B receives Dorohedoro") {
            try b.mangas().contains { $0.title == "Dorohedoro" }
        }
        try await waitUntil("queues drain") {
            a.engine.pendingCount == 0 && b.engine.pendingCount == 0
        }

        // Both edit the same series at once. Whichever version reaches the
        // server last wins on both sides — but neither device may end up
        // with a mix, and both must converge.
        let onB = try XCTUnwrap(b.mangas().first)
        manga.note = "from A"
        onB.note = "from B"
        try a.context.save()
        try b.context.save()

        try await waitUntil("both converge") {
            try a.engine.pendingCount == 0 && b.engine.pendingCount == 0
                && a.mangas().first?.note == b.mangas().first?.note
        }
        XCTAssertTrue(["from A", "from B"].contains(manga.note))
    }

    func testLibraryKeyRoundTrips() {
        let key = LibraryKey.generate()
        XCTAssertEqual(key.count, 24)
        XCTAssertEqual(LibraryKey.normalize(LibraryKey.formatted(key)), key)
        XCTAssertEqual(LibraryKey.normalize(key.lowercased()), key)
        XCTAssertNil(LibraryKey.normalize(String(key.dropLast())))
        XCTAssertNil(LibraryKey.normalize(key + "A"))
        XCTAssertNil(LibraryKey.normalize(key.replacingCharacters(in: key.startIndex ..< key.index(after: key.startIndex), with: "0")))
    }
}
