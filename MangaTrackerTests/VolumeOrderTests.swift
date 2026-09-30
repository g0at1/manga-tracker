@testable import MangaTrackerIOS
import SwiftData
import XCTest

/// Volumes ordered and on their way ("W drodze"): kept out of the
/// collection numbers until delivered, then bought in one go. In-memory
/// store, no backend.
@MainActor
final class VolumeOrderTests: XCTestCase {
    private var container: ModelContainer!

    private var context: ModelContext {
        container.mainContext
    }

    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Manga.self, Volume.self, VolumePart.self, configurations: configuration)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    /// A series with volumes 1…`count`, the first `owned` of them owned
    /// at 30 PLN each, saved.
    private func makeManga(volumes count: Int, owned: Int) throws -> Manga {
        let manga = Manga(title: "Berserk")
        manga.volumes = (1 ... count).map {
            Volume(number: $0, owned: $0 <= owned, price: $0 <= owned ? 30 : nil, manga: manga)
        }
        context.insert(manga)
        try context.save()
        return manga
    }

    private func volume(_ number: Int, of manga: Manga) throws -> Volume {
        try XCTUnwrap(manga.volumes.first { $0.number == number })
    }

    func testOrderedVolumesStayOutOfTheStats() throws {
        let manga = try makeManga(volumes: 4, owned: 2)
        let ordered = try volume(3, of: manga)
        ordered.markOrdered(true)
        ordered.price = 45

        let stats = manga.volumeStats
        XCTAssertEqual(stats.owned, 2)
        XCTAssertEqual(stats.onItsWay, 1)
        XCTAssertEqual(stats.totalPaid, 60, accuracy: 0.001, "an order's price only counts once it arrives")
        XCTAssertEqual(stats.firstMissing?.number, 4, "an ordered volume isn't missing")

        let library = MangaLibraryStats(mangas: [manga])
        XCTAssertEqual(library.ownedVolumesCount, 2)
        XCTAssertEqual(library.totalPaid, 60, accuracy: 0.001)
    }

    func testDeliveryMarksEveryOrderedVolumeOwnedKeepingTheOrderDate() throws {
        let manga = try makeManga(volumes: 4, owned: 1)
        let orderDay = Date(timeIntervalSince1970: 1_700_000_000)
        try volume(2, of: manga).markOrdered(true, on: orderDay)
        try volume(3, of: manga).markOrdered(true, on: orderDay)

        XCTAssertEqual(manga.markOrderDelivered(), 2)

        for number in [2, 3] {
            let arrived = try volume(number, of: manga)
            XCTAssertTrue(arrived.owned)
            XCTAssertFalse(arrived.isOnItsWay)
            XCTAssertEqual(arrived.purchaseDate, orderDay)
        }
        XCTAssertFalse(try volume(4, of: manga).owned, "volumes that weren't ordered are left alone")
        XCTAssertEqual(manga.volumeStats.owned, 3)
        XCTAssertEqual(manga.markOrderDelivered(), 0)
    }

    func testOwnedVolumesCantBeOrderedAndCancellingClearsTheDate() throws {
        let manga = try makeManga(volumes: 2, owned: 1)
        let owned = try volume(1, of: manga)
        owned.markOrdered(true)
        XCTAssertFalse(owned.isOnItsWay)
        XCTAssertTrue(owned.owned)

        let ordered = try volume(2, of: manga)
        ordered.markOrdered(true)
        XCTAssertNotNil(ordered.purchaseDate)
        ordered.markOrdered(false)
        XCTAssertFalse(ordered.isOnItsWay)
        XCTAssertNil(ordered.purchaseDate)
    }

    func testReadingOrUnowningAnOrderedVolumeEndsTheOrder() throws {
        let manga = try makeManga(volumes: 2, owned: 0)
        let read = try volume(1, of: manga)
        read.markOrdered(true)
        read.markRead(true)
        XCTAssertTrue(read.owned)
        XCTAssertFalse(read.isOnItsWay)

        let unowned = try volume(2, of: manga)
        unowned.markOrdered(true)
        unowned.markOwned(false)
        XCTAssertFalse(unowned.owned)
        XCTAssertFalse(unowned.isOnItsWay)
        XCTAssertNil(unowned.purchaseDate)
    }

    func testTypedPurchaseDateKeepsAnOrderOnItsWay() throws {
        let manga = try makeManga(volumes: 2, owned: 0)
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        let ordered = try volume(1, of: manga)
        ordered.markOrdered(true)
        ordered.setPurchaseDate(day)
        XCTAssertTrue(ordered.isOnItsWay)
        XCTAssertFalse(ordered.owned)
        XCTAssertEqual(ordered.purchaseDate, day)

        let plain = try volume(2, of: manga)
        plain.setPurchaseDate(day)
        XCTAssertTrue(plain.owned)
        XCTAssertEqual(plain.purchaseDate, day)
    }

    // MARK: - Snapshot

    func testSnapshotCarriesTheOrderAndLeavesItOutOtherwise() throws {
        let manga = try makeManga(volumes: 2, owned: 0)
        try volume(1, of: manga).markOrdered(true)

        let exported = ExportedManga(manga)
        XCTAssertEqual(exported.volumes[0].isOrdered, true)
        XCTAssertNil(exported.volumes[1].isOrdered, "an ordinary volume's snapshot is unchanged")

        let decoded = try XCTUnwrap(decodeMangasFromJSON(encodeMangasToJSON([manga])).first)
        let copy = Manga(exported: decoded)
        context.insert(copy)
        try context.save()
        XCTAssertTrue(try volume(1, of: copy).isOnItsWay)
        XCTAssertFalse(try volume(2, of: copy).isOnItsWay)
    }

    func testApplyingASnapshotSyncsTheOrderWithoutChurn() throws {
        let manga = try makeManga(volumes: 1, owned: 0)
        let volume = try volume(1, of: manga)
        volume.isOrdered = false
        var snapshot = ExportedManga(manga)
        XCTAssertFalse(manga.apply(snapshot), "false and a missing field both mean not ordered")

        // The other device ordered it.
        snapshot.volumes[0].isOrdered = true
        XCTAssertTrue(manga.apply(snapshot))
        XCTAssertTrue(volume.isOnItsWay)
        XCTAssertFalse(manga.apply(snapshot))

        // …and then it arrived there.
        snapshot.volumes[0].isOrdered = nil
        snapshot.volumes[0].owned = true
        XCTAssertTrue(manga.apply(snapshot))
        XCTAssertFalse(volume.isOnItsWay)
        XCTAssertTrue(volume.owned)
    }
}
