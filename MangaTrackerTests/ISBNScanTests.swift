@testable import MangaTrackerIOS
import SwiftData
import XCTest

/// Scanning a volume's barcode: reading ISBNs and printed prices, the
/// National Library catalogue records, and finding the series and volume
/// in the library without duplicating anything. No network, no camera.
@MainActor
final class ISBNScanTests: XCTestCase {
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

    // MARK: - ISBN

    func testBarcodeAndPrintedFormsNormalizeToTheSameISBN() {
        XCTAssertEqual(ISBN.normalized("9788374712019"), "9788374712019")
        XCTAssertEqual(ISBN.normalized("978-83-7471-201-9"), "9788374712019")
        XCTAssertEqual(ISBN.normalized(" 978 83 7471 201 9 "), "9788374712019")
        // The same book's ISBN-10.
        XCTAssertEqual(ISBN.normalized("83-7471-201-5"), "9788374712019")
    }

    func testISBN10WithXCheckDigit() {
        XCTAssertEqual(ISBN.normalized("0-8044-2957-X"), "9780804429573")
    }

    func testMisreadsAndOtherBarcodesAreRejected() {
        XCTAssertNil(ISBN.normalized("9788374712018"), "wrong check digit")
        XCTAssertNil(ISBN.normalized("5901234123457"), "an ordinary EAN-13, not a book")
        XCTAssertNil(ISBN.normalized("97883747120"), "too short")
        XCTAssertNil(ISBN.normalized(""))
    }

    func testISBNsAreFoundInRecognizedText() {
        let text = "ISBN(całość):978-83-7471-200-2\nISBN(tom 1):978-83-7471-201-9"
        XCTAssertEqual(ISBN.all(in: text), ["9788374712002", "9788374712019"])
    }

    func testFormattedForDisplay() {
        XCTAssertEqual(ISBN.formatted("9788374712019"), "978-837471201-9")
    }

    // MARK: - Printed price

    func testPriceNextToTheBarcode() {
        XCTAssertEqual(PrintedPrice.parse("CENA: 25,20zł"), 25.20)
        XCTAssertEqual(PrintedPrice.parse("Cena 29,99 zł (w tym VAT 5%)"), 29.99)
        XCTAssertEqual(PrintedPrice.parse("cena:32.00 PLN"), 32)
        XCTAssertEqual(PrintedPrice.parse("19,99 ZŁ"), 19.99)
    }

    func testTextWithoutAPriceGivesNone() {
        XCTAssertNil(PrintedPrice.parse("(w tym VAT 5%)"))
        XCTAssertNil(PrintedPrice.parse("ISBN(tom 1):978-83-7471-201-9"))
        XCTAssertNil(PrintedPrice.parse("shonenjump.com"))
    }

    // MARK: - National Library records

