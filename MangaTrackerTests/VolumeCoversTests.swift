@testable import MangaTrackerIOS
import SwiftData
import XCTest

/// Picking one MangaDex cover per volume, and hanging the result on a
/// series. In-memory store, no network — `bestCoverURLs` takes the decoded
/// entries, so the choice can be tested without one.
@MainActor
final class VolumeCoversTests: XCTestCase {
    private var container: ModelContainer!

    private var context: ModelContext {
        container.mainContext
    }

    private let seriesID = "a77742b1-befd-49a4-bff5-1ad4e6b0ef7b"

    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Manga.self, Volume.self, VolumePart.self, configurations: configuration)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeManga(volumes count: Int) throws -> Manga {
        let manga = Manga(title: "Chainsaw Man")
        manga.volumes = (1 ... count).map { Volume(number: $0, owned: true, manga: manga) }
        context.insert(manga)
        try context.save()
        return manga
    }

    private func entry(_ volume: String?, _ locale: String?, _ file: String) -> MangaDexService.CoverEntry {
        MangaDexService.CoverEntry(volume: volume, fileName: file, locale: locale)
    }

    // MARK: - Choosing a cover

    func testPrefersEnglishOverJapanese() {
        let covers = MangaDexService.bestCoverURLs(seriesID: seriesID, from: [
            entry("1", "ja", "japanese.jpg"),
            entry("1", "en", "english.jpg"),
        ])

        XCTAssertEqual(covers.count, 1)
        XCTAssertEqual(covers[1], MangaDexService.coverURL(seriesID: seriesID, fileName: "english.jpg"))
    }

    /// Berserk and One Piece have no English covers at all, so Japanese has
    /// to be taken rather than leaving the volume blank.
    func testFallsBackToJapaneseWhenNoEnglishCoverExists() {
        let covers = MangaDexService.bestCoverURLs(seriesID: seriesID, from: [
            entry("1", "ja", "japanese.jpg"),
            entry("2", "ja", "japanese-2.jpg"),
        ])

        XCTAssertEqual(covers[1], MangaDexService.coverURL(seriesID: seriesID, fileName: "japanese.jpg"))
        XCTAssertEqual(covers[2], MangaDexService.coverURL(seriesID: seriesID, fileName: "japanese-2.jpg"))
    }

    func testUnlistedLocaleLosesToAPreferredOne() {
        let covers = MangaDexService.bestCoverURLs(seriesID: seriesID, from: [
            entry("1", "it", "italian.jpg"),
            entry("1", "ja", "japanese.jpg"),
        ])

        XCTAssertEqual(covers[1], MangaDexService.coverURL(seriesID: seriesID, fileName: "japanese.jpg"))
    }

    /// Nothing preferred uploaded a cover, so whatever exists is better than
    /// an empty row.
    func testUnlistedLocaleIsUsedWhenItIsTheOnlyOne() {
        let covers = MangaDexService.bestCoverURLs(seriesID: seriesID, from: [
            entry("1", "it", "italian.jpg"),
        ])

        XCTAssertEqual(covers[1], MangaDexService.coverURL(seriesID: seriesID, fileName: "italian.jpg"))
    }

    func testSkipsVolumesTheLibraryCannotNumber() {
        let covers = MangaDexService.bestCoverURLs(seriesID: seriesID, from: [
            entry("7.5", "en", "side-story.jpg"),
            entry("none", "en", "loose-chapters.jpg"),
            entry("", "en", "blank.jpg"),
            entry(nil, "en", "missing.jpg"),
            entry("8", "en", "eight.jpg"),
        ])

        XCTAssertEqual(covers.count, 1)
        XCTAssertEqual(covers[8], MangaDexService.coverURL(seriesID: seriesID, fileName: "eight.jpg"))
    }

    func testCoverURLAsksForTheThumbnailWidth() {
        XCTAssertEqual(
            MangaDexService.coverURL(seriesID: seriesID, fileName: "cover.jpg"),
            "https://uploads.mangadex.org/covers/\(seriesID)/cover.jpg.512.jpg"
        )
    }

    // MARK: - Applying to a series

    func testAppliesCoversByVolumeNumberAndIgnoresUnknownOnes() throws {
        let manga = try makeManga(volumes: 3)

        let applied = manga.applyVolumeCovers([1: "one.jpg", 3: "three.jpg", 9: "nine.jpg"])

        XCTAssertEqual(applied, 2)
        XCTAssertEqual(manga.volumes.first { $0.number == 1 }?.coverURL, "one.jpg")
        XCTAssertNil(manga.volumes.first { $0.number == 2 }?.coverURL)
        XCTAssertEqual(manga.volumes.first { $0.number == 3 }?.coverURL, "three.jpg")
    }

    /// Same rule as the series cover in `applyAniListInfo`: a refresh must
    /// not throw away a cover the user chose.
    func testKeepsAnExistingCoverUnlessOverwritingIsAsked() throws {
        let manga = try makeManga(volumes: 1)
        let volume = try XCTUnwrap(manga.volumes.first)
        volume.coverURL = "hand-picked.jpg"

        XCTAssertEqual(manga.applyVolumeCovers([1: "fetched.jpg"]), 0)
        XCTAssertEqual(volume.coverURL, "hand-picked.jpg")

        XCTAssertEqual(manga.applyVolumeCovers([1: "fetched.jpg"], overwrite: true), 1)
        XCTAssertEqual(volume.coverURL, "fetched.jpg")
    }

    func testApplyingTheSameCoversTwiceChangesNothing() throws {
        let manga = try makeManga(volumes: 2)

        XCTAssertEqual(manga.applyVolumeCovers([1: "one.jpg", 2: "two.jpg"]), 2)
        XCTAssertEqual(manga.applyVolumeCovers([1: "one.jpg", 2: "two.jpg"]), 0)
    }

    func testHasVolumeCoversOnlyOnceOneIsSet() throws {
        let manga = try makeManga(volumes: 2)
        XCTAssertFalse(manga.hasVolumeCovers)

        manga.applyVolumeCovers([2: "two.jpg"])
        XCTAssertTrue(manga.hasVolumeCovers)
    }

    // MARK: - Snapshot

    /// Covers are fetched on one device, so they have to reach the others
    /// through the sync snapshot — along with the resolved series id, which
    /// saves every other device the lookup.
    func testCoversAndSeriesIDSurviveTheSnapshotRoundTrip() throws {
        let manga = try makeManga(volumes: 2)
        manga.mangaDexId = seriesID
        manga.applyVolumeCovers([1: "one.jpg", 2: "two.jpg"])

        let data = try encodeMangasToJSON([manga])
        let restored = try XCTUnwrap(decodeMangasFromJSON(data).first)

        XCTAssertEqual(restored.mangaDexId, seriesID)
        XCTAssertEqual(restored.volumes.map(\.coverURL), ["one.jpg", "two.jpg"])

        let copy = Manga(exported: restored)
        XCTAssertEqual(copy.mangaDexId, seriesID)
        XCTAssertEqual(copy.volumes.sorted { $0.number < $1.number }.map(\.coverURL), ["one.jpg", "two.jpg"])
    }

    /// A snapshot from a device that has covers must land on one that
    /// doesn't, and count as a change exactly once.
    func testApplyingASnapshotBringsCoversInOnce() throws {
        let source = try makeManga(volumes: 2)
        source.mangaDexId = seriesID
        source.applyVolumeCovers([1: "one.jpg", 2: "two.jpg"])
        let snapshot = ExportedManga(source)

        let target = try makeManga(volumes: 2)
        XCTAssertTrue(target.apply(snapshot))
        XCTAssertEqual(target.volumes.sorted { $0.number < $1.number }.map(\.coverURL), ["one.jpg", "two.jpg"])
        XCTAssertEqual(target.mangaDexId, seriesID)

        XCTAssertFalse(target.apply(snapshot))
    }
}
