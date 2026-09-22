@testable import MangaTrackerIOS
import SwiftData
import XCTest

/// Splitting a volume into parts and what that does to reading state,
/// progress numbers and the sync snapshot. In-memory store, no backend.
@MainActor
final class VolumePartsTests: XCTestCase {
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

    /// A series with `count` owned volumes, saved.
    private func makeManga(volumes count: Int) throws -> Manga {
        let manga = Manga(title: "Berserk")
        manga.volumes = (1 ... count).map { Volume(number: $0, owned: true, manga: manga) }
        context.insert(manga)
        try context.save()
        return manga
    }

    private func volume(_ number: Int, of manga: Manga) throws -> Volume {
        try XCTUnwrap(manga.volumes.first { $0.number == number })
    }

    // MARK: - Splitting

    func testSplitCreatesUnreadPartsAndJoinRemovesThem() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)

        volume.setPartCount(3)
        try context.save()
        XCTAssertEqual(volume.sortedParts.map(\.index), [1, 2, 3])
        XCTAssertTrue(volume.parts.allSatisfy { !$0.read })
        XCTAssertEqual(volume.read, false)

        volume.setPartCount(1)
        try context.save()
        XCTAssertFalse(volume.isSplit)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VolumePart>()), 0, "joined parts are deleted, not orphaned")
    }

    func testSplittingAFinishedVolumeKeepsItFinished() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)
        let finished = Date(timeIntervalSince1970: 1_700_000_000)
        volume.markRead(true, on: finished)

        volume.setPartCount(3)
        XCTAssertTrue(volume.parts.allSatisfy(\.read))
        XCTAssertEqual(volume.parts.compactMap(\.readDate), [finished, finished, finished])
        XCTAssertEqual(volume.read, true)

        // Growing the split keeps what's there and adds parts as read as
        // the volume is; shrinking drops the highest ones.
        volume.setPartCount(4)
        XCTAssertEqual(volume.sortedParts.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(volume.read, true)
        volume.setPartCount(2)
        XCTAssertEqual(volume.sortedParts.map(\.index), [1, 2])
    }

    func testDeletingAVolumeCascadesToItsParts() throws {
        let manga = try makeManga(volumes: 2)
        let volume = try volume(1, of: manga)
        volume.setPartCount(3)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VolumePart>()), 3)

        manga.volumes.removeAll { $0.persistentModelID == volume.persistentModelID }
        context.delete(volume)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VolumePart>()), 0)
    }

    // MARK: - Reading

    func testVolumeIsReadOnceEveryPartIs() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)
        volume.owned = false
        volume.setPartCount(3)
        let parts = volume.sortedParts
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86400)

        volume.markPart(parts[0], read: true, on: day1)
        XCTAssertEqual(volume.read, false)
        XCTAssertNil(volume.readDate)
        XCTAssertTrue(volume.owned, "reading a part means owning the volume")
        XCTAssertEqual(volume.purchaseDate, day1)
        XCTAssertEqual(volume.readPartCount, 1)
        XCTAssertEqual(volume.firstUnreadPart?.index, 2)

        volume.markPart(parts[2], read: true, on: day2)
        volume.markPart(parts[1], read: true, on: day2)
        XCTAssertEqual(volume.read, true)
        XCTAssertEqual(volume.readDate, day2, "dated when the last part was finished")
        XCTAssertNil(volume.firstUnreadPart)

        volume.markPart(parts[1], read: false)
        XCTAssertEqual(volume.read, false)
        XCTAssertNil(volume.readDate)
        XCTAssertEqual(parts[2].readDate, day2, "other parts keep their dates")
    }

    func testMarkingTheVolumeAppliesToEveryPart() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)
        volume.setPartCount(3)

        volume.markRead(true)
        XCTAssertTrue(volume.parts.allSatisfy(\.read))
        XCTAssertTrue(volume.parts.allSatisfy { $0.readDate != nil })

        volume.markRead(false)
        XCTAssertTrue(volume.parts.allSatisfy { !$0.read && $0.readDate == nil })
        XCTAssertEqual(volume.read, false)

        volume.markPart(volume.sortedParts[0], read: true)
        volume.markOwned(false)
        XCTAssertTrue(volume.parts.allSatisfy { !$0.read }, "un-owning clears reading, parts included")
    }

    func testNextUnitToReadIsTheNextPart() throws {
        let manga = try makeManga(volumes: 2)
        let first = try volume(1, of: manga)
        first.setPartCount(3)
        first.markPart(first.sortedParts[0], read: true)

        manga.markNextAsRead()
        XCTAssertEqual(first.readPartCount, 2)
        XCTAssertEqual(first.read, false)

        first.markNextUnitRead()
        XCTAssertEqual(first.read, true)

        manga.markNextAsRead()
        XCTAssertEqual(try volume(2, of: manga).read, true, "an unsplit volume is read whole")
    }

    // MARK: - Numbers

    func testProgressCountsPartsButTilesCountVolumes() throws {
        let manga = try makeManga(volumes: 3)
        let first = try volume(1, of: manga)
        first.setPartCount(3)
        first.markPart(first.sortedParts[0], read: true)
        try volume(2, of: manga).markRead(true)

        let stats = manga.volumeStats
        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.read, 1)
        XCTAssertEqual(stats.totalUnits, 5)
        XCTAssertEqual(stats.readUnits, 2)
        XCTAssertEqual(stats.readPercent, 40, accuracy: 0.001)
        XCTAssertEqual(stats.nextUnread?.number, 1)
        XCTAssertEqual(stats.nextUnreadPart?.index, 2)
        XCTAssertFalse(stats.allRead)

        let library = MangaLibraryStats(mangas: [manga])
        XCTAssertEqual(library.ownedVolumesCount, 3)
        XCTAssertEqual(library.totalReadPercent, 40, accuracy: 0.001)
    }

    func testReadDaysComeFromPartsOfASplitVolume() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)
        volume.setPartCount(2)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        volume.markPart(volume.sortedParts[0], read: true, on: yesterday)
        volume.markPart(volume.sortedParts[1], read: true, on: today)

        let library = MangaLibraryStats(mangas: [manga])
        XCTAssertTrue(library.didReadToday)
        XCTAssertEqual(library.currentReadStreak, 2)
        XCTAssertEqual(volume.readDates.count, 2, "the volume's own date repeats the last part's and isn't counted again")
    }

    // MARK: - Snapshot

    func testSnapshotRoundTripsPartsAndLeavesThemOutForUnsplitVolumes() throws {
        let manga = try makeManga(volumes: 2)
        let first = try volume(1, of: manga)
        first.setPartCount(2)
        let finished = Date(timeIntervalSince1970: 1_700_000_000)
        first.markPart(first.sortedParts[1], read: true, on: finished)

        let exported = ExportedManga(manga)
        XCTAssertEqual(exported.volumes[0].parts?.map(\.index), [1, 2])
        XCTAssertEqual(exported.volumes[0].parts?.map(\.read), [false, true])
        XCTAssertNil(exported.volumes[1].parts, "an ordinary volume's snapshot is unchanged")

        let data = try encodeMangasToJSON([manga])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"parts\" : null"))
        let decoded = try XCTUnwrap(decodeMangasFromJSON(data).first)

        let copy = Manga(exported: decoded)
        context.insert(copy)
        try context.save()
        let copiedFirst = try volume(1, of: copy)
        XCTAssertEqual(copiedFirst.sortedParts.map(\.read), [false, true])
        XCTAssertEqual(copiedFirst.sortedParts[1].readDate, finished)
        XCTAssertFalse(try volume(2, of: copy).isSplit)
    }

    func testApplyingASnapshotReconcilesPartsByIndex() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try volume(1, of: manga)
        volume.setPartCount(3)
        try context.save()
        let original = volume.sortedParts

        // The other device read part 2 and shrank the split to two parts.
        var snapshot = ExportedManga(manga)
        snapshot.volumes[0].parts = [
            ExportedVolumePart(index: 1, read: false, readDate: nil),
            ExportedVolumePart(index: 2, read: true, readDate: Date(timeIntervalSince1970: 1_700_000_000)),
        ]
        XCTAssertTrue(manga.apply(snapshot))
        try context.save()

        XCTAssertEqual(volume.sortedParts.map(\.index), [1, 2])
        XCTAssertTrue(volume.sortedParts[1].read)
        XCTAssertEqual(volume.sortedParts[0].persistentModelID, original[0].persistentModelID, "matched by index, not replaced")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VolumePart>()), 2)
        XCTAssertFalse(manga.apply(snapshot), "applying the same snapshot again changes nothing")

        // A snapshot without parts joins the volume back.
        snapshot.volumes[0].parts = nil
        XCTAssertTrue(manga.apply(snapshot))
        XCTAssertFalse(volume.isSplit)
    }

    func testOldSnapshotsWithoutPartsStillDecode() throws {
        let json = """
        [{"title":"Monster","note":"","createdAt":"2024-01-01T00:00:00Z","volumes":[{"number":1,"owned":true}]}]
        """
        let decoded = try decodeMangasFromJSON(Data(json.utf8))
        XCTAssertNil(decoded[0].volumes[0].parts)
        let manga = Manga(exported: decoded[0])
        XCTAssertFalse(manga.volumes[0].isSplit)
    }
}