    /// One Piece 1 (JPF): the volume has its own title; the series and
    /// number are in the series entries ("One piece", "t. 1").
    private let onePieceRecord = #"""
    {"nextPage":"","bibs":[{"id":2962606,"deleted":false,"isbnIssn":"9788374712002 9788374712019","marc":{"fields":[
      {"001":"b0000002962606"},
      {"020":{"ind1":" ","ind2":" ","subfields":[{"a":"9788374712002"}]}},
      {"020":{"ind1":" ","ind2":" ","subfields":[{"a":"9788374712019"}]}},
      {"100":{"ind1":"1","ind2":" ","subfields":[{"a":"Oda, Eiichiro"},{"d":"(1975- )"}]}},
      {"245":{"ind1":"1","ind2":"0","subfields":[{"a":"Romance Dawn - przygoda na horyzoncie /"},{"c":"Eiichiro Oda ; [tł. Paweł \"Rep\" Dybała]."}]}},
      {"260":{"ind1":" ","ind2":" ","subfields":[{"a":"Mierzyn :"},{"b":"Shin Yasuda Publishing House \"J. P. Fantastica\","},{"c":"2010."}]}},
      {"490":{"ind1":"1","ind2":" ","subfields":[{"a":"J. P. F. Comics"}]}},
      {"490":{"ind1":"1","ind2":" ","subfields":[{"a":"One piece / Eiichiro Oda ;"},{"v":"t. 1"}]}},
      {"500":{"ind1":" ","ind2":" ","subfields":[{"a":"Tyt. oryg.: One piece, 1997. Na książce także pseud. tł.: Rep."}]}},
      {"800":{"ind1":"1","ind2":" ","subfields":[{"a":"Oda, Eiichiro"},{"d":"(1975- )."},{"t":"One piece"},{"v":"t. 1"}]}},
      {"830":{"ind1":" ","ind2":"0","subfields":[{"a":"J. P. F. Manga Komiks Serial"}]}}
    ]}}]}
    """#

    /// Frieren 4 (Studio JG): numbered in the title itself, with a
    /// subtitle and the original title as a variant.
    private let frierenRecord = #"""
    {"bibs":[{"deleted":false,"isbnIssn":"9788382573213","marc":{"fields":[
      {"020":{"ind1":" ","ind2":" ","subfields":[{"a":"9788382573213"}]}},
      {"245":{"ind1":"1","ind2":"0","subfields":[{"a":"Frieren :"},{"b":"u kresu drogi."},{"n":"4 /"},{"c":"scenariusz: Kanehito Yamada ; ilustracje: Tsukasa Abe."}]}},
      {"246":{"ind1":"1","ind2":" ","subfields":[{"i":"Tytuł oryginału:"},{"a":"Sōsō no Furīren."},{"n":"Vol. 4,"},{"f":"2021"}]}},
      {"264":{"ind1":" ","ind2":"1","subfields":[{"a":"Warszawa :"},{"b":"Wydawnictwo Studio JG,"},{"c":"2023."}]}}
    ]}}]}
    """#

    func testVolumeNumberedThroughTheSeriesEntry() throws {
        let book = try XCTUnwrap(NationalLibraryService.parse(Data(onePieceRecord.utf8), isbn: "9788374712019"))
        XCTAssertEqual(book.seriesTitle, "One piece")
        XCTAssertEqual(book.volumeNumber, 1)
        XCTAssertEqual(book.volumeTitle, "Romance Dawn - przygoda na horyzoncie")
        XCTAssertEqual(book.originalTitle, "One piece")
        XCTAssertEqual(book.author, "Eiichiro Oda")
        XCTAssertEqual(book.publisher, #"Shin Yasuda Publishing House "J. P. Fantastica""#)
        XCTAssertEqual(book.otherISBNs, ["9788374712002"])
    }

    func testVolumeNumberedInItsTitle() throws {
        let book = try XCTUnwrap(NationalLibraryService.parse(Data(frierenRecord.utf8), isbn: "9788382573213"))
        XCTAssertEqual(book.seriesTitle, "Frieren: u kresu drogi")
        XCTAssertEqual(book.volumeNumber, 4)
        XCTAssertNil(book.volumeTitle)
        XCTAssertEqual(book.originalTitle, "Sōsō no Furīren")
        XCTAssertEqual(book.publisher, "Wydawnictwo Studio JG")
    }

    func testRecordForAnotherISBNIsIgnored() throws {
        XCTAssertNil(try NationalLibraryService.parse(Data(frierenRecord.utf8), isbn: "9788374712019"))
        XCTAssertNil(try NationalLibraryService.parse(Data(#"{"bibs":[]}"#.utf8), isbn: "9788374712019"))
    }

    // MARK: - Finding the series

    private func insert(_ title: String, volumes: [Int] = [], owned: Set<Int> = [], aniListId: Int? = nil) -> Manga {
        let manga = Manga(title: title, aniListId: aniListId)
        manga.volumes = volumes.map { Volume(number: $0, owned: owned.contains($0), manga: manga) }
        context.insert(manga)
        return manga
    }

    func testExactISBNWinsOverEverythingElse() {
        let byTitle = insert("One Piece")
        let byISBN = insert("Wan Pīsu", volumes: [1])
        byISBN.volumes[0].isbn = "9788374712019"

        let found = ScanMatcher.series(isbn: "9788374712019", titles: ["One piece"], aniListId: nil, in: [byTitle, byISBN])
        XCTAssertTrue(found === byISBN)
    }

    func testAniListIdThenTitle() {
        let frieren = insert("Frieren: Beyond Journey's End", aniListId: 118_586)
        let berserk = insert("Berserk")

        XCTAssertTrue(ScanMatcher.series(isbn: nil, titles: ["Frieren: u kresu drogi"], aniListId: 118_586, in: [berserk, frieren]) === frieren)
        // Case, accents and punctuation don't matter.
        XCTAssertTrue(ScanMatcher.series(isbn: nil, titles: ["BERSERK."], aniListId: nil, in: [frieren, berserk]) === berserk)
    }

    func testTitleBeforeTheColonMatchesWhenUnambiguous() {
        let frieren = insert("Frieren: Beyond Journey's End")
        XCTAssertTrue(ScanMatcher.series(isbn: nil, titles: ["Frieren: u kresu drogi"], aniListId: nil, in: [frieren]) === frieren)

        let other = insert("Frieren: Side Stories")
        XCTAssertNil(ScanMatcher.series(isbn: nil, titles: ["Frieren: u kresu drogi"], aniListId: nil, in: [frieren, other]))
    }

    func testNewSeriesMatchesNothing() {
        let berserk = insert("Berserk", aniListId: 30002)
        XCTAssertNil(ScanMatcher.series(isbn: "9788374712019", titles: ["One piece"], aniListId: 30013, in: [berserk]))
    }

    func testPolishLettersFold() {
        XCTAssertEqual(ScanMatcher.normalizedTitle("Łowcy Dusz: Księga"), "lowcy dusz ksiega")
    }

    // MARK: - Saving the volume

    func testOwnedVolumeIsNotDuplicated() throws {
        let manga = insert("One Piece", volumes: [1, 2], owned: [1])
        manga.volumes.first { $0.number == 1 }?.price = 20

        let result = manga.addScannedVolume(number: 1, isbn: "9788374712019", price: 25.2)

        XCTAssertEqual(result, .alreadyOwned)
        XCTAssertEqual(manga.volumes.filter { $0.number == 1 }.count, 1)
        let volume = try XCTUnwrap(manga.volumes.first { $0.number == 1 })
        XCTAssertEqual(volume.price, 20, "an owned volume's price is left alone")
        XCTAssertEqual(volume.isbn, "9788374712019", "but the ISBN is remembered")
    }

    func testListedVolumeIsMarkedBought() throws {
        let manga = insert("One Piece", volumes: [1, 2, 3])
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = manga.addScannedVolume(number: 2, isbn: "9788374712026", price: 25.2, purchaseDate: date)

        XCTAssertEqual(result, .markedOwned)
        XCTAssertEqual(manga.volumes.count, 3)
        let volume = try XCTUnwrap(manga.volumes.first { $0.number == 2 })
        XCTAssertTrue(volume.owned)
        XCTAssertEqual(volume.price, 25.2)
        XCTAssertEqual(volume.purchaseDate, date)
        XCTAssertEqual(volume.isbn, "9788374712026")
    }

    func testVolumeOnItsWayArrives() {
        let manga = insert("One Piece", volumes: [1])
        let volume = manga.volumes[0]
        let orderDate = Date(timeIntervalSince1970: 1_600_000_000)
        volume.isOrdered = true
        volume.purchaseDate = orderDate

        XCTAssertEqual(manga.addScannedVolume(number: 1, isbn: nil, price: nil), .markedOwned)
        XCTAssertTrue(volume.owned)
        XCTAssertFalse(volume.isOnItsWay)
        XCTAssertEqual(volume.purchaseDate, orderDate, "the order date stays the purchase date")
    }

    func testMissingVolumeIsAdded() throws {
        let manga = insert("One Piece", volumes: [1], owned: [1])

        XCTAssertEqual(manga.addScannedVolume(number: 5, isbn: "9788374712057", price: nil), .added)
        let volume = try XCTUnwrap(manga.volumes.first { $0.number == 5 })
        XCTAssertTrue(volume.owned)
        XCTAssertNil(volume.price)
        XCTAssertNotNil(volume.purchaseDate)

        // Scanning it again finds it by ISBN.
        XCTAssertEqual(manga.addScannedVolume(number: 5, isbn: "9788374712057", price: nil), .alreadyOwned)
        XCTAssertEqual(manga.volumes.count, 2)
    }

    // MARK: - Sync snapshot

    func testISBNSurvivesTheSnapshot() throws {
        let manga = insert("One Piece", volumes: [1, 2], owned: [1])
        manga.volumes.first { $0.number == 1 }?.isbn = "9788374712019"

        let data = try encodeMangasToJSON([manga])
        let decoded = try decodeMangasFromJSON(data)
        XCTAssertEqual(decoded[0].volumes.first { $0.number == 1 }?.isbn, "9788374712019")
        XCTAssertNil(decoded[0].volumes.first { $0.number == 2 }?.isbn)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(#""isbn" : null"#), "absent, not null")

        let copy = Manga(exported: decoded[0])
        XCTAssertEqual(copy.volumes.first { $0.number == 1 }?.isbn, "9788374712019")
    }

    func testSnapshotsFromBeforeISBNsStillDecode() throws {
        let old = #"""
        [{"title":"Berserk","note":"","createdAt":"2025-01-01T00:00:00Z",
          "volumes":[{"number":1,"owned":true,"price":30}]}]
        """#
        let decoded = try decodeMangasFromJSON(Data(old.utf8))
        XCTAssertNil(decoded[0].volumes[0].isbn)
        XCTAssertNil(Manga(exported: decoded[0]).volumes[0].isbn)
    }
}
